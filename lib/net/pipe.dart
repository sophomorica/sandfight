import 'dart:typed_data';

abstract class BytePipe {
  void send(Uint8List payload);

  Stream<Uint8List> get inbound;

  Future<void> close();
}
