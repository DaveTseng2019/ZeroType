import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/services/hotkey_service.dart';

// 熱鍵被其他程式佔用時，使用者要看得到。套件自己不回報失敗，所以服務要自己標出來。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    // hotkey_manager 的 method channel：只記錄呼叫，一律回報成功（和真實套件的行為一樣）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/hotkey_manager'),
      (call) async {
        if (call.method == 'register') {
          calls.add('register:${call.arguments['keyCode']}');
        }
        return true;
      },
    );
  });

  Future<HotkeyService> make(HotkeyProbe probe) async {
    final prefs = await SharedPreferences.getInstance();
    final s = HotkeyService(prefs: prefs, probe: probe);
    await s.initialize();
    return s;
  }

  test('被佔用的熱鍵記進 conflicts，而且不會交給套件註冊', () async {
    // 預設熱鍵：錄音 Alt+Z、精簡 Alt+X、詞彙 Alt+C。讓 Alt+X 註冊不到。
    final s = await make((k) => k.physicalKey != PhysicalKeyboardKey.keyX);
    expect(s.conflicts.value, {HotkeyKind.quick});
    expect(calls.length, 2, reason: '只有沒被佔用的兩組該註冊');
  });

  test('沒有衝突時 conflicts 是空的，三組都註冊', () async {
    final s = await make((_) => true);
    expect(s.conflicts.value, isEmpty);
    expect(calls.length, 3);
  });

  test('換成可用的熱鍵後警告消失', () async {
    var blocked = true;
    final s = await make((k) => !(blocked && k.physicalKey == PhysicalKeyboardKey.keyX));
    expect(s.conflicts.value, {HotkeyKind.quick});

    blocked = false;
    await s.updateHotkey(
      HotkeyKind.quick,
      HotKey(
        key: PhysicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
    );
    expect(s.conflicts.value, isEmpty);
  });
}
