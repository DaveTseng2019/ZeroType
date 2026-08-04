import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/features/settings/presentation/pages/settings_page.dart';

void main() {
  // debugName 在 release build 回 null（見 physicalKeyLabel 的註解），
  // 這裡直接比對 usbHidUsage 算出來的字元，不依賴 debugName。
  test('字母鍵對應正確', () {
    expect(physicalKeyLabel(PhysicalKeyboardKey.keyA), 'A');
    expect(physicalKeyLabel(PhysicalKeyboardKey.keyZ), 'Z');
  });

  test('數字鍵對應正確', () {
    expect(physicalKeyLabel(PhysicalKeyboardKey.digit1), '1');
    expect(physicalKeyLabel(PhysicalKeyboardKey.digit0), '0');
  });

  test('功能鍵對應正確', () {
    expect(physicalKeyLabel(PhysicalKeyboardKey.f1), 'F1');
    expect(physicalKeyLabel(PhysicalKeyboardKey.f12), 'F12');
  });

  test('特殊鍵對應正確', () {
    expect(physicalKeyLabel(PhysicalKeyboardKey.space), 'Space');
    expect(physicalKeyLabel(PhysicalKeyboardKey.enter), 'Enter');
  });

  test('沒對應到的鍵退回 16 進位代碼，不是空字串', () {
    final label = physicalKeyLabel(PhysicalKeyboardKey.f13);
    expect(label, isNotEmpty);
    expect(label, startsWith('Key 0x'));
  });
}
