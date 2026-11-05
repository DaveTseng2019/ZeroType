import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';

/// 一句辨識的效能數字。
class PerfEntry {
  const PerfEntry({
    required this.at,
    required this.provider,
    required this.model,
    required this.processingMs,
    this.audioMs,
    this.inputTokens,
    this.outputTokens,
    this.chars,
  });

  final DateTime at;
  final String provider;
  final String model;

  /// 放開錄音鍵之後等辨識結果的時間（含網路往返；兩段式服務商含校正）
  final int processingMs;

  /// 錄音長度（按下到放開）
  final int? audioMs;
  final int? inputTokens;
  final int? outputTokens;
  final int? chars;

  /// 每個輸出 token 花幾毫秒。本機端點是單段、沒有網路延遲，這個數字直接反映模型
  /// 跑得快不快：正常約 34～48；被 Windows 節能節流時 200 以上。雲端服務商含網路與排隊，只能參考。
  int? get msPerToken => outputTokens != null && outputTokens! > 0
      ? (processingMs / outputTokens!).round()
      : null;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'provider': provider,
        'model': model,
        'processingMs': processingMs,
        'audioMs': audioMs,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'chars': chars,
      };

  factory PerfEntry.fromJson(Map<String, dynamic> j) => PerfEntry(
        at: DateTime.parse(j['at'] as String),
        provider: j['provider'] as String? ?? '',
        model: j['model'] as String? ?? '',
        processingMs: j['processingMs'] as int,
        audioMs: j['audioMs'] as int?,
        inputTokens: j['inputTokens'] as int?,
        outputTokens: j['outputTokens'] as int?,
        chars: j['chars'] as int?,
      );
}

class PerfState {
  const PerfState({required this.enabled, required this.entries});

  final bool enabled;

  /// 新到舊
  final List<PerfEntry> entries;

  PerfState copyWith({bool? enabled, List<PerfEntry>? entries}) =>
      PerfState(enabled: enabled ?? this.enabled, entries: entries ?? this.entries);
}

final perfControllerProvider =
    NotifierProvider<PerfController, PerfState>(PerfController.new);

/// 效能紀錄。開關關著時什麼都不記；開著時每句一行 JSON 附加到 perf.jsonl。
///
/// notes: 只附加不輪替，畫面只讀最後 [_maxEntries] 筆。開關是追問題時才開的，
///   真的長到礙事再加大小上限。寫檔失敗一律吞掉，記錄不該把主流程弄倒。
class PerfController extends Notifier<PerfState> {
  static const _maxEntries = 500;

  @override
  PerfState build() {
    _restoreFromFile();
    return PerfState(
      enabled: appPrefs.getBool(AppConstants.perfLogKey) ?? false,
      entries: const [],
    );
  }

  Future<void> setEnabled(bool value) async {
    await appPrefs.setBool(AppConstants.perfLogKey, value);
    state = state.copyWith(enabled: value);
  }

  /// 開關關著時直接略過，呼叫端不必先檢查。
  void add(PerfEntry entry) {
    if (!state.enabled) return;
    final next = [entry, ...state.entries];
    state = state.copyWith(
        entries: next.length > _maxEntries ? next.sublist(0, _maxEntries) : next);
    final line = '${jsonEncode(entry.toJson())}\n';
    _tail = _tail.then((_) async {
      final file = await _perfFile();
      await file.writeAsString(line, mode: FileMode.append);
    }).catchError((_) {});
  }

  /// 清空畫面與檔案
  void clear() {
    state = state.copyWith(entries: const []);
    _tail = _tail.then((_) async {
      final file = await _perfFile();
      if (file.existsSync()) await file.delete();
    }).catchError((_) {});
  }

  Future<void> _restoreFromFile() async {
    try {
      final file = await _perfFile();
      if (!file.existsSync()) return;
      final restored = <PerfEntry>[];
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          restored.add(PerfEntry.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {
          // 壞掉的一行跳過，不影響其他筆
        }
      }
      if (restored.isEmpty) return;
      final merged = [...state.entries, ...restored.reversed];
      state = state.copyWith(
          entries: merged.length > _maxEntries
              ? merged.sublist(0, _maxEntries)
              : merged);
    } catch (_) {
      // 讀不回來就算了
    }
  }

  static Future<File>? _file;
  static Future<File> _perfFile() => _file ??= getApplicationSupportDirectory()
      .then((d) => File('${d.path}/${AppConstants.perfLogFileName}'));

  // 寫檔串成一條鏈，連續寫入時內容不會交錯
  static Future<void> _tail = Future.value();
}
