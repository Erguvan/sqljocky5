library sqljocky.query_stream_handler;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:sqljocky5/constants.dart';
import 'package:sqljocky5/comm/buffer.dart';

import '../handlers/handler.dart';
import '../handlers/ok_packet.dart';

import '../results/row.dart';
import '../results/field.dart';
import '../results/results_impl.dart';

import 'result_set_header_packet.dart';
import 'package:sqljocky5/results/standard_data_packet.dart';

class QueryStreamHandler extends Handler {
  static const int STATE_HEADER_PACKET = 0;
  static const int STATE_FIELD_PACKETS = 1;
  static const int STATE_ROW_PACKETS = 2;
  final String _sql;
  int _state = STATE_HEADER_PACKET;

  OkPacket _okPacket;
  ResultSetHeaderPacket _resultSetHeaderPacket;
  final fieldPackets = <Field>[];

  Map<String, int> _fieldIndex;

  StreamController<Row> _streamController;

  QueryStreamHandler(String this._sql)
      : super(new Logger("QueryStreamHandler"));

  Buffer createRequest() {
    var encoded = utf8.encode(_sql);
    var buffer = new Buffer(encoded.length + 1);
    buffer.writeByte(COM_QUERY);
    buffer.writeList(encoded);
    return buffer;
  }

  HandlerResponse processResponse(Buffer response) {
    log.fine("Processing query response");
    var packet = checkResponse(response, false, _state == STATE_ROW_PACKETS);
    if (packet == null) {
      if (response[0] == PACKET_EOF) {
        if (_state == STATE_FIELD_PACKETS) {
          return _handleEndOfFields();
        } else if (_state == STATE_ROW_PACKETS) {
          return _handleEndOfRows();
        }
      } else {
        switch (_state) {
          case STATE_HEADER_PACKET:
            _handleHeaderPacket(response);
            break;
          case STATE_FIELD_PACKETS:
            _handleFieldPacket(response);
            break;
          case STATE_ROW_PACKETS:
            _handleRowPacket(response);
            break;
        }
      }
    } else if (packet is OkPacket) {
      return _handleOkPacket(packet);
    }
    return HandlerResponse.notFinished;
  }

  _handleEndOfFields() {
    _state = STATE_ROW_PACKETS;
    _streamController = new StreamController<Row>(onCancel: () {
      _streamController.close();
    });
    this._fieldIndex = createFieldIndex();
    return new HandlerResponse(
        result: new ResultsStream(null, null, fieldPackets,
            stream: _streamController.stream));
  }

  _handleEndOfRows() {
    // the connection's _handler field needs to have been nulled out before the stream is closed,
    // otherwise the stream will be reused in an unfinished state.
    // TODO: can we use Future.delayed elsewhere, to make reusing connections nicer?
//    new Future.delayed(new Duration(seconds: 0), _streamController.close);
    _streamController.close();
    return new HandlerResponse(finished: true);
  }

  _handleHeaderPacket(Buffer response) {
    _resultSetHeaderPacket = new ResultSetHeaderPacket(response);
    log.fine(_resultSetHeaderPacket.toString());
    _state = STATE_FIELD_PACKETS;
  }

  _handleFieldPacket(Buffer response) {
    var fieldPacket = new Field.fromBuffer(response);
    log.fine(fieldPacket.toString());
    fieldPackets.add(fieldPacket);
  }

  _handleRowPacket(Buffer response) {
    List<dynamic> values = parseStandardDataResponse(response, fieldPackets);
    var row = new Row(values, _fieldIndex);
    log.fine(row.toString());
    _streamController.add(row);
  }

  _handleOkPacket(packet) {
    _okPacket = packet;
    var finished = false;
    // TODO: I think this is to do with multiple queries. Will probably break.
    if ((packet.serverStatus & SERVER_MORE_RESULTS_EXISTS) == 0) {
      finished = true;
    }

    //TODO is this finished value right?
    return new HandlerResponse(
        finished: finished,
        result: new ResultsStream(
            _okPacket.insertId, _okPacket.affectedRows, fieldPackets));
  }

  Map<String, int> createFieldIndex() {
    var identifierPattern = new RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');
    var fieldIndex = new Map<String, int>();
    for (var i = 0; i < fieldPackets.length; i++) {
      var name = fieldPackets[i].name;
      if (identifierPattern.hasMatch(name)) {
        fieldIndex[name] = i;
      }
    }
    return fieldIndex;
  }

  @override
  String toString() {
    return "QueryStreamHandler($_sql)";
  }
}
