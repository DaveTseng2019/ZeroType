/// 每百萬 token 美元價。[audioInputPerM] 不是 null 時，音訊輸入另外計價，
/// [inputPerM] 只算文字輸入。
typedef ModelPrice = ({
  double inputPerM,
  double outputPerM,
  double? audioInputPerM,
});

/// 價目表依服務商分開：同一個模型在不同服務商的價格與計價方式可能不同。
const Map<String, Map<String, ModelPrice>> kModelPricing = {
  // notes: gpt-transcribe（$0.0045/分鐘）與 whisper-1（$0.006/分鐘）是按時間計價，
  //        沒有 token 單價，刻意不列——calculateCost 回 null，UI 就不顯示費用。
  //        官方價目頁只列一種輸入價，不分音訊與文字（2026-10-25 查）。
  'openai': {
    'gpt-4o-transcribe': (inputPerM: 2.5, outputPerM: 10.0, audioInputPerM: null),
    'gpt-4o-mini-transcribe':
        (inputPerM: 1.25, outputPerM: 5.0, audioInputPerM: null),
  },
  // notes: Azure Global Standard 的牌價，來源是 prices.azure.com（2026-10-25 查，
  //        South India）。音訊輸入比文字輸入貴，要用回應的 audio_tokens 分開算。
  //        gpt-transcribe（每小時 $0.27）與 whisper 按時間計價，同樣不列。
  'azure': {
    'gpt-4o-transcribe': (inputPerM: 2.5, outputPerM: 10.0, audioInputPerM: 6.0),
    'gpt-4o-mini-transcribe':
        (inputPerM: 1.25, outputPerM: 5.0, audioInputPerM: 3.0),
  },
  'gemini': {
    'gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5, audioInputPerM: null),
    'gemini-3-flash-preview':
        (inputPerM: 1.0, outputPerM: 2.5, audioInputPerM: null),
  },
  // notes: OpenRouter 的模型一律不列在這裡——價格會變（3.6-flash 就無聲降價一半，
  //        害費用顯示高一倍）。那邊的實際費用由回應的 usage.cost 帶回，選單費率由
  //        /api/v1/models 即時抓、抓不到時用上一次快取（ModelConfigRepository）。
  //        OpenAI、Azure 與 Gemini 原生 API 都不回報金額，只能寫死；
  //        改價時要手動更新這幾行。
};

ModelPrice? modelPrice(String providerId, String modelId) =>
    kModelPricing[providerId]?[modelId];

const Map<String, String> kProviderNames = {
  'openai': 'OpenAI',
  'azure': 'Azure OpenAI',
  'gemini': 'Gemini',
  'openrouter': 'OpenRouter',
  'local': '本機',
};

const Map<String, String> kModelNames = {
  'gpt-transcribe': 'GPT Transcribe',
  'gpt-4o-transcribe': 'GPT-4o Transcribe',
  'gpt-4o-mini-transcribe': 'GPT-4o Mini Transcribe',
  'whisper-1': 'Whisper',
  // Azure 的模型名稱就叫 whisper，不帶 -1
  'whisper': 'Whisper',
  // notes: 本機推論沒有 token 計價，刻意不列進 kModelPricing——calculateCost 回 null，
  //        費用欄位就不顯示。
  'moss-transcribe-diarize': 'MOSS Transcribe Diarize',
  // notes: 本機模型各有一份啟動設定（LocalSttService），選單換模型就換那份設定並重啟端點。
  //        實際跑哪個引擎仍由那份設定裡的 --engine 決定，id 對照見 kLocalEngineModelIds。
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

/// 紀錄頁每句前面標的模型簡稱，只要認得出是哪個模型就好。沒列的退回 [kModelNames]。
const Map<String, String> kModelShortNames = {
  'moss-transcribe-diarize': 'MOSS',
  // 已移除的本機引擎。留著讓舊紀錄的標籤仍看得懂。
  'fireredasr2-aed': 'FireRed',
  'gpt-transcribe': 'GPT',
  'gpt-4o-transcribe': '4o',
  'gpt-4o-mini-transcribe': '4o-mini',
  'whisper-1': 'Whisper',
  'whisper': 'Whisper',
};

String modelShortName(String modelId) =>
    kModelShortNames[modelId] ?? kModelNames[modelId] ?? modelId;

double? calculateCost(
  String providerId,
  String modelId,
  int? inputTokens,
  int? outputTokens, {
  int? audioInputTokens,
}) {
  final pricing = modelPrice(providerId, modelId);
  if (pricing == null || inputTokens == null || outputTokens == null) return null;
  final audioPerM = pricing.audioInputPerM;
  // 音訊分開計價、且回應帶了音訊明細，才拆開算；否則全部照一般輸入價
  final audio = (audioPerM != null && audioInputTokens != null)
      ? audioInputTokens.clamp(0, inputTokens)
      : 0;
  final inputCost =
      (inputTokens - audio) * pricing.inputPerM + audio * (audioPerM ?? 0);
  return (inputCost + outputTokens * pricing.outputPerM) / 1_000_000;
}

String formatCostUsd(double cost) {
  if (cost >= 10) return '\$${cost.toStringAsFixed(2)}';
  return '\$${cost.toStringAsFixed(4)}';
}
