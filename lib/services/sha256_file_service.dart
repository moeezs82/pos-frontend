import 'dart:io';
import 'dart:typed_data';

/// Small streaming SHA-256 implementation used by the updater.
///
/// Kept inside CounterIQ so updater verification does not require adding a
/// dependency to the application's pubspec just for hashing installers.
class Sha256FileService {
  const Sha256FileService._();

  static Future<String> hashFile(File file) async {
    final digest = _Sha256Digest();
    await for (final chunk in file.openRead()) {
      digest.add(chunk);
    }
    return digest.close();
  }
}

class _Sha256Digest {
  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final List<int> _h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _totalLength = 0;
  bool _closed = false;

  void add(List<int> data) {
    if (_closed) throw StateError('SHA-256 digest is already closed.');
    if (data.isEmpty) return;

    _totalLength += data.length;
    _buffer.add(data);
    _processBufferedBlocks();
  }

  String close() {
    if (_closed) throw StateError('SHA-256 digest is already closed.');
    _closed = true;

    final remainder = _buffer.takeBytes();
    final bitLength = _totalLength * 8;
    final padLength = ((56 - ((_totalLength + 1) % 64)) + 64) % 64;
    final padded = Uint8List(remainder.length + 1 + padLength + 8);
    padded.setRange(0, remainder.length, remainder);
    padded[remainder.length] = 0x80;

    for (var i = 0; i < 8; i++) {
      padded[padded.length - 1 - i] = (bitLength >> (8 * i)) & 0xff;
    }

    for (var offset = 0; offset < padded.length; offset += 64) {
      _processBlock(padded, offset);
    }

    return _h.map((value) => value.toUnsigned(32).toRadixString(16).padLeft(8, '0')).join();
  }

  void _processBufferedBlocks() {
    final bytes = _buffer.takeBytes();
    final fullLength = bytes.length - (bytes.length % 64);

    for (var offset = 0; offset < fullLength; offset += 64) {
      _processBlock(bytes, offset);
    }

    if (fullLength < bytes.length) {
      _buffer.add(bytes.sublist(fullLength));
    }
  }

  void _processBlock(List<int> block, int offset) {
    final w = Uint32List(64);
    for (var i = 0; i < 16; i++) {
      final j = offset + (i * 4);
      w[i] = ((block[j] << 24) |
              (block[j + 1] << 16) |
              (block[j + 2] << 8) |
              block[j + 3])
          .toUnsigned(32);
    }

    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1).toUnsigned(32);
    }

    var a = _h[0];
    var b = _h[1];
    var c = _h[2];
    var d = _h[3];
    var e = _h[4];
    var f = _h[5];
    var g = _h[6];
    var h = _h[7];

    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final temp1 = (h + s1 + ch + _k[i] + w[i]).toUnsigned(32);
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj).toUnsigned(32);

      h = g;
      g = f;
      f = e;
      e = (d + temp1).toUnsigned(32);
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2).toUnsigned(32);
    }

    _h[0] = (_h[0] + a).toUnsigned(32);
    _h[1] = (_h[1] + b).toUnsigned(32);
    _h[2] = (_h[2] + c).toUnsigned(32);
    _h[3] = (_h[3] + d).toUnsigned(32);
    _h[4] = (_h[4] + e).toUnsigned(32);
    _h[5] = (_h[5] + f).toUnsigned(32);
    _h[6] = (_h[6] + g).toUnsigned(32);
    _h[7] = (_h[7] + h).toUnsigned(32);
  }

  static int _rotr(int value, int shift) {
    final v = value.toUnsigned(32);
    return ((v >> shift) | (v << (32 - shift))).toUnsigned(32);
  }
}
