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
  static const String historyRetentionDaysKey = 'history_retention_days';
  static const String maxRecordingMinutesKey = 'max_recording_minutes';
}

class SecureStorageKeys {
  SecureStorageKeys._();

  static const String groqApiKey = 'groq_api_key';
  static const String geminiApiKey = 'gemini_api_key';
}
