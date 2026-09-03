import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 每次呼叫辨識服務的耗時，逐行附加到 latency.jsonl。
///
/// 刻意不併進 history.json：那份有保留天數會被 purgeExpiredRecords 清掉，
/// 也會被「清除全部」一起刪，但拿來比較服務商就是要長期累積的資料。
class LatencyLog {
  static const _fileName = 'latency.jsonl';

  Future<File> file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$_fileName');

  /// [stage] audio = 音訊辨識那一段，text = 字典校正那一段。
  /// 失敗也要記——「延遲很久」最後常常是逾時，只記成功的會漏掉最想看的那幾筆。
  Future<void> record({
    required String stage,
    required String provider,
    required String model,
    required int elapsedMs,
    int? audioBytes,
    String? error,
  }) async {
    final line = jsonEncode({
      'at': DateTime.now().toIso8601String(),
      'stage': stage,
      'provider': provider,
      'model': model,
      'ms': elapsedMs,
      if (audioBytes != null) 'audioBytes': audioBytes,
      if (error != null)
        'error': error.length > 200 ? error.substring(0, 200) : error,
    });
    try {
      // notes: 每次都 open/append/close。單人桌面 app 一次只錄一段，呼叫端又是
      //        await 序列化的，不會交錯；要改成背景批次寫再考慮加鎖。
      await (await file()).writeAsString('$line\n', mode: FileMode.append);
    } catch (e) {
      // 記錄失敗絕不能影響辨識本身
      print('[LatencyLog] write failed: $e');
    }
  }
}
