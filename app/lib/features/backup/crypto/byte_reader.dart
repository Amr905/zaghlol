// T-148: exact-size reads over a byte stream, pulling one source event at a
// time (StreamIterator pauses the source between events), so the decryptor
// reads no further than it needs: a wrong passphrase stops before any chunk
// is pulled. A source error is `io`. Pure Dart.

import 'dart:async';
import 'dart:typed_data';

import 'backup_crypto_exception.dart';

final class ByteReader {
  ByteReader(Stream<List<int>> source)
    : _it = StreamIterator<List<int>>(source);

  final StreamIterator<List<int>> _it;
  List<int> _current = const [];
  int _offset = 0;
  bool _done = false;

  /// Pulls the next non-empty event. False at end of stream.
  Future<bool> _fill() async {
    while (_offset >= _current.length) {
      if (_done) return false;
      final bool more;
      try {
        more = await _it.moveNext();
      } on Object {
        _done = true;
        throw BackupCryptoException(BackupCryptoErrorCode.io);
      }
      if (!more) {
        _done = true;
        _current = const [];
        _offset = 0;
        return false;
      }
      _current = _it.current;
      _offset = 0;
    }
    return true;
  }

  /// Reads up to [n] bytes; fewer only at end of stream. [n] is chosen by the
  /// caller (≤ 4096 for the header, ≤ chunkSize + 16 for chunks), never by
  /// the input.
  Future<Uint8List> read(int n) async {
    final out = Uint8List(n);
    var got = 0;
    while (got < n) {
      if (!await _fill()) break;
      final take = (n - got) < (_current.length - _offset)
          ? n - got
          : _current.length - _offset;
      out.setRange(got, got + take, _current, _offset);
      got += take;
      _offset += take;
    }
    return got == n ? out : Uint8List.sublistView(out, 0, got);
  }

  /// True when no byte is left. May pull one more source event.
  Future<bool> get atEnd async => !await _fill();

  /// Stops reading and cancels the source. Never throws.
  Future<void> cancel() async {
    _done = true;
    try {
      await _it.cancel();
    } on Object {
      // Best effort.
    }
  }
}
