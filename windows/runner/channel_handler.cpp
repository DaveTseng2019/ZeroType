#include "channel_handler.h"

#include <windows.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <atomic>
#include <memory>
#include <variant>

// Keep channels alive for the duration of the app
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_keyboard_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_permission_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_overlay_channel;
static std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
    g_control_channel;

// ── 背景音樂：開始錄音時暫停 ────────────────────────────────────────────
//
// 只暫停，不自動恢復（要不要繼續聽由使用者決定）。
// VK_MEDIA_PLAY_PAUSE 是**切換鍵**，沒在播的時候按下去會反而開始播放，
// 所以送出前一定要先確認真的有東西在出聲——這個檢查同時也讓「已經暫停了」
// 的第二次錄音不會誤按，不必自己記狀態。

// 預設輸出裝置現在有沒有聲音。用 peak meter 而不是列舉 audio session ——
// 一個介面一次呼叫就夠，session 列舉要多繞好幾層。
//
// notes: peak 是瞬時值，歌曲間的空檔會讀到 0，那時就不暫停。誤判方向是安全的：
// 讀不到就維持現狀（音樂繼續放，跟改動前一樣），不會變成誤按而開始播放。
static bool IsRenderingAudio() {
  IMMDeviceEnumerator* enumerator = nullptr;
  // COM 已由 main.cpp 的 CoInitializeEx 初始化
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return false;
  }
  IMMDevice* device = nullptr;
  bool playing = false;
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                    &device))) {
    IAudioMeterInformation* meter = nullptr;
    if (SUCCEEDED(device->Activate(__uuidof(IAudioMeterInformation),
                                   CLSCTX_ALL, nullptr,
                                   reinterpret_cast<void**>(&meter)))) {
      float peak = 0.0f;
      if (SUCCEEDED(meter->GetPeakValue(&peak))) playing = peak > 0.001f;
      meter->Release();
    }
    device->Release();
  }
  enumerator->Release();
  return playing;
}

static void SendMediaPlayPause() {
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_MEDIA_PLAY_PAUSE;
  inputs[1] = inputs[0];
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(2, inputs, sizeof(INPUT));
}

static void PauseMedia() {
  if (!IsRenderingAudio()) return;
  SendMediaPlayPause();
}

// 貼上的目標視窗：按下熱鍵那一刻使用者正在打字的地方。
//
// 辨識要好幾秒，這期間焦點常常已經不在原本那個欄位了（切了視窗、點開
// ZeroType 自己看進度）。SendInput 只會送給當下的前景視窗，所以不記住目標
// 就會貼到錯的地方 —— 文字還在剪貼簿與歷史裡，但沒有進到使用者要的欄位。
static HWND g_paste_target = nullptr;

// 記下目前的前景視窗當作貼上目標。ZeroType 自己不能當目標，否則從自己的
// 視窗觸發錄音時會把文字貼進自己；這種情況保留上一次記到的視窗。
static void RememberPasteTarget() {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd) return;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == GetCurrentProcessId()) return;
  g_paste_target = hwnd;
}

// 把焦點切回目標視窗。切成功（或本來就沒有目標可切）回 true。
//
// SetForegroundWindow 對非前景行程通常會被 Windows 拒絕。前景權限屬於「當下的
// 前景執行緒」，所以要附掛到它的輸入佇列才拿得到 —— 附掛到 target 的執行緒沒有
// 用，target 此刻正好就不是前景。
static bool FocusPasteTarget() {
  HWND target = g_paste_target;
  if (!target || !IsWindow(target)) return true;  // 沒目標：照舊貼給目前前景
  HWND fg = GetForegroundWindow();
  if (fg == target) return true;  // 焦點沒跑掉，不必動

  // notes: 只做 SetForegroundWindow，不要再 SetFocus(target) —— target 是頂層
  // 視窗，附掛狀態下對它 SetFocus 會把鍵盤焦點從編輯子視窗搶走，Ctrl+V 就打進
  // 外框而不是編輯區。SetForegroundWindow 本來就會還原視窗內部原本的焦點。
  DWORD self = GetCurrentThreadId();
  DWORD fg_thread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
  DWORD target_thread = GetWindowThreadProcessId(target, nullptr);
  BOOL fg_attached =
      fg_thread && fg_thread != self && AttachThreadInput(self, fg_thread, TRUE);
  BOOL target_attached = target_thread != self && target_thread != fg_thread &&
                         AttachThreadInput(self, target_thread, TRUE);

  if (IsIconic(target)) ShowWindow(target, SW_RESTORE);
  SetForegroundWindow(target);

  if (fg_attached) AttachThreadInput(self, fg_thread, FALSE);
  if (target_attached) AttachThreadInput(self, target_thread, FALSE);

  // 焦點切換要一點時間才會落定，太快送 Ctrl+V 會打在切換的空檔。等到真的切過去
  // 再送；切不過去就回 false，寧可不貼也不要貼進別人的視窗（文字還在剪貼簿）。
  // 這裡是 UI 執行緒，但此刻畫面停在「已完成」，這點延遲看不出來。
  for (int i = 0; i < 12; ++i) {
    Sleep(25);
    if (GetForegroundWindow() == target) return true;
  }
  return false;
}

// Simulates Ctrl+V (Windows paste shortcut) using Win32 SendInput.
// Equivalent to macOS CGEvent Cmd+V in AppDelegate.swift.
// press_enter：精簡模式用，貼上後補一個 Enter 把訊息送出去。
static bool SimulatePaste(bool press_enter) {
  if (!FocusPasteTarget()) return false;

  INPUT inputs[6] = {};

  // Key down: Ctrl
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;

  // Key down: V
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';

  // Key up: V
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  // Key up: Ctrl
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  UINT count = 4;
  if (press_enter) {
    // 跟 Ctrl+V 同一批送出，中間不留空隙 —— 分兩次 SendInput 的話，Enter 可能
    // 趕在目標視窗處理完貼上之前抵達，送出去的就是一則空訊息。
    inputs[4].type = INPUT_KEYBOARD;
    inputs[4].ki.wVk = VK_RETURN;

    inputs[5].type = INPUT_KEYBOARD;
    inputs[5].ki.wVk = VK_RETURN;
    inputs[5].ki.dwFlags = KEYEVENTF_KEYUP;
    count = 6;
  }

  SendInput(count, inputs, sizeof(INPUT));
  return true;
}

// ── Esc 取消錄音的低階鍵盤鉤子 ──────────────────────────────────────────
//
// 只在錄音時（g_cancel_hotkey_armed）通知 Dart，其餘時間看到 Esc 一樣直接放行，
// 對其他 app 完全透明。
static std::atomic<bool> g_cancel_hotkey_armed{false};
static HHOOK g_keyboard_hook = nullptr;

static LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam,
                                              LPARAM lparam) {
  if (code == HC_ACTION && wparam == WM_KEYDOWN && g_cancel_hotkey_armed) {
    auto* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    if (info->vkCode == VK_ESCAPE && g_control_channel) {
      g_control_channel->InvokeMethod(
          "cancel", std::make_unique<flutter::EncodableValue>());
    }
  }
  return ::CallNextHookEx(nullptr, code, wparam, lparam);
}

void SetupChannels(flutter::BinaryMessenger* messenger) {
  // ── Keyboard channel ────────────────────────────────────────────────────
  // Handles simulatePaste → Win32 SendInput Ctrl+V
  g_keyboard_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/keyboard",
          &flutter::StandardMethodCodec::GetInstance());

  g_keyboard_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "simulatePaste") {
          bool press_enter = false;
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto it = args->find(flutter::EncodableValue("pressEnter"));
            if (it != args->end()) {
              if (const auto* v = std::get_if<bool>(&it->second)) {
                press_enter = *v;
              }
            }
          }
          result->Success(flutter::EncodableValue(SimulatePaste(press_enter)));
        } else if (call.method_name() == "rememberPasteTarget") {
          RememberPasteTarget();
          result->Success(nullptr);
        } else if (call.method_name() == "pauseMedia") {
          PauseMedia();
          result->Success(nullptr);
        } else {
          result->NotImplemented();
        }
      });

  // ── Permission channel ──────────────────────────────────────────────────
  // Windows: SendInput does not require Accessibility permission.
  // Return true for checkAccessibility so the Settings page shows it as granted.
  g_permission_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/permission",
          &flutter::StandardMethodCodec::GetInstance());

  g_permission_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "checkAccessibility") {
          // No special permission required on Windows
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "openAccessibilitySettings") {
          // No-op on Windows
          result->Success(nullptr);
        } else {
          result->NotImplemented();
        }
      });

  // ── Overlay channel (stub) ──────────────────────────────────────────────
  // On Windows, overlay is handled by the Flutter RecordingOverlay widget.
  // These stubs prevent MissingPluginException on the Dart side.
  g_overlay_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/overlay",
          &flutter::StandardMethodCodec::GetInstance());

  g_overlay_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        // Dart side already has try-catch; stubs are just a safety net
        result->Success(nullptr);
      });

  // ── Control channel ──────────────────────────────────────────────────────
  // Dart calls setCancelHotkeyArmed(bool) while recording is active; native
  // calls back with "cancel" when Esc is pressed while armed. See the
  // keyboard-hook block below for why this replaced a RegisterHotKey-based
  // Esc (that approach either had to steal Esc from every other app, or crash
  // a vendor plugin bug when unregistering).
  g_control_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/control",
          &flutter::StandardMethodCodec::GetInstance());

  g_control_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setCancelHotkeyArmed") {
          const auto* armed = std::get_if<bool>(call.arguments());
          g_cancel_hotkey_armed = armed != nullptr && *armed;
        }
        result->Success(nullptr);
      });

  // ── Esc 取消錄音（不獨佔）───────────────────────────────────────────────
  //
  // 錄音當下焦點幾乎都在別的應用程式，之前試過用 hotkey_manager 的
  // RegisterHotKey 註冊全域 Esc：Windows 會把 Esc 整個從系統攔下只送給
  // ZeroType，其他 app 收不到那個按鍵；註冊/解除的時機一沒抓準，
  // 外掛的 Windows 端在 unregister 一個沒登記的 identifier 時還會丟出
  // 未接的 C++ 例外把整個程式炸掉。
  //
  // 低階鍵盤鉤子不會有這兩個問題：CallNextHookEx 永遠放行，其他 app 該收到的
  // Esc 照樣收得到；鉤子本身在整個程式生命週期只裝一次，「錄音中才生效」純粹
  // 靠 g_cancel_hotkey_armed 這個旗標開關，沒有 register/unregister 的時序可出錯。
  if (!g_keyboard_hook) {
    g_keyboard_hook =
        ::SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, nullptr, 0);
  }
}
