class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    this.inputPerM,
    this.outputPerM,
  });

  final String id;
  final String name;

  /// 每百萬 token 美元價（動態清單由 API 帶回；null 時 UI 改查 kModelPricing）
  final double? inputPerM;
  final double? outputPerM;
}

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.models,
  });

  final String id;
  final String name;
  final List<AiModel> models;
}

class ProvidersConfig {
  const ProvidersConfig({
    required this.speechRecognition,
  });

  final List<AiProvider> speechRecognition;
}
