import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'settings_state.dart';

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
        SettingsController.new);

class SettingsController extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    print('[SettingsController] Building state...');

    try {
      print('[SettingsController] Checking if launch at startup is enabled...');
      final isLaunchEnabled = appPrefs.getBool(AppConstants.launchAtStartupKey) ?? false;
      final startupMinimized = appPrefs.getBool(AppConstants.startupMinimizedKey) ?? false;
      
      print('[SettingsController] Fetching current hotkey...');
      final hotkey = hotkeyService.currentHotkey;

      print('[SettingsController] Fetching permissions...');
      final isAccessibilityAuthorized = await _checkAccessibility();
      final isMicrophoneAuthorized = await AudioRecorder().hasPermission();

      final prefs = appPrefs;
      final soundEnabled = prefs.getBool(AppConstants.soundEnabledKey) ?? true;
      final startSound = prefs.getString(AppConstants.startSoundKey) ?? kDefaultStartSound;
      final stopSound = prefs.getString(AppConstants.stopSoundKey) ?? kDefaultStopSound;
      final recordingStoppedSound =
          prefs.getString(AppConstants.recordingStoppedSoundKey) ??
              kDefaultRecordingStoppedSound;
      final historyRetentionDays = prefs.getInt(AppConstants.historyRetentionDaysKey) ?? 7;
      final maxRecordingMinutes = prefs.getInt(AppConstants.maxRecordingMinutesKey) ?? 1;
      final inputDeviceId = prefs.getString(AppConstants.inputDeviceIdKey) ?? '';
      final devices = await _loadDevices();
      // 0 = 不過濾，也是預設值
      final noiseGateStrength =
          prefs.getDouble(AppConstants.noiseGateStrengthKey) ?? 0;

      print('[SettingsController] Build complete.');
      return SettingsState(
        launchAtStartup: isLaunchEnabled,
        startupMinimized: startupMinimized,
        hotkey: hotkey,
        isAccessibilityAuthorized: isAccessibilityAuthorized,
        isMicrophoneAuthorized: isMicrophoneAuthorized,
        soundEnabled: soundEnabled,
        startSound: startSound,
        stopSound: stopSound,
        recordingStoppedSound: recordingStoppedSound,
        historyRetentionDays: historyRetentionDays,
        maxRecordingMinutes: maxRecordingMinutes,
        inputDeviceId: inputDeviceId,
        inputDevices: devices.list,
        defaultDeviceLabel: devices.defaultLabel,
        defaultCommsDeviceLabel: devices.commsLabel,
        noiseGateStrength: noiseGateStrength,
        recordWarmupMs: prefs.getInt(AppConstants.recordWarmupMsKey) ?? 0,
      );
    } catch (e, st) {
      print('[SettingsController] Error building settings state: $e\n$st');
      rethrow;
    }
  }

  Future<void> toggleLaunchAtStartup(bool value) async {
    print('[SettingsController] Toggling launchAtStartup to $value...');
    try {
      if (value) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } on MissingPluginException {
      print('[SettingsController] toggleLaunchAtStartup failed: plugin missing.');
      return;
    } catch (e) {
      print('[SettingsController] toggleLaunchAtStartup error: $e');
      return;
    }
    await appPrefs.setBool(AppConstants.launchAtStartupKey, value);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(launchAtStartup: value));
    }
  }

  Future<void> toggleStartupMinimized(bool value) async {
    await appPrefs.setBool(AppConstants.startupMinimizedKey, value);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(startupMinimized: value));
    }
  }

  Future<void> startRecordingHotkey() async {
    print('[SettingsController] Starting hotkey recording...');
    final currentState = state.value;
    if (currentState == null) return;

    // Disable global hotkey BEFORE showing overlay to prevent accidental triggers
    await hotkeyService.pause();

    state = AsyncData(currentState.copyWith(isRecordingHotkey: true));
  }

  void stopRecordingHotkey() {
    print('[SettingsController] Stopping hotkey recording...');
    final currentState = state.value;
    if (currentState == null) return;
    
    // Re-enable global hotkey
    hotkeyService.resume();
    
    state = AsyncData(currentState.copyWith(isRecordingHotkey: false));
  }

  Future<void> saveHotkey(List<PhysicalKeyboardKey> keys) async {
    print('[SettingsController] Saving hotkey with keys: $keys');
    
    final List<HotKeyModifier> modifiers = [];
    PhysicalKeyboardKey? mainKey;

    for (final key in keys) {
      if (key == PhysicalKeyboardKey.metaLeft || key == PhysicalKeyboardKey.metaRight) {
        if (!modifiers.contains(HotKeyModifier.meta)) modifiers.add(HotKeyModifier.meta);
      } else if (key == PhysicalKeyboardKey.controlLeft || key == PhysicalKeyboardKey.controlRight) {
        if (!modifiers.contains(HotKeyModifier.control)) modifiers.add(HotKeyModifier.control);
      } else if (key == PhysicalKeyboardKey.altLeft || key == PhysicalKeyboardKey.altRight) {
        if (!modifiers.contains(HotKeyModifier.alt)) modifiers.add(HotKeyModifier.alt);
      } else if (key == PhysicalKeyboardKey.shiftLeft || key == PhysicalKeyboardKey.shiftRight) {
        if (!modifiers.contains(HotKeyModifier.shift)) modifiers.add(HotKeyModifier.shift);
      } else {
        // Take the last non-modifier key as the main key
        mainKey = key;
      }
    }

    if (mainKey == null) {
      print('[SettingsController] No main key selected, ignoring save.');
      stopRecordingHotkey();
      return;
    }

    final newHotKey = HotKey(
      key: mainKey,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );

    await hotkeyService.updateHotkey(newHotKey);
    
    // Stop recording and trigger refresh
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(
        isRecordingHotkey: false,
        hotkey: newHotKey,
      ));
    }
    
    // Resume local hotkey (already handled in stopRecordingHotkey but stay safe)
    hotkeyService.resume();
  }

  Future<void> toggleSound(bool value) async {
    await appPrefs.setBool(AppConstants.soundEnabledKey, value);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(soundEnabled: value));
    }
  }

  Future<void> setStartSound(String path) async {
    await appPrefs.setString(AppConstants.startSoundKey, path);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(startSound: path));
    }
  }

  Future<void> setStopSound(String path) async {
    await appPrefs.setString(AppConstants.stopSoundKey, path);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(stopSound: path));
    }
  }

  Future<void> setRecordingStoppedSound(String path) async {
    await appPrefs.setString(AppConstants.recordingStoppedSoundKey, path);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(recordingStoppedSound: path));
    }
  }

  Future<void> setHistoryRetentionDays(int days) async {
    await appPrefs.setInt(AppConstants.historyRetentionDaysKey, days);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(historyRetentionDays: days));
    }
  }

  /// 空字串 = 系統預設輸入裝置
  Future<void> setInputDeviceId(String deviceId) async {
    await appPrefs
        .setString(AppConstants.inputDeviceIdKey, deviceId);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(inputDeviceId: deviceId));
      await setRecordWarmupMs(_defaultWarmupFor(currentState, deviceId));
    }
  }

  /// 換裝置時順便帶出合理的等待值：藍牙耳機要丟掉切換通話模式那段死區，
  /// 其他麥克風一開就有訊號，等待只會變成「等你開口」。
  ///
  /// notes: 靠名字裡有沒有「耳機」判斷。Windows 的 endpoint 沒有「這是不是藍牙」
  /// 的乾淨旗標，裝置名稱是現成又看得懂的線索；判錯了使用者自己拉滑桿就好。
  int _defaultWarmupFor(SettingsState s, String deviceId) {
    final label = deviceId.isEmpty
        // 空字串是「系統預設」，實際錄音吃的是預設通訊裝置
        ? (s.defaultCommsDeviceLabel.isEmpty
            ? s.defaultDeviceLabel
            : s.defaultCommsDeviceLabel)
        : s.inputDevices
            .where((d) => d.id == deviceId)
            .map((d) => d.label)
            .join();
    // 1 秒：實測 HFP 切換約 0.93 秒完成；時間到就算就緒，不看訊號內容
    return label.contains('耳機') ? 1000 : 0;
  }

  Future<void> setNoiseGateStrength(double strength) async {
    await appPrefs
        .setDouble(AppConstants.noiseGateStrengthKey, strength);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(noiseGateStrength: strength));
    }
  }

  Future<void> setRecordWarmupMs(int ms) async {
    await appPrefs
        .setInt(AppConstants.recordWarmupMsKey, ms);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(recordWarmupMs: ms));
    }
  }

  /// 裝置清單 + 系統預設裝置實際是哪一支（設定頁要顯示，不然「系統預設」看不出是誰）
  Future<({List<InputDevice> list, String defaultLabel, String commsLabel})>
      _loadDevices() async {
    List<InputDevice> list;
    try {
      list = await AudioRecorder().listInputDevices();
    } catch (e) {
      print('[SettingsController] listInputDevices error: $e');
      list = const [];
    }
    final ids = defaultInputDeviceIds();
    return (
      list: list,
      defaultLabel: resolveInputDevice(list, ids.console)?.label ?? '',
      commsLabel: resolveInputDevice(list, ids.communications)?.label ?? '',
    );
  }

  Future<void> setMaxRecordingMinutes(int minutes) async {
    await appPrefs.setInt(AppConstants.maxRecordingMinutesKey, minutes);
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(maxRecordingMinutes: minutes));
    }
  }

  /// Called by SettingsPage whenever it becomes visible.
  Future<void> refreshPermissions() async {
    // Run checks independently of current state loading status
    final isAccessibility = await _checkAccessibility();
    final isMicrophone = await AudioRecorder().hasPermission();
    // 藍牙裝置可能在 app 執行期間才連上，每次開設定頁重抓
    final devices = await _loadDevices();

    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(
        isAccessibilityAuthorized: isAccessibility,
        isMicrophoneAuthorized: isMicrophone,
        inputDevices: devices.list,
        defaultDeviceLabel: devices.defaultLabel,
        defaultCommsDeviceLabel: devices.commsLabel,
      ));
    } else {
      // State is still loading (initial build not done yet);
      // wait for it to complete, then update
      state.whenData((s) {
        state = AsyncData(s.copyWith(
          isAccessibilityAuthorized: isAccessibility,
          isMicrophoneAuthorized: isMicrophone,
        ));
      });
    }
  }

  Future<bool> _checkAccessibility() async {
    // Windows doesn't require Accessibility permission for SendInput
    if (Platform.isWindows) return true;
    const channel = MethodChannel('com.zerotype.app/permission');
    try {
      return await channel.invokeMethod<bool>('checkAccessibility') ?? false;
    } catch (e) {
      print('[SettingsController] checkAccessibility error: $e');
      return false;
    }
  }
}
