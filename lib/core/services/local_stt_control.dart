import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_stt_service.dart';

/// 讓 AI 代理或本機腳本停止、啟動、重啟本機辨識端點，效果等於模型設定頁的按鈕。
///
/// 協定（資料夾是 `<應用程式資料夾>\control`）：
/// 1. 寫入 `local-stt.request`，內容是 `stop`、`start` 或 `restart`。
/// 2. ZeroType 刪掉請求檔，執行指令。
/// 3. 結果寫到 `local-stt.result`（JSON：id、command、result、at）。
///    請求內容可以帶第二個字當 id（例如 `restart 1794890000`），結果會原樣帶回，
///    呼叫端靠它分辨「這是我這次的結果」。
///
/// start／restart 只負責把行程拉起來，不等模型載完；要等就輪詢端點的 /health。
///
/// notes: 用檔案而不用 HTTP。動機是 Claude Code 的自動模式擋下「關掉 ZeroType 啟動的
///        行程再重開」；寫一個檔是 app 自己定義的介面，不必碰別人的行程。
///        也不必多開一個 port。權限邊界跟端點的 /shutdown 一樣：同一個使用者的程式都能用。
/// notes: 用 Directory.watch。天花板：網路磁碟或 watch 失效時收不到事件。
///        這裡另外每 5 秒補查一次，代價是最慢 5 秒才反應。
class LocalSttControl {
  LocalSttControl({required this.dir, required this.execute});

  /// 放請求檔與結果檔的資料夾。
  final Directory dir;

  /// 執行一個指令，回傳結果代碼（例如 restarted、stopped）。
  final Future<String> Function(String command) execute;

  static const requestName = 'local-stt.request';
  static const resultName = 'local-stt.result';
  static const commands = {'stop', 'start', 'restart'};

  File get _request => File('${dir.path}${Platform.pathSeparator}$requestName');
  File get _result => File('${dir.path}${Platform.pathSeparator}$resultName');

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _poll;
  bool _busy = false;

  /// 開始監看。啟動前留下的請求一律丟掉不執行：
  /// 啟動本來就會依設定拉起端點，舊的 stop 在這時候執行只會讓人摸不著頭緒。
  Future<void> start() async {
    await dir.create(recursive: true);
    if (await _request.exists()) {
      final stale = (await _readRequest()) ?? '';
      await _request.delete();
      await _writeResult(_parse(stale).id, _parse(stale).command, 'ignoredStale');
    }
    _watch = dir.watch().listen((event) {
      if (event.path.endsWith(requestName)) unawaited(processPending());
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => processPending());
  }

  Future<void> dispose() async {
    await _watch?.cancel();
    _poll?.cancel();
  }

  /// 有請求就處理。watch 一次寫入常發好幾個事件，_busy 讓同一份請求只跑一次。
  Future<void> processPending() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await _request.exists()) return;
      final raw = await _readRequest();
      if (raw == null) return; // 還在寫，下一個事件或下一輪再處理
      try {
        await _request.delete();
      } on FileSystemException {
        return; // 寫入端還開著檔案
      }
      final req = _parse(raw);
      if (!commands.contains(req.command)) {
        await _writeResult(req.id, req.command, 'unknownCommand');
        return;
      }
      print('[LocalSttControl] 收到 ${req.command}');
      String result;
      try {
        result = await execute(req.command);
      } catch (e) {
        result = 'error: $e';
      }
      print('[LocalSttControl] ${req.command} → $result');
      await _writeResult(req.id, req.command, result);
    } finally {
      _busy = false;
    }
  }

  /// 讀請求內容。空字串視為寫到一半，回 null 等下一輪。
  Future<String?> _readRequest() async {
    try {
      final text = (await _request.readAsString()).trim();
      return text.isEmpty ? null : text;
    } on FileSystemException {
      return null;
    }
  }

  static ({String command, String? id}) _parse(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    return (
      command: parts.isEmpty ? '' : parts.first.toLowerCase(),
      id: parts.length > 1 ? parts[1] : null,
    );
  }

  Future<void> _writeResult(String? id, String command, String result) async {
    final body = jsonEncode({
      'id': id,
      'command': command,
      'result': result,
      'at': DateTime.now().toIso8601String(),
    });
    // 先寫暫存檔再改名，讀的一方不會讀到寫一半的 JSON。
    final tmp = File('${_result.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(_result.path);
  }
}

/// 把指令對到 [LocalSttService] 的現有操作，與模型設定頁的按鈕走同一條路。
Future<String> runLocalSttCommand(LocalSttService service, String command) async {
  switch (command) {
    case 'stop':
      if (await service.health() == null) return 'notRunning';
      await service.shutdown();
      // 跟 restartIfRunning 一樣等 /health 連不上，最多 10 秒。
      for (var i = 0; i < 50 && await service.health() != null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return await service.health() == null ? 'stopped' : 'stuck';
    case 'start':
      if (await service.health() != null) return 'alreadyRunning';
      if (!service.canLaunch) return 'notLaunchable';
      await service.ensureRunning();
      return 'launched';
    case 'restart':
      if (await service.health() == null) {
        if (!service.canLaunch) return 'notLaunchable';
        await service.ensureRunning();
        return 'launched';
      }
      return (await service.restartIfRunning()).name;
    default:
      return 'unknownCommand';
  }
}
