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
    
    // Default: Alt + Space
    _currentHotkey = HotKey(
      key: PhysicalKeyboardKey.space,
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

  Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
  }
}
