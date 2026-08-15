import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/features/model_config/entities/ai_provider.dart';

class ModelConfigRepository {
  ModelConfigRepository({
    required SharedPreferences prefs,
  }) : _prefs = prefs;

  final SharedPreferences _prefs;

  Future<ProvidersConfig> loadProvidersConfig() async {
    final jsonString =
        await rootBundle.loadString('assets/config/providers.json');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    AiProvider parseProvider(Map<String, dynamic> p) => AiProvider(
          id: p['id'] as String,
          name: p['name'] as String,
          url: p['url'] as String?,
          models: _markRecommended((p['models'] as List)
              .map(
                (m) => AiModel(
                  id: m['id'] as String,
                  name: m['name'] as String,
                ),
              )
              .toList()),
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
            url: providers[i].url,
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
    final marked = _markRecommended(models);
    // 推薦優先，其餘依輸入價由低到高；免費模型可用性差，一律排最後
    marked.sort((a, b) {
      final aFree = a.id.endsWith(':free');
      final bFree = b.id.endsWith(':free');
      if (aFree != bFree) return aFree ? 1 : -1;
      if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
      return (a.inputPerM ?? 0).compareTo(b.inputPerM ?? 0);
    });
    return marked;
  }

  /// 推薦依據：可信大廠的付費「標準級」模型中，音訊輸入價最低者
  /// （轉譯成本以輸入為大宗）。品質代理＝廠商＋級距關鍵字；
  /// 同價時取清單較前者（動態清單 API 順序為新到舊，即較新一代）。
  static List<AiModel> _markRecommended(List<AiModel> models) {
    AiModel? best;
    var bestPrice = double.infinity;
    for (final m in models) {
      final org = m.id.contains('/') ? m.id.split('/').first : '';
      final trusted = org.isEmpty ||
          const {'google', 'openai', 'mistralai'}.contains(org);
      // token 邊界比對，避免 gemini 誤中 mini
      final lite = RegExp(r'(^|[-/.])(lite|nano|micro|mini|small)([-:.]|$)')
          .hasMatch(m.id.toLowerCase());
      final price = m.inputPerM ?? kModelPricing[m.id]?.inputPerM;
      if (!trusted || lite || price == null || price <= 0) continue;
      if (price < bestPrice) {
        bestPrice = price;
        best = m;
      }
    }
    if (best == null) return models;
    return models
        .map((m) => m == best
            ? AiModel(
                id: m.id,
                name: m.name,
                inputPerM: m.inputPerM,
                outputPerM: m.outputPerM,
                recommended: true,
              )
            : m)
        .toList();
  }

  Future<String?> getSelectedSpeechProviderId() async =>
      _prefs.getString(AppConstants.selectedSpeechProviderKey);

  Future<void> saveSelectedSpeechProviderId(String providerId) async =>
      _prefs.setString(AppConstants.selectedSpeechProviderKey, providerId);

  Future<String?> getSelectedSpeechModelId(String providerId) async =>
      _prefs.getString('${AppConstants.selectedSpeechModelKey}_$providerId');

  Future<void> saveSelectedSpeechModelId(String providerId, String modelId) async =>
      _prefs.setString('${AppConstants.selectedSpeechModelKey}_$providerId', modelId);

  Future<String?> getSpeechApiKey(String providerId) async =>
      _prefs.getString('api_key_speech_$providerId');

  Future<void> saveSpeechApiKey(String providerId, String apiKey) async =>
      _prefs.setString('api_key_speech_$providerId', apiKey);

  Future<void> removeSpeechApiKey(String providerId) async =>
      _prefs.remove('api_key_speech_$providerId');

  Future<String?> getCustomEndpoint(String providerId) async =>
      _prefs.getString('custom_endpoint_$providerId');

  Future<void> saveCustomEndpoint(String providerId, String endpoint) async =>
      _prefs.setString('custom_endpoint_$providerId', endpoint);
}
