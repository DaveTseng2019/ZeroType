import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/features/prompt/repositories/prompt_repository.dart';

final promptRepositoryProvider =
    Provider<PromptRepository>((ref) => PromptRepository(prefs: appPrefs));

final speechPromptControllerProvider =
    AsyncNotifierProvider<SpeechPromptController, String>(
        SpeechPromptController.new);

class SpeechPromptController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final repo = ref.watch(promptRepositoryProvider);
    return repo.getSpeechPrompt();
  }

  Future<String> save(String prompt) async {
    final repo = ref.read(promptRepositoryProvider);
    final newVal = await repo.saveSpeechPrompt(prompt);
    ref.invalidateSelf();
    return newVal;
  }

  Future<String> resetToDefault() async {
    final repo = ref.read(promptRepositoryProvider);
    final newVal = await repo.resetSpeechPrompt();
    ref.invalidateSelf();
    return newVal;
  }
}

