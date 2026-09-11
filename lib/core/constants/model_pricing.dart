const Map<String, ({double inputPerM, double outputPerM})> kModelPricing = {
  // notes: gpt-transcribe（$0.0045/分鐘）與 whisper-1（$0.006/分鐘）是按時間計價，
  //        沒有 token 單價，刻意不列——calculateCost 回 null，UI 就不顯示費用
  'gpt-4o-transcribe': (inputPerM: 2.5, outputPerM: 10.0),
  'gpt-4o-mini-transcribe': (inputPerM: 1.25, outputPerM: 5.0),
  'gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5),
  'gemini-3-flash-preview': (inputPerM: 1.0, outputPerM: 2.5),
  // notes: OpenRouter 的模型一律不列在這裡——價格會變（3.6-flash 就無聲降價一半，
  //        害費用顯示高一倍）。那邊的實際費用由回應的 usage.cost 帶回，選單費率由
  //        /api/v1/models 即時抓、抓不到時用上一次快取（ModelConfigRepository）。
  //        OpenAI 與 Gemini 原生 API 都不回報金額，也沒有價格查詢端點，只能寫死；
  //        改價時要手動更新這幾行。
};

const Map<String, String> kProviderNames = {
  'openai': 'OpenAI',
  'gemini': 'Gemini',
  'openrouter': 'OpenRouter',
  'local': '本機',
};

const Map<String, String> kModelNames = {
  'gpt-transcribe': 'GPT Transcribe',
  'gpt-4o-transcribe': 'GPT-4o Transcribe',
  'gpt-4o-mini-transcribe': 'GPT-4o Mini Transcribe',
  'whisper-1': 'Whisper',
  // notes: 本機推論沒有 token 計價，刻意不列進 kModelPricing——calculateCost 回 null，
  //        費用欄位就不顯示。
  'moss-transcribe-diarize': 'MOSS Transcribe Diarize',
  'gemini-2.5-flash': 'Gemini 2.5 Flash',
  'gemini-3-flash-preview': 'Gemini 3 Flash Preview',
  'google/gemini-2.5-flash': 'Gemini 2.5 Flash',
  'google/gemini-3-flash-preview': 'Gemini 3 Flash Preview',
  'google/gemini-3.7-flash': 'Gemini 3.7 Flash',
  'google/gemini-3.6-flash': 'Gemini 3.6 Flash',
  'google/gemini-3.5-flash': 'Gemini 3.5 Flash',
  'google/gemini-3.5-flash-lite': 'Gemini 3.5 Flash Lite',
  'google/gemini-3.1-flash-lite': 'Gemini 3.1 Flash Lite',
  'google/gemini-3.1-pro-preview': 'Gemini 3.1 Pro Preview',
  'google/gemini-2.5-flash-lite': 'Gemini 2.5 Flash Lite',
  'google/gemini-2.5-pro': 'Gemini 2.5 Pro',
  'openai/gpt-audio': 'GPT Audio',
  'openai/gpt-audio-mini': 'GPT Audio Mini',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free': 'Nemotron 3 Nano Omni',
  'xiaomi/mimo-v2.5': '小米 MiMo-V2.5',
};

double? calculateCost(String modelId, int? inputTokens, int? outputTokens) {
  final pricing = kModelPricing[modelId];
  if (pricing == null || inputTokens == null || outputTokens == null) return null;
  return (inputTokens * pricing.inputPerM + outputTokens * pricing.outputPerM) /
      1_000_000;
}

String formatCostUsd(double cost) {
  if (cost >= 10) return '\$${cost.toStringAsFixed(2)}';
  return '\$${cost.toStringAsFixed(4)}';
}
