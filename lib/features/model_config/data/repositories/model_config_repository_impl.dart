import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/features/model_config/domain/entities/ai_provider.dart';
import 'package:zero_type/features/model_config/domain/repositories/model_config_repository.dart';

class ModelConfigRepositoryImpl implements ModelConfigRepository {
  ModelConfigRepositoryImpl({
    required SharedPreferences prefs,
  }) : _prefs = prefs;

  final SharedPreferences _prefs;

  @override
  Future<ProvidersConfig> loadProvidersConfig() async {
    final jsonString =
        await rootBundle.loadString('assets/config/providers.json');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    AiProvider parseProvider(Map<String, dynamic> p) => AiProvider(
          id: p['id'] as String,
          name: p['name'] as String,
          models: (p['models'] as List)
              .map(
                (m) => AiModel(
                  id: m['id'] as String,
                  name: m['name'] as String,
                ),
              )
              .toList(),
        );

    final providers = (json['speechRecognition'] as List)
        .map((p) => parseProvider(p as Map<String, dynamic>))
        .toList();

    // OpenRouter 清單改為線上更新，失敗時保留內建清單
    try {
      final openRouterModels = await _fetchOpenRouterAudioModels();
      if (openRouterModels.isNotEmpty) {
        final i = providers.indexWhere((p) => p.id == 'openrouter');
        if (i != -1) {
          providers[i] = AiProvider(
            id: providers[i].id,
            name: providers[i].name,
            models: openRouterModels,
          );
        }
      }
    } catch (_) {
      // 離線或 API 失敗，使用內建清單
    }

    return ProvidersConfig(speechRecognition: providers);
  }

  /// 從 OpenRouter 公開 API 抓支援音訊輸入的模型（含即時費率）
  static Future<List<AiModel>> _fetchOpenRouterAudioModels() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ));
    final res = await dio.get('https://openrouter.ai/api/v1/models');
    final data = res.data['data'] as List;

    final models = <AiModel>[];
    for (final m in data) {
      final id = m['id'] as String;
      final modalities =
          (m['architecture']?['input_modalities'] as List?) ?? const [];
      final promptPrice =
          double.tryParse(m['pricing']?['prompt']?.toString() ?? '') ?? -1;
      if (!modalities.contains('audio') ||
          promptPrice < 0 || // 排除 openrouter/auto 這類無固定價的路由
          id.startsWith('~') ||
          id.contains('customtools')) {
        continue;
      }
      final audioPrice =
          double.tryParse(m['pricing']?['audio']?.toString() ?? '');
      final completionPrice =
          double.tryParse(m['pricing']?['completion']?.toString() ?? '');
      models.add(AiModel(
        id: id,
        name: (m['name'] as String? ?? id).replaceFirst(RegExp(r'^[^:]+: '), ''),
        // API 價格單位是每 token，轉成每百萬 token；音訊輸入以 audio 價為準
        inputPerM: (audioPrice ?? promptPrice) * 1_000_000,
        outputPerM:
            completionPrice == null ? null : completionPrice * 1_000_000,
      ));
    }
    // 去掉重複的 preview 版：正式版已存在、或帶日期的 preview 快照
    final ids = models.map((m) => m.id).toSet();
    models.removeWhere((m) =>
        m.id.contains('-preview-') ||
        (m.id.endsWith('-preview') &&
            ids.contains(m.id.substring(0, m.id.length - '-preview'.length))));
    // 推薦優先，其餘依輸入價由低到高
    models.sort((a, b) {
      final ra = kRecommendedModels.contains(a.id) ? 0 : 1;
      final rb = kRecommendedModels.contains(b.id) ? 0 : 1;
      if (ra != rb) return ra - rb;
      return (a.inputPerM ?? 0).compareTo(b.inputPerM ?? 0);
    });
    return models;
  }

  @override
  Future<String?> getSelectedSpeechProviderId() async =>
      _prefs.getString(AppConstants.selectedSpeechProviderKey);

  @override
  Future<void> saveSelectedSpeechProviderId(String providerId) async =>
      _prefs.setString(AppConstants.selectedSpeechProviderKey, providerId);

  @override
  Future<String?> getSelectedSpeechModelId(String providerId) async =>
      _prefs.getString('${AppConstants.selectedSpeechModelKey}_$providerId');

  @override
  Future<void> saveSelectedSpeechModelId(String providerId, String modelId) async =>
      _prefs.setString('${AppConstants.selectedSpeechModelKey}_$providerId', modelId);

  @override
  Future<String?> getSpeechApiKey(String providerId) async =>
      _prefs.getString('api_key_speech_$providerId');

  @override
  Future<void> saveSpeechApiKey(String providerId, String apiKey) async =>
      _prefs.setString('api_key_speech_$providerId', apiKey);

  @override
  Future<String?> getCustomEndpoint(String providerId) async =>
      _prefs.getString('custom_endpoint_$providerId');

  @override
  Future<void> saveCustomEndpoint(String providerId, String endpoint) async =>
      _prefs.setString('custom_endpoint_$providerId', endpoint);
}
