import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

final phraseControllerProvider =
    AsyncNotifierProvider<PhraseController, List<String>>(PhraseController.new);

/// 常用詞彙：從歷史記錄複製過來的純文字，不帶音檔也不帶 token/費用資訊。
class PhraseController extends AsyncNotifier<List<String>> {
  static const _fileName = 'phrases.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  @override
  Future<List<String>> build() => _load();

  /// notes: 增刪一律以檔案為準重讀一次，不吃記憶體裡的 state —— 使用者可能剛用
  ///        外部編輯器改過檔案（見 [openFile]），拿舊清單整份寫回去會把他的編輯蓋掉。
  Future<List<String>> _load() async {
    final file = await _file();
    if (!file.existsSync()) return [];
    try {
      // 手改過的檔案可能有重複或整段空白；只丟掉整段空白的，其餘原樣保留
      // （含前後空白，例如結尾留一格好接下一個字）。順序保留使用者排的
      // （檔案順序即顯示順序），去重時 LinkedHashSet 留下第一次出現的位置。
      return (jsonDecode(await file.readAsString()) as List)
          .cast<String>()
          .where((s) => s.trim().isNotEmpty)
          .toSet()
          .toList();
    } catch (e) {
      print('[PhraseController] Failed to parse $_fileName: $e');
      return [];
    }
  }

  Future<void> _save(List<String> phrases) async {
    final file = await _file();
    // 縮排寫出，這個檔是給人手動編輯的
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(phrases));
    state = AsyncData(phrases);
  }

  /// 新的一筆加在最後，重複的不再加一筆。原樣保留前後空白；整段空白才拒絕。
  /// 回傳是否真的加入了。
  Future<bool> add(String text) async {
    if (text.trim().isEmpty) return false;
    final phrases = await _load();
    if (phrases.contains(text)) return false;
    await _save([...phrases, text]);
    return true;
  }

  Future<void> remove(String text) async {
    final phrases = await _load();
    phrases.remove(text);
    await _save(phrases);
  }

  /// 就地改寫第 [index] 筆，位置不動。以目前顯示的 state 為底（同 [reorder]）。
  /// 原樣保留前後空白。[newText]：整段空白、或與其他筆重複 → 不改，回傳 false；
  /// 沒變動回傳 true。
  Future<bool> edit(int index, String newText) async {
    final phrases = [...?state.value];
    if (index < 0 || index >= phrases.length) return false;
    if (newText.trim().isEmpty) return false;
    if (newText == phrases[index]) return true;
    // 與「別筆」重複才擋；跟自己比在上一行已放行
    if (phrases.contains(newText)) return false;
    phrases[index] = newText;
    await _save(phrases);
    return true;
  }

  /// 把第 [oldIndex] 筆搬到第 [newIndex] 筆的位置。[newIndex] 是移除該筆之後的
  /// 插入位置（ReorderableListView 的 onReorderItem 已經調整過，直接插入即可）。
  /// 以目前顯示的 state 為底，不重讀檔案 —— 使用者拖的是眼前這一份，重讀可能拿到
  /// 不同順序而錯位。
  Future<void> reorder(int oldIndex, int newIndex) async {
    final phrases = [...?state.value];
    if (oldIndex < 0 || oldIndex >= phrases.length) return;
    if (newIndex < 0 || newIndex >= phrases.length) return;
    final item = phrases.removeAt(oldIndex);
    phrases.insert(newIndex, item);
    await _save(phrases);
  }

  /// 用系統預設程式開啟 phrases.json 讓使用者手動編輯。
  Future<void> openFile() async {
    final file = await _file();
    // 還沒加過任何詞彙時檔案不存在，先寫一份空清單，不然開檔會撲空
    if (!file.existsSync()) await file.writeAsString('[]');
    final opened = await launchUrl(Uri.file(file.path),
        mode: LaunchMode.externalApplication);
    // notes: .json 沒有關聯程式時開檔會失敗，退而開資料夾——紀錄頁踩過同一個坑
    if (!opened) {
      await launchUrl(Uri.file(file.parent.path),
          mode: LaunchMode.externalApplication);
    }
  }

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
