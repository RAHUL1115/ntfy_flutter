import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/update_check.dart';

void main() {
  test(
    'release comparison handles patch, minor, major, and build versions',
    () {
      expect(isNewerRelease('0.1.23', '0.1.22'), isTrue);
      expect(isNewerRelease('0.2.0', '0.1.99'), isTrue);
      expect(isNewerRelease('1.0.0', '0.99.99'), isTrue);
      expect(isNewerRelease('0.1.22', '0.1.22+23'), isFalse);
      expect(isNewerRelease('0.1.21', '0.1.22'), isFalse);
    },
  );
}
