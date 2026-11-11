// T-148: the small, strict subset of deterministic CBOR (RFC 8949 §4.2.1)
// used by the backup header and the key slot (design note §2). Only unsigned
// integers, byte strings, text strings and maps, all definite length, all in
// shortest form. Everything else (negative integers, arrays, tags, floats,
// simple values, indefinite lengths, reserved additional info, non-shortest
// heads) is refused. No allocation exceeds the bytes actually present.

import 'dart:convert';
import 'dart:typed_data';

/// A violation of the strict encoding. Internal: callers map it to
/// `corruptHeader`. Carries no input bytes.
final class CborFormatException implements Exception {
  const CborFormatException();

  @override
  String toString() => 'CborFormatException';
}

const int _majorUint = 0;
const int _majorBytes = 2;
const int _majorText = 3;
const int _majorMap = 5;

/// Writes canonical CBOR.
final class CborWriter {
  final BytesBuilder _out = BytesBuilder(copy: true);

  void _head(int major, int value) {
    if (value < 0) throw ArgumentError.value(value, 'value', 'negative');
    final m = major << 5;
    if (value < 24) {
      _out.addByte(m | value);
    } else if (value < 0x100) {
      _out
        ..addByte(m | 24)
        ..addByte(value);
    } else if (value < 0x10000) {
      _out
        ..addByte(m | 25)
        ..addByte(value >> 8)
        ..addByte(value & 0xff);
    } else if (value < 0x100000000) {
      _out.addByte(m | 26);
      for (var s = 24; s >= 0; s -= 8) {
        _out.addByte((value >> s) & 0xff);
      }
    } else {
      _out.addByte(m | 27);
      for (var s = 56; s >= 0; s -= 8) {
        _out.addByte((value >> s) & 0xff);
      }
    }
  }

  void uint(int value) => _head(_majorUint, value);

  void bytes(List<int> value) {
    _head(_majorBytes, value.length);
    _out.add(value);
  }

  void text(String value) {
    final encoded = utf8.encode(value);
    _head(_majorText, encoded.length);
    _out.add(encoded);
  }

  void mapHeader(int entries) => _head(_majorMap, entries);

  Uint8List takeBytes() => _out.takeBytes();
}

/// Reads strict canonical CBOR from a fixed buffer. Every method throws
/// [CborFormatException] on any deviation.
final class CborReader {
  CborReader(this._data);

  final Uint8List _data;
  int _pos = 0;

  bool get atEnd => _pos == _data.length;

  int get remaining => _data.length - _pos;

  int _byte() {
    if (_pos >= _data.length) throw const CborFormatException();
    return _data[_pos++];
  }

  /// Reads a head of [major] and returns its argument (shortest form only).
  int _head(int major) {
    final initial = _byte();
    if (initial >> 5 != major) throw const CborFormatException();
    final info = initial & 0x1f;
    if (info < 24) return info;
    final int length;
    final int minimum;
    switch (info) {
      case 24:
        length = 1;
        minimum = 24;
      case 25:
        length = 2;
        minimum = 0x100;
      case 26:
        length = 4;
        minimum = 0x10000;
      case 27:
        length = 8;
        minimum = 0x100000000;
      default:
        // 28..30 reserved, 31 indefinite length: never allowed.
        throw const CborFormatException();
    }
    if (remaining < length) throw const CborFormatException();
    var value = 0;
    for (var i = 0; i < length; i++) {
      final b = _data[_pos++];
      // A uint64 above 2^63 - 1 does not fit a Dart int: refuse it.
      if (i == 0 && length == 8 && b >= 0x80) {
        throw const CborFormatException();
      }
      value = (value << 8) | b;
    }
    if (value < minimum) throw const CborFormatException();
    return value;
  }

  int readUint() => _head(_majorUint);

  int readMapHeader() => _head(_majorMap);

  /// A byte string of exactly [length] bytes.
  Uint8List readBytes(int length) {
    final n = _head(_majorBytes);
    if (n != length || n > remaining) throw const CborFormatException();
    final out = Uint8List.sublistView(_data, _pos, _pos + n);
    _pos += n;
    return Uint8List.fromList(out);
  }

  /// A UTF-8 text string of 1..[maxBytes] bytes (strict UTF-8).
  String readText({required int maxBytes}) {
    final n = _head(_majorText);
    if (n == 0 || n > maxBytes || n > remaining) {
      throw const CborFormatException();
    }
    final raw = Uint8List.sublistView(_data, _pos, _pos + n);
    _pos += n;
    try {
      return const Utf8Decoder(allowMalformed: false).convert(raw);
    } on FormatException {
      throw const CborFormatException();
    }
  }

  /// Expects the next map key to be exactly [key].
  void expectKey(int key) {
    if (readUint() != key) throw const CborFormatException();
  }
}
