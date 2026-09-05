import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef HotkeyCallback = Future<void> Function();

/// 三組全域熱鍵。[prefsKey] 是它在 SharedPreferences 裡的鍵名，改名會讓
/// 使用者已經設好的熱鍵退回預設值。
enum HotkeyKind {
  /// 一般錄音：按一次開始，再按一次停止
  record('global_hotkey'),

  /// 精簡模式：講完自動停、貼上後自動送出
  quick('quick_hotkey'),

  /// 常用詞彙選擇器：不用開口，挑一句直接貼上
  phrase('phrase_hotkey');

  const HotkeyKind(this.prefsKey);

  final String prefsKey;
}

class HotkeyService {
  HotkeyService({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  static final Map<HotkeyKind, HotKey> _defaults = {
    HotkeyKind.record: HotKey(
      key: PhysicalKeyboardKey.keyZ,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    ),
    HotkeyKind.quick: HotKey(
      key: PhysicalKeyboardKey.keyX,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    ),
    HotkeyKind.phrase: HotKey(
      key: PhysicalKeyboardKey.keyC,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    ),
  };

  final Map<HotkeyKind, HotKey> _hotkeys = {};
  final Map<HotkeyKind, HotkeyCallback> _callbacks = {};
  bool _isPaused = false;

  HotKey hotkeyOf(HotkeyKind kind) => _hotkeys[kind] ?? _defaults[kind]!;

  Future<void> initialize() async {
    for (final kind in HotkeyKind.values) {
      _hotkeys[kind] = _load(kind);
    }
    print('[HotkeyService] Initialized with hotkeys: $_hotkeys');
    await hotKeyManager.unregisterAll();
    _isPaused = false;
    await _registerCurrent();
  }

  HotKey _load(HotkeyKind kind) {
    final json = _prefs.getString(kind.prefsKey);
    if (json != null) {
      try {
        final Map<String, dynamic> map = jsonDecode(json);
        final saved = HotKey.fromJson(map);
        // notes: 舊版曾允許存下「單獨修飾鍵」(如單按右 Win)，那種熱鍵註冊後擋不住
        // 開始選單，載入時直接丟掉退回預設值。
        if (!_isModifierOnly(saved)) return saved;
        print('[HotkeyService] Discarding modifier-only hotkey: $saved');
      } catch (e) {
        print('[HotkeyService] Error loading hotkey: $e');
      }
    }
    return _defaults[kind]!;
  }

  static bool _isModifierOnly(HotKey hotkey) {
    final modifierKeys = {
      PhysicalKeyboardKey.metaLeft,
      PhysicalKeyboardKey.metaRight,
      PhysicalKeyboardKey.controlLeft,
      PhysicalKeyboardKey.controlRight,
      PhysicalKeyboardKey.altLeft,
      PhysicalKeyboardKey.altRight,
      PhysicalKeyboardKey.shiftLeft,
      PhysicalKeyboardKey.shiftRight,
    };
    return modifierKeys.contains(hotkey.key);
  }

  Future<void> _saveHotkey(HotkeyKind kind, HotKey hotkey) async {
    try {
      await _prefs.setString(kind.prefsKey, jsonEncode(hotkey.toJson()));
    } catch (e) {
      print('[HotkeyService] Error saving hotkey: $e');
    }
  }

  void setCallback(HotkeyKind kind, HotkeyCallback callback) {
    _callbacks[kind] = callback;
  }

  Future<void> updateHotkey(HotkeyKind kind, HotKey newKey) async {
    print('[HotkeyService] Updating ${kind.name} hotkey to $newKey');
    // More reliable to unregister all for this app
    await hotKeyManager.unregisterAll();
    _hotkeys[kind] = newKey;
    await _saveHotkey(kind, newKey);

    // Only register if we're not currently paused
    if (!_isPaused) {
      await _registerCurrent();
    }
  }

  Future<void> _registerCurrent() async {
    print('[HotkeyService] Registering: $_hotkeys');
    for (final kind in HotkeyKind.values) {
      await hotKeyManager.register(
        hotkeyOf(kind),
        keyDownHandler: (_) {
          if (_isPaused) return; // Dart-level guard against in-flight callbacks
          print('[HotkeyService] ${kind.name} hotkey activated!');
          _callbacks[kind]?.call();
        },
      );
    }
  }

  Future<void> pause() async {
    if (_isPaused) return;
    _isPaused = true; // Set immediately to block any in-flight callbacks
    print('[HotkeyService] Pausing all hotkeys...');
    await hotKeyManager.unregisterAll();
  }

  Future<void> resume() async {
    if (!_isPaused) return;
    print('[HotkeyService] Resuming hotkey...');
    await _registerCurrent();
    _isPaused = false;
  }

  Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
  }
}
