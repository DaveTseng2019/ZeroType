import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';

enum LogLevel { info, error }

class LogEntry {
  const LogEntry(this.at, this.level, this.message);

  final DateTime at;
  final LogLevel level;
  final String message;
}

final logControllerProvider =
    NotifierProvider<LogController, List<LogEntry>>(LogController.new);

/// 執行過程的訊息。純記憶體，不落地 —— 需要留存的資訊已經在歷史紀錄裡。
///
/// notes: 存在的理由是取代「錯誤訊息顯示 2~3 秒」那種用延遲當 UI 的做法。
/// 那些延遲會把流程整個卡住（錯誤要等 3 秒才回到閒置），訊息也留不下來，
/// 看漏了就沒了。寫進這裡就不必等，訊息也還在。
class LogController extends Notifier<List<LogEntry>> {
  /// 上限，避免長時間執行後無限成長
  static const _maxEntries = 200;

  @override
  List<LogEntry> build() {
    _restoreFromFile();
    return const [];
  }

  /// 有紀錄檔就把內容讀回畫面。重開 app 之後記憶體是空的，但檔案還在 ——
  /// 不讀回來的話畫面看起來像沒紀錄，檔案裡卻明明有。
  ///
  /// notes: 訊息本身可能有換行（轉寫文字裡的換行），所以認不出時間戳開頭的行
  ///   一律當成上一筆的續行接回去，不要丟掉。
  Future<void> _restoreFromFile() async {
    try {
      final file = await logFile();
      if (!file.existsSync()) return;
      final restored = <LogEntry>[];
      for (final line in await file.readAsLines()) {
        final m = _linePattern.firstMatch(line);
        if (m == null) {
          if (restored.isNotEmpty) {
            final last = restored.removeLast();
            restored
                .add(LogEntry(last.at, last.level, '${last.message}\n$line'));
          }
          continue;
        }
        restored.add(LogEntry(
          DateTime.parse(m.group(1)!),
          m.group(2) == 'error' ? LogLevel.error : LogLevel.info,
          m.group(3)!,
        ));
      }
      if (restored.isEmpty) return;
      // 檔案是舊到新，畫面是新到舊；讀回來的一律排在這次開機新增的後面
      final merged = [...state, ...restored.reversed];
      state =
          merged.length > _maxEntries ? merged.sublist(0, _maxEntries) : merged;
    } catch (_) {
      // 讀不回來就算了，紀錄不該擋住程式
    }
  }

  static final _linePattern = RegExp(r'^(\S+) \[(info|error)\] (.*)$');

  void info(String message) => _add(LogLevel.info, message);

  void error(String message) => _add(LogLevel.error, message);

  /// 只有偵錯模式開著才記的訊息（貼上目標之類）。平常不顯示 —— 這些細節只在
  /// 追問題時有意義，一直印在畫面上只會把真正要看的訊息擠掉。
  void debug(String message) {
    if (_debugOn) _add(LogLevel.info, message);
  }

  /// 清空紀錄，連落地的檔案一起刪 —— 清歷史紀錄時會走這裡，
  /// 講過的話不該只清掉畫面上那份而留在磁碟上。
  void clear() {
    state = const [];
    _tail = _tail.then((_) async {
      final file = await logFile();
      if (file.existsSync()) await file.delete();
    }).catchError((_) {});
  }

  void _add(LogLevel level, String message) {
    final entry = LogEntry(DateTime.now(), level, message);
    final next = [entry, ...state];
    state = next.length > _maxEntries ? next.sublist(0, _maxEntries) : next;
    if (_debugOn) _appendToFile(entry);
  }

  static bool get _debugOn =>
      appPrefs.getBool(AppConstants.debugLogKey) ?? false;

  static Future<File>? _file;

  /// 偵錯紀錄檔。設定頁要拿它來開檔，所以是公開的。
  static Future<File> logFile() => _file ??= getApplicationSupportDirectory()
      .then((d) => File('${d.path}/${AppConstants.debugLogFileName}'));

  // 寫檔串成一條鏈：_add 是同步的、可能連續呼叫，各自 await 會讓內容交錯。
  // notes: 只附加不輪替，偵錯模式是臨時開的、開著也只有錄音時才寫；真的長到礙事
  //   再加大小上限。寫檔失敗一律吞掉 —— 記錄本身不該把主流程弄倒。
  static Future<void> _tail = Future.value();

  static void _appendToFile(LogEntry entry) {
    final line = '${entry.at.toIso8601String()} [${entry.level.name}] '
        '${entry.message}\n';
    _tail = _tail.then((_) async {
      final file = await logFile();
      await file.writeAsString(line, mode: FileMode.append);
    }).catchError((_) {});
  }
}
