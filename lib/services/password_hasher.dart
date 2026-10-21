import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 password hashing with a random 16-byte salt.
/// Stored format: `pbkdf2_sha256$<iterations>$<saltBase64>$<hashBase64>`.
class PasswordHasher {
  final int iterations;
  const PasswordHasher({this.iterations = 120000});

  Future<String> hash(String password) async {
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    final it = iterations;
    final dk = await Isolate.run(() => pbkdf2(utf8.encode(password), salt, it, 32));
    return 'pbkdf2_sha256\$$it\$${base64.encode(salt)}\$${base64.encode(dk)}';
  }

  Future<bool> verify(String password, String stored) async {
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final it = int.tryParse(parts[1]);
    if (it == null || it < 1) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final dk = await Isolate.run(() => pbkdf2(utf8.encode(password), salt, it, expected.length));
    return constantTimeEquals(dk, expected);
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength + 31) ~/ 32;
    final out = BytesBuilder();
    for (var i = 1; i <= blocks; i++) {
      var u = hmac.convert([...salt, (i >> 24) & 255, (i >> 16) & 255, (i >> 8) & 255, i & 255]).bytes;
      final t = Uint8List.fromList(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.takeBytes().sublist(0, keyLength));
  }

  /// Basic password policy. Returns an error message or null when acceptable.
  static String? validatePolicy(String password) {
    if (password.length < 8) return 'Password must be at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'\d').hasMatch(password)) {
      return 'Password must contain letters and numbers.';
    }
    return null;
  }
}
