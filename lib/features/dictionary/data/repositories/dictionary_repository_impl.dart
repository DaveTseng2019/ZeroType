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
    // notes: 「僅供修正拼寫＋嚴禁加入」的敘述式禁令實測壓不住插入；
    // 改成替換規則＋最終檢查兩段式（API 實測 8/8 零插入、2/2 正確改寫「藥群→耀群」）
    return 'dictionary_hints:\n'
        '  - 這是拼寫替換規則，不是要輸出的文字：'
        '僅當音檔中出現與下列詞彙發音相同或相近的詞時，'
        '才將該詞改寫成字典的寫法：${words.join('、')}\n'
        '  - 最終檢查：字典裡的詞若其發音沒有在音檔中出現，輸出中不得含有該詞。';
  }
}
