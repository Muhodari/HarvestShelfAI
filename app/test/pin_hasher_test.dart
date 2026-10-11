import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harvestshelf/services/auth/pin_hasher.dart';

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Expected values from Python's hashlib.pbkdf2_hmac('sha256', ...).
void main() {
  const vectors = [
    (
      'password',
      'salt',
      1,
      32,
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    ),
    (
      'password',
      'salt',
      2,
      32,
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    ),
    (
      'password',
      'salt',
      4096,
      32,
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    ),
    (
      'passwordPASSWORDpassword',
      'saltSALTsaltSALTsaltSALTsaltSALTsalt',
      4096,
      40,
      '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
    ),
    (
      '2580',
      'harvestshelf-salt',
      60000,
      32,
      'b64534b239a62361cec2af8ce1095f1b8d857a773d0da3de23f22bf88652a7da',
    ),
  ];

  for (final (pw, salt, c, n, want) in vectors) {
    test('PBKDF2-HMAC-SHA256 $pw/$salt c=$c', () {
      expect(hex(pbkdf2Sha256(utf8.encode(pw), utf8.encode(salt), c, n)), want);
    });
  }

  test('hash then verify; wrong PIN fails; salts differ', () async {
    const h = PinHasher(iterations: 1000);
    final a = await h.hash('2580');
    final b = await h.hash('2580');
    expect(a, startsWith(r'pbkdf2_sha256$1000$'));
    expect(a, isNot(b));
    expect(await h.verify('2580', a), isTrue);
    expect(await h.verify('2581', a), isFalse);
    expect(await h.verify('2580', 'garbage'), isFalse);
  });

  test('timing of default iterations (informational)', () async {
    final sw = Stopwatch()..start();
    await const PinHasher().hash('2580');
    // ignore: avoid_print
    print(
      'PBKDF2 ${PinHasher.defaultIterations} iterations: ${sw.elapsedMilliseconds} ms (host)',
    );
  });
}
