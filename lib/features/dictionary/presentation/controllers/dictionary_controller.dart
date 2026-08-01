import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/features/dictionary/repositories/dictionary_repository.dart';

final dictionaryRepositoryProvider =
    Provider<DictionaryRepository>((ref) => DictionaryRepository());

final dictionaryControllerProvider =
    AsyncNotifierProvider<DictionaryController, List<String>>(
        DictionaryController.new);

class DictionaryController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repo = ref.watch(dictionaryRepositoryProvider);
    return repo.loadWords();
  }

  Future<void> addWord(String word) async {
    final repo = ref.read(dictionaryRepositoryProvider);
    await repo.addWord(word);
    ref.invalidateSelf();
  }

  Future<void> removeWord(String word) async {
    final repo = ref.read(dictionaryRepositoryProvider);
    await repo.removeWord(word);
    ref.invalidateSelf();
  }
}
