const Map<String, ({double inputPerM, double outputPerM})> kModelPricing = {
  'gpt-4o-transcribe': (inputPerM: 2.5, outputPerM: 10.0),
  'gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5),
  'gemini-3-flash-preview': (inputPerM: 1.0, outputPerM: 2.5),
  // OpenRouter：inputPerM 採音訊 token 價格（pricing.audio）
  'google/gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5),
  'google/gemini-3-flash-preview': (inputPerM: 1.0, outputPerM: 3.0),
  'openai/gpt-4o-audio-preview': (inputPerM: 40.0, outputPerM: 10.0),
  'google/gemini-3.5-flash': (inputPerM: 3.0, outputPerM: 9.0),
  'google/gemini-3.1-flash-lite': (inputPerM: 0.5, outputPerM: 1.5),
  'google/gemini-3.1-pro-preview': (inputPerM: 2.0, outputPerM: 12.0),
  'google/gemini-2.5-flash-lite': (inputPerM: 0.3, outputPerM: 0.4),
  'google/gemini-2.5-pro': (inputPerM: 1.25, outputPerM: 10.0),
  'openai/gpt-audio': (inputPerM: 32.0, outputPerM: 10.0),
  'openai/gpt-audio-mini': (inputPerM: 0.6, outputPerM: 2.4),
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free': (inputPerM: 0, outputPerM: 0),
  'xiaomi/mimo-v2.5': (inputPerM: 0.14, outputPerM: 0.28),
};

const Map<String, String> kProviderNames = {
  'openai': 'OpenAI',
  'gemini': 'Gemini',
  'openrouter': 'OpenRouter',
};

const Map<String, String> kModelNames = {
  'gpt-4o-transcribe': 'GPT-4o Transcribe',
  'gemini-2.5-flash': 'Gemini 2.5 Flash',
  'gemini-3-flash-preview': 'Gemini 3 Flash Preview',
  'google/gemini-2.5-flash': 'Gemini 2.5 Flash',
  'google/gemini-3-flash-preview': 'Gemini 3 Flash Preview',
  'openai/gpt-4o-audio-preview': 'GPT-4o Audio Preview',
  'google/gemini-3.5-flash': 'Gemini 3.5 Flash',
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
