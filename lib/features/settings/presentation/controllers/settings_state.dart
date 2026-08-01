import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:record/record.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/services/sound_service.dart';

// notes: 原本用 freezed（全專案唯一使用點），手寫 copyWith 省掉整套 codegen；
// 沒實作 ==/hashCode，設定頁 rebuild 成本低，需要去重再加
class SettingsState {
  const SettingsState({
    this.launchAtStartup = false,
    this.startupMinimized = false,
    required this.hotkey,
    this.isAccessibilityAuthorized = false,
    this.isMicrophoneAuthorized = false,
    this.isRecordingHotkey = false,
    this.soundEnabled = true,
    this.startSound = kDefaultStartSound,
    this.stopSound = kDefaultStopSound,
    this.historyRetentionDays = 7,
    this.maxRecordingMinutes = 1,
    this.inputDeviceId = '',
    this.inputDevices = const <InputDevice>[],
    this.noiseGateEnabled = false,
    this.noiseGateStrength = kDefaultNoiseGateStrength,
    this.defaultDeviceLabel = '',
    this.defaultCommsDeviceLabel = '',
    this.recordWarmupMs = 0,
  });

  final bool launchAtStartup;
  final bool startupMinimized;
  final HotKey hotkey;
  final bool isAccessibilityAuthorized;
  final bool isMicrophoneAuthorized;
  final bool isRecordingHotkey;
  final bool soundEnabled;
  final String startSound;
  final String stopSound;
  final int historyRetentionDays;
  final int maxRecordingMinutes;

  /// 空字串 = 系統預設輸入裝置
  final String inputDeviceId;
  final List<InputDevice> inputDevices;
  final bool noiseGateEnabled;

  /// 噪音門檻強度，見 recording_service.dart 的 applyNoiseGate marginFactor
  final double noiseGateStrength;

  /// 系統預設錄音裝置的名稱（藍牙耳機常只被設成通訊裝置，所以兩個角色分開顯示）
  final String defaultDeviceLabel;
  final String defaultCommsDeviceLabel;

  /// 開始錄音後丟棄的毫秒數，給藍牙 HFP 協商用；0 = 不延遲
  final int recordWarmupMs;

  SettingsState copyWith({
    bool? launchAtStartup,
    bool? startupMinimized,
    HotKey? hotkey,
    bool? isAccessibilityAuthorized,
    bool? isMicrophoneAuthorized,
    bool? isRecordingHotkey,
    bool? soundEnabled,
    String? startSound,
    String? stopSound,
    int? historyRetentionDays,
    int? maxRecordingMinutes,
    String? inputDeviceId,
    List<InputDevice>? inputDevices,
    bool? noiseGateEnabled,
    double? noiseGateStrength,
    String? defaultDeviceLabel,
    String? defaultCommsDeviceLabel,
    int? recordWarmupMs,
  }) {
    return SettingsState(
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      startupMinimized: startupMinimized ?? this.startupMinimized,
      hotkey: hotkey ?? this.hotkey,
      isAccessibilityAuthorized:
          isAccessibilityAuthorized ?? this.isAccessibilityAuthorized,
      isMicrophoneAuthorized:
          isMicrophoneAuthorized ?? this.isMicrophoneAuthorized,
      isRecordingHotkey: isRecordingHotkey ?? this.isRecordingHotkey,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      startSound: startSound ?? this.startSound,
      stopSound: stopSound ?? this.stopSound,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      maxRecordingMinutes: maxRecordingMinutes ?? this.maxRecordingMinutes,
      inputDeviceId: inputDeviceId ?? this.inputDeviceId,
      inputDevices: inputDevices ?? this.inputDevices,
      noiseGateEnabled: noiseGateEnabled ?? this.noiseGateEnabled,
      noiseGateStrength: noiseGateStrength ?? this.noiseGateStrength,
      defaultDeviceLabel: defaultDeviceLabel ?? this.defaultDeviceLabel,
      defaultCommsDeviceLabel:
          defaultCommsDeviceLabel ?? this.defaultCommsDeviceLabel,
      recordWarmupMs: recordWarmupMs ?? this.recordWarmupMs,
    );
  }
}
