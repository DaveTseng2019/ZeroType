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
    required this.quickHotkey,
    this.isAccessibilityAuthorized = false,
    this.isMicrophoneAuthorized = false,
    this.isRecordingHotkey = false,
    this.isEditingQuickHotkey = false,
    this.quickAutoEnter = true,
    this.soundEnabled = true,
    this.startSound = kDefaultStartSound,
    this.stopSound = kDefaultStopSound,
    this.recordingStoppedSound = kDefaultRecordingStoppedSound,
    this.historyRetentionDays = 7,
    this.maxRecordingMinutes = 1,
    this.inputDeviceId = '',
    this.inputDevices = const <InputDevice>[],
    this.noiseGateStrength = 0,
    this.defaultDeviceLabel = '',
    this.defaultCommsDeviceLabel = '',
    this.recordWarmupMs = 0,
  });

  final bool launchAtStartup;
  final bool startupMinimized;
  final HotKey hotkey;

  /// 精簡模式熱鍵：講完自動停、貼上後自動送出
  final HotKey quickHotkey;
  final bool isAccessibilityAuthorized;
  final bool isMicrophoneAuthorized;
  final bool isRecordingHotkey;

  /// 錄製中的熱鍵是哪一組（只在 [isRecordingHotkey] 為 true 時有意義）
  final bool isEditingQuickHotkey;

  /// 精簡模式貼上後要不要自動按 Enter 送出
  final bool quickAutoEnter;
  final bool soundEnabled;
  final String startSound;
  final String stopSound;
  final String recordingStoppedSound;
  final int historyRetentionDays;
  final int maxRecordingMinutes;

  /// 空字串 = 系統預設輸入裝置
  final String inputDeviceId;

  /// 系統可用的錄音輸入裝置
  final List<InputDevice> inputDevices;

  /// 噪音門檻強度，0 = 不過濾（預設）。
  /// 見 recording_service.dart 的 applyNoiseGate marginFactor
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
    HotKey? quickHotkey,
    bool? isAccessibilityAuthorized,
    bool? isMicrophoneAuthorized,
    bool? isRecordingHotkey,
    bool? isEditingQuickHotkey,
    bool? quickAutoEnter,
    bool? soundEnabled,
    String? startSound,
    String? stopSound,
    String? recordingStoppedSound,
    int? historyRetentionDays,
    int? maxRecordingMinutes,
    String? inputDeviceId,
    List<InputDevice>? inputDevices,
    double? noiseGateStrength,
    String? defaultDeviceLabel,
    String? defaultCommsDeviceLabel,
    int? recordWarmupMs,
  }) {
    return SettingsState(
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      startupMinimized: startupMinimized ?? this.startupMinimized,
      hotkey: hotkey ?? this.hotkey,
      quickHotkey: quickHotkey ?? this.quickHotkey,
      isAccessibilityAuthorized:
          isAccessibilityAuthorized ?? this.isAccessibilityAuthorized,
      isMicrophoneAuthorized:
          isMicrophoneAuthorized ?? this.isMicrophoneAuthorized,
      isRecordingHotkey: isRecordingHotkey ?? this.isRecordingHotkey,
      isEditingQuickHotkey:
          isEditingQuickHotkey ?? this.isEditingQuickHotkey,
      quickAutoEnter: quickAutoEnter ?? this.quickAutoEnter,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      startSound: startSound ?? this.startSound,
      stopSound: stopSound ?? this.stopSound,
      recordingStoppedSound: recordingStoppedSound ?? this.recordingStoppedSound,
      historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
      maxRecordingMinutes: maxRecordingMinutes ?? this.maxRecordingMinutes,
      inputDeviceId: inputDeviceId ?? this.inputDeviceId,
      inputDevices: inputDevices ?? this.inputDevices,
      noiseGateStrength: noiseGateStrength ?? this.noiseGateStrength,
      defaultDeviceLabel: defaultDeviceLabel ?? this.defaultDeviceLabel,
      defaultCommsDeviceLabel:
          defaultCommsDeviceLabel ?? this.defaultCommsDeviceLabel,
      recordWarmupMs: recordWarmupMs ?? this.recordWarmupMs,
    );
  }
}
