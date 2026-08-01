import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:zero_type/core/constants/app_constants.dart';

class DictionaryRepository {
  Future<File> _getDictionaryFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${AppConstants.dictionaryFileName}');
  }

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

  Future<void> removeWord(String word) async {
    final words = await loadWords();
    words.remove(word);
    final file = await _getDictionaryFile();
    await file.writeAsString(words.join('\n'));
  }

  Future<String> buildDictionaryPrompt() async {
    final words = await loadWords();
    if (words.isEmpty) return '';
    // notes: 只剩 openai（whisper）路徑使用，whisper 的 prompt 是解碼偏置不是指令；
    // gemini/openrouter 改走 buildCorrectionPrompt() 的兩段式，避免辨識時憑空插入
    return 'dictionary_hints:\n'
        '  - 這是拼寫替換規則，不是要輸出的文字：'
        '僅當音檔中出現與下列詞彙發音相同或相近的詞時，'
        '才將該詞改寫成字典的寫法：${words.join('、')}\n'
        '  - 最終檢查：字典裡的詞若其發音沒有在音檔中出現，輸出中不得含有該詞。';
  }

  Future<String> buildCorrectionPrompt() async {
    final words = await loadWords();
    if (words.isEmpty) return '';
    // notes: 字典跟音訊放同一個 context 時，模型會把「發音相近」自我合理化而憑空插入
    // （「來源」→「來自耀群科技」，替換規則措辭 4/4、逐音節措辭 2/4 都失守）；
    // 改成轉錄後的純文字第二段校正，模型看不到音訊就沒有「我好像有聽到」的空間
    // （API 實測負向 6/6 零插入、陷阱句 7/7 原樣保留、正向 3/3 修正「藥群→耀群」）。
    // notes: 「字數相同」規則以中文一字一音節為前提，字典加入英文詞時需再驗證
    return 'task: 校正逐字稿中專有名詞的拼寫，直接輸出校正後的逐字稿，不解釋。\n'
        'rules:\n'
        '  - 字典（正確寫法）：${words.join('、')}\n'
        '  - 僅當逐字稿中某個詞與字典詞「發音相同、且字數相同」時，'
        '才把那個詞改寫成字典的寫法。替換前後的字數必須一樣，'
        '一個字都不能多、不能少。\n'
        '  - 字數不同、或發音對不上的詞，一律原樣保留。'
        '不得為了語意通順而替換。\n'
        '  - 例：字典有「臺積電」；逐字稿出現「台機電」（同音同字數）→ 改成「臺積電」；'
        '逐字稿出現「台電」或「積體電路」（字數不同）→ 原樣保留。\n'
        '  - 其他文字一律原樣保留，不增刪、不改寫、不潤飾。'
        '沒有任何詞需要校正時，原樣輸出整份逐字稿。\n'
        'transcript:\n';
  }
}
