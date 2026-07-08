const Map<String, ({double inputPerM, double outputPerM})> kModelPricing = {
  'gpt-4o-transcribe': (inputPerM: 2.5, outputPerM: 10.0),
  'gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5),
  'gemini-3-flash-preview': (inputPerM: 1.0, outputPerM: 2.5),
  'google/gemini-2.5-flash': (inputPerM: 1.0, outputPerM: 2.5),
  'google/gemini-3-flash-preview': (inputPerM: 1.0, outputPerM: 2.5),
  'openai/gpt-4o-audio-preview': (inputPerM: 40.0, outputPerM: 10.0),
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
