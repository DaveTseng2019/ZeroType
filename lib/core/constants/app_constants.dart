class AppConstants {
  AppConstants._();

  static const String appName = 'ZeroType';
  static const String dictionaryFileName = 'dictionary.txt';
  static const String speechPromptKey = 'speech_recognition_prompt';
  static const String refinementPromptKey = 'text_refinement_prompt';
  static const String selectedSpeechProviderKey = 'selected_speech_provider';
  static const String selectedSpeechModelKey = 'selected_speech_model';
  static const String selectedRefinementProviderKey =
      'selected_refinement_provider';
  static const String selectedRefinementModelKey = 'selected_refinement_model';
  static const String isRefinementEnabledKey = 'is_refinement_enabled';
  static const String hotkeyKey = 'global_hotkey';
  static const String launchAtStartupKey = 'launch_at_startup';
  static const String startupMinimizedKey = 'startup_minimized';
  static const String soundEnabledKey = 'sound_enabled';
  static const String startSoundKey = 'start_sound';
  static const String stopSoundKey = 'stop_sound';
  static const String recordingStoppedSoundKey = 'recording_stopped_sound';
  static const String pasteFailedSoundKey = 'paste_failed_sound';

  /// 提示音期間主音量的下限（百分比，0 = 不干預）
  static const String minMasterVolumeKey = 'min_master_volume';
  static const String historyRetentionDaysKey = 'history_retention_days';
  static const String maxRecordingMinutesKey = 'max_recording_minutes';
  static const String inputDeviceIdKey = 'input_device_id';
  static const String noiseGateStrengthKey = 'noise_gate_strength';
  static const String recordWarmupMsKey = 'record_warmup_ms';

  /// 精簡模式貼上後要不要自動按 Enter 送出（預設要）
  static const String quickAutoEnterKey = 'quick_auto_enter';

  /// 偵錯模式：紀錄一併寫到 [debugLogFileName]，並多記貼上目標之類的細節
  static const String debugLogKey = 'debug_log';
  static const String debugLogFileName = 'debug.log';
  static const String fontSizesKey = 'font_sizes_json';

  static const String githubRepoUrl = 'https://github.com/DaveTseng2019/ZeroType';
  static const String githubLatestReleaseApiUrl =
      'https://api.github.com/repos/DaveTseng2019/ZeroType/releases/latest';
}

class SecureStorageKeys {
  SecureStorageKeys._();

  static const String groqApiKey = 'groq_api_key';
  static const String geminiApiKey = 'gemini_api_key';
}
