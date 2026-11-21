import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 本機辨識端點啟動失敗時，對使用者的提示。抽成介面是為了測試時可以換成假的。
abstract class LocalSttAlert {
  Future<bool> askFixReservedPort(int port);
  Future<void> showReservedPortManual(int port);

  /// 以系統管理員執行修正，成功回 true。
  Future<bool> reservePort(int port);
  Future<void> showFixFailed(int port);
  Future<void> showPortInUse(int port);
  Future<void> showCrashed(List<String> tail, String logPath);
}

const _title = 'ZeroType 本機辨識';

/// win32 5.15 沒有這個常數。
const _seeMaskNoCloseProcess = 0x00000040;

String _manualSteps(int port) => '請用系統管理員身分開啟 PowerShell，依序執行：\n'
    'net stop winnat\n'
    'netsh int ipv4 add excludedportrange protocol=tcp startport=$port numberofports=1 store=persistent\n'
    'net start winnat\n'
    '\n'
    '完成後，到 ZeroType 的模型設定按「啟動」。\n'
    '（這個視窗的文字可以按 Ctrl+C 複製。）';

/// notes: MessageBox 會擋住呼叫的執行緒，所以放進 Isolate.run，不能在 UI isolate 跑。
///        字串在 isolate 內配置與釋放（指標不能跨 isolate 傳）。
/// notes: hWnd 用 NULL：App 可能縮在系統匣，沒有視窗可當擁有者。
Future<int> _messageBox(String text, int extraFlags) {
  return Isolate.run(() {
    final lpText = text.toNativeUtf16();
    final lpCaption = _title.toNativeUtf16();
    try {
      return MessageBox(
        NULL,
        lpText,
        lpCaption,
        extraFlags | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND,
      );
    } finally {
      calloc.free(lpText);
      calloc.free(lpCaption);
    }
  });
}

class Win32LocalSttAlert implements LocalSttAlert {
  @override
  Future<bool> askFixReservedPort(int port) async {
    final result = await _messageBox(
      '本機辨識模型已經載入，但無法使用連接埠 $port，所以沒有啟動。\n'
      '\n'
      '原因：Windows 開機時把一段連接埠保留給系統（WinNAT／Hyper-V），$port 剛好在裡面。這不是每次開機都會發生。\n'
      '\n'
      '要現在修正嗎？\n'
      '按「是」：ZeroType 會要求系統管理員權限（會跳出 UAC），把 $port 永久保留給本機辨識，然後重新啟動端點。修正的幾秒內，WSL 與 Docker 的網路會中斷一下。\n'
      '按「否」：不修正。你可以之後自己修，做法見說明文件，或重新開機再試。',
      MB_YESNO,
    );
    return result == IDYES;
  }

  @override
  Future<void> showReservedPortManual(int port) => _messageBox(
        '本機辨識無法使用連接埠 $port（被 Windows 保留），所以沒有啟動。\n'
        '\n'
        '${_manualSteps(port)}',
        MB_OK,
      );

  @override
  Future<bool> reservePort(int port) {
    return Isolate.run(() {
      final verb = 'runas'.toNativeUtf16();
      final file = 'powershell.exe'.toNativeUtf16();
      final params = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden '
              '-Command "net stop winnat; '
              'netsh int ipv4 add excludedportrange protocol=tcp startport=$port numberofports=1 store=persistent; '
              r'$c=$LASTEXITCODE; net start winnat; exit $c"')
          .toNativeUtf16();
      final info = calloc<SHELLEXECUTEINFO>();
      final exitCode = calloc<Uint32>();
      try {
        info.ref
          ..cbSize = sizeOf<SHELLEXECUTEINFO>()
          ..fMask = _seeMaskNoCloseProcess
          ..lpVerb = verb
          ..lpFile = file
          ..lpParameters = params
          ..nShow = SW_HIDE;
        // 失敗包含使用者在 UAC 按「否」（錯誤碼 1223）。
        if (ShellExecuteEx(info) == 0) return false;
        final process = info.ref.hProcess;
        if (process == 0) return false;
        try {
          if (WaitForSingleObject(process, 60000) != WAIT_OBJECT_0) {
            return false;
          }
          if (GetExitCodeProcess(process, exitCode) == 0) return false;
          return exitCode.value == 0;
        } finally {
          CloseHandle(process);
        }
      } finally {
        calloc.free(verb);
        calloc.free(file);
        calloc.free(params);
        calloc.free(info);
        calloc.free(exitCode);
      }
    });
  }

  @override
  Future<void> showFixFailed(int port) => _messageBox(
        '自動修正沒有完成（取消了權限要求，或指令失敗）。\n'
        '\n'
        '${_manualSteps(port)}',
        MB_OK,
      );

  @override
  Future<void> showPortInUse(int port) => _messageBox(
        '本機辨識無法使用連接埠 $port，因為另一個程式正在使用它，所以沒有啟動。\n'
        '\n'
        '查是哪個程式：在 PowerShell 執行\n'
        'Get-NetTCPConnection -LocalPort $port | Select-Object OwningProcess\n'
        '再到工作管理員的「詳細資料」用 PID 找到它並關閉。\n'
        '\n'
        '完成後，到 ZeroType 的模型設定按「啟動」。',
        MB_OK,
      );

  @override
  Future<void> showCrashed(List<String> tail, String logPath) => _messageBox(
        '本機辨識端點啟動後自行結束了。\n'
        '\n'
        '記錄的最後幾行：\n'
        '${tail.join('\n')}\n'
        '\n'
        '完整記錄：$logPath',
        MB_OK,
      );
}
