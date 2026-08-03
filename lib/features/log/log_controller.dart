import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  List<LogEntry> build() => const [];

  void info(String message) => _add(LogLevel.info, message);

  void error(String message) => _add(LogLevel.error, message);

  void clear() => state = const [];

  void _add(LogLevel level, String message) {
    final next = [LogEntry(DateTime.now(), level, message), ...state];
    state = next.length > _maxEntries ? next.sublist(0, _maxEntries) : next;
  }
}
