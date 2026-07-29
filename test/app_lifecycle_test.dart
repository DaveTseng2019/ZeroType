import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/app_lifecycle.dart';

void main() {
  test('第二次啟動會被擋下', () async {
    var notified = 0;

    // 第一個實例:搶到鎖,視為唯一實例
    expect(await ensureSingleInstance(onSecondLaunch: () => notified++), isTrue);

    // 第二個實例:搶不到鎖,必須回 false 讓呼叫端退出
    expect(await ensureSingleInstance(onSecondLaunch: () => notified++), isFalse);

    // socket 版要靠通知第一個實例才會把視窗叫出來,否則使用者按捷徑會沒反應。
    // Windows 走 mutex + FindWindow,由後啟動的行程自己叫視窗,不會有通知。
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(notified, Platform.isWindows ? 0 : 1);
  });
}
