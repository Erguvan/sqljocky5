library sqljocky.ssl_handler;

import 'package:logging/logging.dart';

import 'package:typed_buffer/typed_buffer.dart';
import '../handlers/handler.dart';

class SSLHandler extends Handler {
  final int clientFlags;
  final int maxPacketSize;
  final int characterSet;

  final Handler nextHandler;

  SSLHandler(
      this.clientFlags, this.maxPacketSize, this.characterSet, this.nextHandler)
      : super(new Logger("SSLHandler"));

  Uint8List createRequest() {
    var buffer = new FixedWriteBuffer(32);
    buffer.seekWrite(0);
    buffer.uint32 = clientFlags;
    buffer.uint32 = maxPacketSize;
    buffer.byte = characterSet;
    buffer.fill(23, 0);

    return buffer.data;
  }
}
