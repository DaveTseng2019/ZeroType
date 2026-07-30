import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:record/record.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/services/sound_service.dart';

part 'settings_state.freezed.dart';

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(false) bool launchAtStartup,
    @Default(false) bool startupMinimized,
    required HotKey hotkey,
    @Default(false) bool isAccessibilityAuthorized,
    @Default(false) bool isMicrophoneAuthorized,
    @Default(false) bool isRecordingHotkey,
    @Default(true) bool soundEnabled,
    @Default(kDefaultStartSound) String startSound,
    @Default(kDefaultStopSound) String stopSound,
    @Default(7) int historyRetentionDays,
    @Default(1) int maxRecordingMinutes,
    /// 空字串 = 系統預設輸入裝置
    @Default('') String inputDeviceId,
    @Default(<InputDevice>[]) List<InputDevice> inputDevices,
    @Default(false) bool noiseGateEnabled,
    /// 噪音門檻強度，見 recording_service.dart 的 applyNoiseGate marginFactor
    @Default(kDefaultNoiseGateStrength) double noiseGateStrength,
    /// 系統預設錄音裝置的名稱（藍牙耳機常只被設成通訊裝置，所以兩個角色分開顯示）
    @Default('') String defaultDeviceLabel,
    @Default('') String defaultCommsDeviceLabel,
    /// 開始錄音後丟棄的毫秒數，給藍牙 HFP 協商用；0 = 不延遲
    @Default(0) int recordWarmupMs,
  }) = _SettingsState;
}
