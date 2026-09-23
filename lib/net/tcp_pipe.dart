import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pipe.dart';

class FrameReader {
  final _buf = <int>[];

  List<Uint8List> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Uint8List>[];
    while (_buf.length >= 4) {
      final len = (_buf[0] << 24) | (_buf[1] << 16) | (_buf[2] << 8) | _buf[3];
      if (len < 0 || len > 20000) {
        _buf.clear();
        break;
      }
      if (_buf.length < 4 + len) break;
      out.add(Uint8List.fromList(_buf.sublist(4, 4 + len)));
      _buf.removeRange(0, 4 + len);
    }
    return out;
  }
}

Uint8List framePayload(Uint8List payload) {
  final out = Uint8List(4 + payload.length);
  final view = ByteData.sublistView(out);
  view.setUint32(0, payload.length);
  out.setRange(4, out.length, payload);
  return out;
}

class TcpPipe implements BytePipe {
  TcpPipe(this._socket) {
    _socket.listen((chunk) {
      for (final frame in _reader.add(chunk)) {
        if (!_inbound.isClosed) _inbound.add(frame);
      }
    }, onDone: () {
      if (!_inbound.isClosed) _inbound.close();
    });
  }

  static const port = 47631;

  final Socket _socket;
  final _reader = FrameReader();
  final _inbound = StreamController<Uint8List>(sync: true);

  static Future<TcpPipe> connect({int attempts = 40}) async {
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 200));
        return TcpPipe(socket);
      } catch (error) {
        last = error;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    throw StateError('no host sim on 127.0.0.1:$port ($last)');
  }

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  void send(Uint8List payload) {
    _socket.add(framePayload(payload));
  }

  @override
  Future<void> close() async {
    await _socket.close();
    if (!_inbound.isClosed) await _inbound.close();
  }
}

class TcpHost {
  ServerSocket? _server;

  Future<TcpPipe> waitForGuest() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, TcpPipe.port);
    _server = server;
    try {
      final socket = await server.first;
      return TcpPipe(socket);
    } finally {
      await server.close();
      _server = null;
    }
  }

  Future<void> cancel() async {
    await _server?.close();
  }
}
