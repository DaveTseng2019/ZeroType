import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef HotkeyCallback = Future<void> Function();

class HotkeyService {
  HotkeyService({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;
  static const String _hotkeyKey = 'global_hotkey';
  
  late HotKey _currentHotkey;
  HotkeyCallback? _onActivated;
  bool _isPaused = false;

  HotKey get currentHotkey => _currentHotkey;

  Future<void> initialize() async {
    await _loadPersistedHotkey();
    print('[HotkeyService] Initialized with hotkey: $_currentHotkey');
    await hotKeyManager.unregisterAll();
    _isPaused = false;
    await _registerCurrent();
  }

  Future<void> _loadPersistedHotkey() async {
    final json = _prefs.getString(_hotkeyKey);
    if (json != null) {
      try {
        final Map<String, dynamic> map = jsonDecode(json);
        final saved = HotKey.fromJson(map);
        // notes: 舊版曾允許存下「單獨修飾鍵」(如單按右 Win)，那種熱鍵註冊後擋不住
        // 開始選單，載入時直接丟掉退回預設值。
        if (!_isModifierOnly(saved)) {
          _currentHotkey = saved;
          return;
        }
        print('[HotkeyService] Discarding modifier-only hotkey: $saved');
      } catch (e) {
        print('[HotkeyService] Error loading hotkey: $e');
      }
    }
    
    // Default: Alt + Z
    _currentHotkey = HotKey(
      key: PhysicalKeyboardKey.keyZ,
      modifiers: [HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
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

  Future<void> _saveHotkey(HotKey hotkey) async {
    try {
      await _prefs.setString(_hotkeyKey, jsonEncode(hotkey.toJson()));
    } catch (e) {
      print('[HotkeyService] Error saving hotkey: $e');
    }
  }

  void setCallback(HotkeyCallback callback) {
    _onActivated = callback;
  }

  Future<void> updateHotkey(HotKey newKey) async {
    print('[HotkeyService] Updating hotkey from $_currentHotkey to $newKey');
    // More reliable to unregister all for this app
    await hotKeyManager.unregisterAll();
    _currentHotkey = newKey;
    await _saveHotkey(newKey);
    
    // Only register if we're not currently paused
    if (!_isPaused) {
      await _registerCurrent();
    }
  }

  Future<void> _registerCurrent() async {
    print('[HotkeyService] Registering: $_currentHotkey');
    await hotKeyManager.register(
      _currentHotkey,
      keyDownHandler: (_) {
        if (_isPaused) return; // Dart-level guard against in-flight callbacks
        print('[HotkeyService] Global Hotkey Activated!');
        _onActivated?.call();
      },
    );
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

  /// notes: Esc 取消錄音是全域熱鍵，不是 Flutter widget 的 key handler ——
  /// 錄音當下焦點幾乎都在別的應用程式（使用者正在對著它講話），
  /// 只有 HardwareKeyboard 監聽的 widget 版本收不到那個 Esc。
  static final _cancelHotkey =
      HotKey(key: PhysicalKeyboardKey.escape, scope: HotKeyScope.system);
  bool _cancelHotkeyRegistered = false;

  /// 呼叫端保證只在「進入錄音」到「離開錄音」這段期間各呼叫一次，
  /// 這裡再擋一次是避免重複註冊讓 win32 RegisterHotKey 出錯或留下殘影。
  Future<void> registerCancelHotkey(HotkeyCallback callback) async {
    if (_cancelHotkeyRegistered) return;
    _cancelHotkeyRegistered = true;
    await hotKeyManager.register(
      _cancelHotkey,
      keyDownHandler: (_) => callback(),
    );
  }

  Future<void> unregisterCancelHotkey() async {
    if (!_cancelHotkeyRegistered) return;
    _cancelHotkeyRegistered = false;
    await hotKeyManager.unregister(_cancelHotkey);
  }

  Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
  }
}
