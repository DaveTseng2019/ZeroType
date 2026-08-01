import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/utils/version_compare.dart';

void main() {
  test('版本比較以數值逐段比較，不是字串比較', () {
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
    expect(isNewerVersion('1.0.9', '1.0.10'), isFalse);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('1.0.3', '1.0.3'), isFalse);
    expect(isNewerVersion('1.0.3', '1.0.4'), isFalse);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
  });
}
