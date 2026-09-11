import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

import '../constants/app_constants.dart';
import 'speech_recognition_service.dart';

/// LocalSTT 資料夾裡的檔名約定。
const _shimName = 'shim.py';
const _pythonRelative = r'repo\.venv\Scripts\python.exe';
const _logName = 'shim.log';

/// notes: 預設位址只寫一次。辨識請求用 kLocalTranscriptionUrl，這裡取它的
///        scheme://host:port，免得改了一邊忘了另一邊。
final _defaultOrigin = Uri.parse(kLocalTranscriptionUrl).origin;

/// notes: 預設用 python.exe 而不是 pythonw.exe。venv 裡的 pythonw.exe 是 uv 的跳板，
///        它生出來的是基底的 python.exe（主控台版），照樣配到一個視窗，
///        所以「無視窗直譯器」在這個 venv 裡根本不成立——實測留下一個標題空白的
///        PseudoConsoleWindow，使用者關掉它就等於把端點殺掉。
///        要藏就得由端點自己藏，見 _hideConsoleFlag。

/// 啟動參數的切法：認雙引號，其餘照空白切。
final _argPattern = RegExp(r'"([^"]*)"|(\S+)');

/// 管理本機辨識端點的生命週期：選了本機服務商就拉起來，離開 app 就關掉。
class LocalSttService {
  LocalSttService({required Dio dio, required SharedPreferences prefs})
      : _dio = dio,
        _prefs = prefs;

  final Dio _dio;
  final SharedPreferences _prefs;

  /// 只有「我們自己啟動的」才記在這裡。外部啟動的端點不歸我們管，也不該被我們殺掉。
  int? _pid;

  /// 上一次送出啟動指令的時間。用來擋住「模型還在載入時又按一次啟動」。
  DateTime? _startedAt;

  /// 端點資料夾可能在哪。使用者不必知道路徑，照這個順序找。
  ///
  /// notes: 判斷標準是資料夾裡有沒有 shim.py。多一個候選位置的代價是一次
  ///        existsSync，比要使用者自己填一條路徑便宜太多。
  /// notes: 只認跟使用者環境無關的位置——執行檔旁邊、使用者資料夾。
  ///        不要把任何一台特定機器的絕對路徑寫進來：這個 repo 是公開的，
  ///        而且每個人的環境不一樣。放在別處的人用「啟動設定（進階）」指定。
  List<String> get _rootCandidates {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final home = Platform.environment['USERPROFILE'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    return [
      '$exeDir\\LocalSTT',
      if (home != null && home.isNotEmpty) '$home\\LocalSTT',
      if (localAppData != null && localAppData.isNotEmpty)
        '$localAppData\\LocalSTT',
    ];
  }

  /// 自動找到的端點資料夾；null＝這台機器上沒裝。設定頁靠它決定要顯示什麼。
  String? get detectedRoot {
    for (final root in _rootCandidates) {
      if (File('$root\\$_shimName').existsSync()) return root;
    }
    return null;
  }

  /// 設定值優先；沒填就從自動找到的資料夾推。兩個都沒有就是空字串。
  String _resolved(String key, String relative) {
    final custom = _prefs.getString(key)?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final root = detectedRoot;
    return root == null ? '' : '$root\\$relative';
  }

  /// 端點位址。跟辨識請求共用「自建模型接口」那一個設定，不另外開一個欄位。
  ///
  /// notes: 那個欄位填的是完整的轉寫網址，這裡只取 scheme://host:port。
  ///        填得不成樣子就退回預設，不要讓一個打錯的字把啟動鍵也一起弄壞。
  String get _origin {
    final custom = _prefs.getString(AppConstants.customEndpointKey('local'));
    final uri = Uri.tryParse(custom?.trim() ?? '');
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      return _defaultOrigin;
    }
    return uri.host.isEmpty ? _defaultOrigin : uri.origin;
  }

  /// 端點在不在，不管是誰啟動的。
  String get healthUrl => '$_origin/health';
  String get shutdownUrl => '$_origin/shutdown';

  /// 目前生效的啟動設定。空字串＝找不到，也沒有人填——這時候不啟動。
  String get program => _resolved(AppConstants.localSttProgramKey, _pythonRelative);

  /// ZeroType 有沒有辦法自己把端點啟動起來。
  ///
  /// notes: 「有路徑」不等於「啟得動」。路徑是存在 prefs 裡跟著使用者走的，
  ///        資料夾搬過位置、換一台機器、或設定檔被複製過來，那條路徑就指向一個
  ///        不存在的檔案。只看 isNotEmpty 會給出一顆按了必定失敗的啟動鍵。
  ///        只驗直譯器本身：啟動參數可能是多個、帶引號，記錄檔則是啟動後才產生的。
  bool get canLaunch => program.isNotEmpty && File(program).existsSync();
  String get arguments => _resolved(AppConstants.localSttArgumentsKey, _shimName);
  String get logPath => _resolved(AppConstants.localSttLogPathKey, _logName);

  Future<void> saveLaunchSettings({
    required String program,
    required String arguments,
    required String logPath,
  }) async {
    await _prefs.setString(AppConstants.localSttProgramKey, program.trim());
    await _prefs.setString(AppConstants.localSttArgumentsKey, arguments.trim());
    await _prefs.setString(AppConstants.localSttLogPathKey, logPath.trim());
  }

  /// 確保端點可用。
  ///
  /// notes: 先探 /health 再決定要不要啟動。這一步同時擋掉兩種情況：使用者手動跑了
  ///        start.ps1，以及上次 app 崩潰留下的孤兒行程。少了它會啟動第二個行程，
  ///        第二個會因為 port 被佔而立刻死掉，而且死得無聲無息。
  Future<void> ensureRunning() async {
    if (await isHealthy()) {
      print('[LocalSTT] 端點已在執行，沿用既有行程');
      return;
    }

    // notes: 判斷「還活不活著」只看 /health，不看 _pid 是否為 null。
    //        外部打了 /shutdown、端點崩潰、使用者從工作管理員關掉，都會讓
    //        pid 留著但行程已死；拿它當依據就再也啟動不起來。
    //        _pid 只用來決定停止時該殺哪一棵行程樹。
    _pid = null;

    // 上一次啟動還在載模型（實測約 20 秒）就不要再開第二個。
    final startedAt = _startedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt).inSeconds < 90) {
      print('[LocalSTT] 上一次啟動仍在載入中，不重複啟動');
      return;
    }

    final program = this.program;
    if (program.isEmpty) {
      print('[LocalSTT] 這台機器上找不到本機辨識程式，不啟動');
      return;
    }
    if (!File(program).existsSync()) {
      print('[LocalSTT] 找不到啟動程式 $program，不啟動');
      return;
    }
    final arguments = _argPattern
        .allMatches(this.arguments)
        .map((m) => m.group(1) ?? m.group(2)!)
        .toList();

    final showConsole =
        _prefs.getBool(AppConstants.localSttShowConsoleKey) ?? false;
    final pid = _createProcess(
      program,
      arguments,
      _workingDirectory(program, arguments),
      showConsole: showConsole,
    );
    if (pid == 0) return;
    _pid = pid;
    _startedAt = DateTime.now();
    print('[LocalSTT] 已啟動端點 pid $pid，等待模型載入');
  }

  /// 自己呼叫 CreateProcess，因為主控台視窗只在建立行程那一刻決定得了。
  ///
  /// notes: 不能用 Process.start。Dart 沒有辦法指定 CREATE_NO_WINDOW，
  ///        它起出來的主控台程式一定會拿到一個主控台；Windows 11 再把那個主控台
  ///        交給 Windows Terminal，於是螢幕上多一個滿版視窗——關掉它就等於殺掉端點。
  ///        實測：子行程自己 ShowWindow(SW_HIDE) 只藏得掉自己那個 0x0 的
  ///        PseudoConsoleWindow 佔位視窗，真正看得見的是別的行程（WindowsTerminal）
  ///        開的視窗，藏不到。唯一擋得住的地方是建立行程的旗標。
  /// notes: 另一個附帶好處是不再有管道。Process.start 的 normal 模式會建管道，
  ///        沒人讀就會在幾 KB 之後把子行程卡死在寫入上；主控台沒有這個問題。
  /// notes: bInheritHandles 給 FALSE，也不設 STARTF_USESTDHANDLES——讓子行程直接
  ///        用新主控台的標準輸出。這樣「顯示視窗」時裡面才真的有字。
  int _createProcess(
    String program,
    List<String> arguments,
    String workingDirectory, {
    required bool showConsole,
  }) {
    final commandLine =
        [program, ...arguments].map((part) => '"$part"').join(' ');
    final lpCommandLine = commandLine.toNativeUtf16();
    final lpCurrentDirectory = workingDirectory.toNativeUtf16();
    final startupInfo = calloc<STARTUPINFO>();
    final processInfo = calloc<PROCESS_INFORMATION>();
    startupInfo.ref.cb = sizeOf<STARTUPINFO>();
    try {
      final ok = CreateProcess(
        nullptr,
        lpCommandLine,
        nullptr,
        nullptr,
        FALSE,
        showConsole ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW,
        nullptr,
        lpCurrentDirectory,
        startupInfo,
        processInfo,
      );
      if (ok == 0) {
        print('[LocalSTT] 啟動失敗，CreateProcess 錯誤碼 ${GetLastError()}');
        return 0;
      }
      // notes: 這兩個 handle 是 CreateProcess 開給我們的，不關就一直留著行程物件。
      //        關掉不會影響已經在跑的行程，停止時是用 pid 打 taskkill。
      CloseHandle(processInfo.ref.hThread);
      CloseHandle(processInfo.ref.hProcess);
      return processInfo.ref.dwProcessId;
    } finally {
      calloc.free(lpCommandLine);
      calloc.free(lpCurrentDirectory);
      calloc.free(startupInfo);
      calloc.free(processInfo);
    }
  }

  /// 從哪個目錄啟動。
  ///
  /// notes: 取「參數裡第一個確實存在的檔案」的所在目錄，通常就是腳本自己的資料夾
  ///        （LocalSTT 的情況是 shim.py 旁邊）；找不到就退回程式所在目錄。
  ///        這是猜的。端點程式如果靠相對路徑找資料，猜錯就會找不到——真的碰到了
  ///        就多開一個「工作目錄」欄位，在那之前不值得為它多一個設定項。
  String _workingDirectory(String program, List<String> arguments) {
    for (final arg in arguments) {
      if (File(arg).existsSync()) return File(arg).parent.path;
    }
    return File(program).parent.path;
  }

  /// 關掉我們自己啟動的端點。外部啟動的不動。
  ///
  /// 同步方法：要能在 quitApp() 這種 `Never` 的路徑上呼叫。
  void stop() {
    final pid = _pid;
    if (pid == null) return;
    _pid = null;
    _startedAt = null;
    // notes: 不能只殺我們拿到的那個 pid。venv 的 python.exe 是 uv 的跳板，
    //        真正跑端點的是它生出來的子行程（實測 29100 → 17636）。只殺跳板的話
    //        伺服器會變成孤兒，繼續佔著 GPU 記憶體與 port——那正是停止鍵要解決的事。
    //        taskkill /T 連整棵行程樹一起收。
    final result = Process.runSync('taskkill', ['/PID', '$pid', '/T', '/F']);
    print('[LocalSTT] 已關閉端點 pid $pid（exit ${result.exitCode}）');
  }

  /// 使用者按下「停止」：把端點關掉，GPU 記憶體還回來。
  ///
  /// notes: 不能只殺 _pid。使用者手動跑過 start.ps1、或上次 app 崩潰留下孤兒時，
  ///        _pid 是 null，但記憶體照樣被佔著——那正是使用者按下停止的理由。
  ///        所以沒有自己的行程時改打端點的 /shutdown，由它自己了結。
  Future<void> shutdown() async {
    if (_pid != null) {
      stop();
      return;
    }
    try {
      await _dio.post<dynamic>(
        shutdownUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );
      _startedAt = null;
      print('[LocalSTT] 已請求外部 shim 自行結束');
    } catch (e) {
      print('[LocalSTT] 停止失敗：$e');
    }
  }

  /// 讀端點記錄的最後幾行，給設定頁顯示。
  ///
  /// notes: 讀檔而不是接管道。管道只讀得到自己啟動的那個行程，而且不讀就會塞死
  ///        （見 ensureRunning 的註解）；檔案對「誰啟動的」一視同仁。
  /// notes: 預設 40 行而不是十來行。記錄檔裡不只有自訂訊息，還有函式庫警告與
  ///        traceback——出事時要看的就是那幾十行，截太短等於看不到原因。
  List<String> readLog({int lines = 40}) {
    final path = logPath;
    if (path.isEmpty) return const [];
    try {
      final file = File(path);
      if (!file.existsSync()) return const [];
      final all = file
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty)
          .toList();
      return all.length <= lines ? all : all.sublist(all.length - lines);
    } catch (e) {
      return ['讀取記錄失敗：$e'];
    }
  }

  /// 端點是否已經可以接受辨識請求。不管是誰啟動的。
  Future<bool> isHealthy() async {
    try {
      final response = await _dio.get<dynamic>(
        healthUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: const Duration(seconds: 2),
        ),
      );
      final data = response.data;
      return data is Map && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
