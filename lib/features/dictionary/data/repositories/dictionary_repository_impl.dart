import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/features/dictionary/domain/repositories/dictionary_repository.dart';

class DictionaryRepositoryImpl implements DictionaryRepository {
  Future<File> _getDictionaryFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${AppConstants.dictionaryFileName}');
  }

  @override
  Future<List<String>> loadWords() async {
    final file = await _getDictionaryFile();
    if (!file.existsSync()) return [];
    final content = await file.readAsString();
    return content
        .split('\n')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList()
      ..sort();
  }

  @override
  Future<void> addWord(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty) return;
    final words = await loadWords();
    if (words.contains(trimmed)) return;
    words
      ..add(trimmed)
      ..sort();
    final file = await _getDictionaryFile();
    await file.writeAsString(words.join('\n'));
  }

  @override
  Future<void> removeWord(String word) async {
    final words = await loadWords();
    words.remove(word);
    final file = await _getDictionaryFile();
    await file.writeAsString(words.join('\n'));
  }

  @override
  Future<String> buildDictionaryPrompt() async {
    final words = await loadWords();
    if (words.isEmpty) return '';
    return '以下是專有名詞字典，僅供修正拼寫：'
        '當音檔中出現發音相同或相近的詞時，採用字典的寫法；'
        '音檔中沒有出現的詞，嚴禁自行加入輸出。\n${words.join('、')}';
  }
}
