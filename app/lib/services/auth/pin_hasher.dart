import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// PBKDF2-HMAC-SHA256 hashing for PINs.
///
/// Stored format: `pbkdf2_sha256$<iterations>$<salt b64>$<hash b64>`, so the
/// iteration count can be raised later without breaking old accounts.
///
/// A 4-6 digit PIN cannot resist an offline brute-force attack whatever the
/// iteration count; the hash stops PINs being readable in a copied database,
/// while Android's app sandbox and the login lockout do the real protecting.
class PinHasher {
  const PinHasher({this.iterations = defaultIterations});

  static const defaultIterations = 60000;
  static const _scheme = 'pbkdf2_sha256';

  final int iterations;

  /// Hashes on a background isolate so the UI does not freeze.
  Future<String> hash(String pin, {Uint8List? salt}) {
    final s = salt ?? _randomSalt();
    return compute(_hashSync, (pin, s, iterations));
  }

  Future<bool> verify(String pin, String stored) =>
      compute(_verifySync, (pin, stored));

  static Uint8List _randomSalt() {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
  }
}

String _hashSync((String, Uint8List, int) args) {
  final (pin, salt, iterations) = args;
  final dk = pbkdf2Sha256(utf8.encode(pin), salt, iterations, 32);
  return '${PinHasher._scheme}\$$iterations\$${base64.encode(salt)}\$${base64.encode(dk)}';
}

bool _verifySync((String, String) args) {
  final (pin, stored) = args;
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != PinHasher._scheme) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final salt = base64.decode(parts[2]);
  final want = base64.decode(parts[3]);
  final got = pbkdf2Sha256(utf8.encode(pin), salt, iterations, want.length);
  // Constant-time comparison.
  var diff = got.length ^ want.length;
  for (var i = 0; i < got.length && i < want.length; i++) {
    diff |= got[i] ^ want[i];
  }
  return diff == 0;
}

/// RFC 8018 PBKDF2 with HMAC-SHA256.
@visibleForTesting
Uint8List pbkdf2Sha256(
  List<int> password,
  List<int> salt,
  int iterations,
  int length,
) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder();
  for (var block = 1; out.length < length; block++) {
    final first = [
      ...salt,
      block >> 24 & 0xff,
      block >> 16 & 0xff,
      block >> 8 & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert(first).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, length));
}
