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
      // 手改過的檔案可能未排序、有重複，讀進來就一併整理
      return (jsonDecode(await file.readAsString()) as List)
          .cast<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
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

  /// 清單依字面排序，重複的不再加一筆。回傳是否真的加入了。
  Future<bool> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final phrases = await _load();
    if (phrases.contains(trimmed)) return false;
    await _save([...phrases, trimmed]..sort());
    return true;
  }

  Future<void> remove(String text) async {
    final phrases = await _load();
    phrases.remove(text);
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
