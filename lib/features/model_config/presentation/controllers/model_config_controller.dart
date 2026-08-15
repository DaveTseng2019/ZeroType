import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/features/model_config/repositories/model_config_repository.dart';
import 'package:zero_type/features/model_config/entities/ai_provider.dart';

ModelConfigRepository _buildRepository() => ModelConfigRepository(
      prefs: appPrefs,
    );

final providersConfigProvider = FutureProvider<ProvidersConfig>(
    (ref) => _buildRepository().loadProvidersConfig());

typedef SpeechProviderConfig = ({
  String? providerId,
  String? modelId,
  String? apiKey,
  String? customEndpoint,
});

final speechProviderControllerProvider =
    AsyncNotifierProvider<SpeechProviderController, SpeechProviderConfig>(
        SpeechProviderController.new);

class SpeechProviderController extends AsyncNotifier<SpeechProviderConfig> {
  ModelConfigRepository get _repo => _buildRepository();

  @override
  Future<({String? providerId, String? modelId, String? apiKey, String? customEndpoint})>
      build() async {
    var providerId = await _repo.getSelectedSpeechProviderId();

    // Auto-select the first provider on first launch so saveApiKey/selectModel work correctly
    if (providerId == null) {
      final config = await _repo.loadProvidersConfig();
      if (config.speechRecognition.isNotEmpty) {
        providerId = config.speechRecognition.first.id;
        await _repo.saveSelectedSpeechProviderId(providerId);
      }
    }

    return (
      providerId: providerId,
      modelId: await _repo.getSelectedSpeechModelId(providerId ?? ''),
      apiKey: await _repo.getSpeechApiKey(providerId ?? ''),
      customEndpoint: await _repo.getCustomEndpoint(providerId ?? ''),
    );
  }

  Future<void> selectProvider(String providerId) async {
    await _repo.saveSelectedSpeechProviderId(providerId);
    ref.invalidateSelf();
  }

  Future<void> selectModel(String modelId) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveSelectedSpeechModelId(state.providerId!, modelId);
      ref.invalidateSelf();
    }
  }

  Future<void> saveApiKey(String apiKey) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveSpeechApiKey(state.providerId!, apiKey);
      ref.invalidateSelf();
    }
  }

  Future<void> clearApiKey() async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.removeSpeechApiKey(state.providerId!);
      ref.invalidateSelf();
    }
  }

  /// 測試目前 provider 的 API Key：成功回 null，失敗回原因
  Future<String?> testApiKey(String apiKey) async {
    final state = await future;
    if (state.providerId == null) return '尚未選擇 Provider';
    return speechService.testApiKey(
      provider: state.providerId!,
      apiKey: apiKey.trim(),
    );
  }

  Future<void> saveCustomEndpoint(String endpoint) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveCustomEndpoint(state.providerId!, endpoint);
      ref.invalidateSelf();
    }
  }
}

