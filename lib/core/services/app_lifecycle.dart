import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../di/injection.dart';

/// 回傳 true 表示本次是唯一實例;false 表示已有實例在跑(已請它把視窗叫出來),
/// 呼叫端應直接結束本次啟動。
/// [onSecondLaunch] 只在 socket 版路徑(非 Windows)會被呼叫;Windows 版是由
/// 後啟動的那個行程直接把既有視窗叫出來,不需要通知第一個實例。
Future<bool> ensureSingleInstance({required void Function() onSecondLaunch}) async {
  if (Platform.isWindows) return _ensureSingleInstanceWindows();
  return _ensureSingleInstanceSocket(onSecondLaunch);
}

// ---------- Windows:具名 mutex ----------

const _mutexName = 'ZeroType_SingleInstance';
const _errorAlreadyExists = 183;
const _swRestore = 9;
// Flutter runner 的視窗類別;搭配 window_manager 設定的標題一起比對,
// 才不會抓到自己這個行程剛建好的視窗(它的標題還是 main.cpp 的 "zero_type")。
const _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';
const _windowTitle = 'ZeroType';

bool _ensureSingleInstanceWindows() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final createMutexW = kernel32.lookupFunction<
      IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
      int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
  final getLastError =
      kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  final name = _mutexName.toNativeUtf16();
  final int lastError;
  try {
    // notes: handle 不關,行程結束由 OS 回收 —— 這正是我們要的持有期間。
    createMutexW(nullptr, 0, name);
    lastError = getLastError();
  } finally {
    calloc.free(name);
  }
  // 建立失敗(handle 0)時 lastError 也不會是 ALREADY_EXISTS,
  // 寧可讓程式照常啟動,也不要因為 mutex 建不出來就完全打不開。
  if (lastError != _errorAlreadyExists) return true;

  _activateExistingWindow();
  return false;
}

void _activateExistingWindow() {
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindowW = user32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
  final showWindow = user32.lookupFunction<Int32 Function(IntPtr, Int32),
      int Function(int, int)>('ShowWindow');
  final setForegroundWindow = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');

  final cls = _windowClass.toNativeUtf16();
  final title = _windowTitle.toNativeUtf16();
  try {
    final hwnd = findWindowW(cls, title);
    if (hwnd != 0) {
      showWindow(hwnd, _swRestore);
      setForegroundWindow(hwnd);
    }
  } finally {
    calloc.free(cls);
    calloc.free(title);
  }
}

// ---------- 其他平台:固定 loopback port 當鎖 ----------

// notes: macOS 沿用 socket 版,不另外做 NSRunningApplication 判斷。
// 天花板:若 port 被別的程式佔走會誤判成「已在執行」而拒絕啟動。
const _singleInstancePort = 45219;

Future<bool> _ensureSingleInstanceSocket(void Function() onSecondLaunch) async {
  try {
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, _singleInstancePort);
    server.listen((socket) {
      socket.destroy();
      onSecondLaunch();
    });
    return true;
  } on SocketException {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _singleInstancePort,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
    } catch (_) {
      // 連不上就算了,還是不啟動第二個實例
    }
    return false;
  }
}

/// 完全結束程式(非縮到系統匣)。
Never quitApp() {
  hotkeyService.dispose();
  trayService.dispose();
  exit(0);
}
