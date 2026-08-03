#include "channel_handler.h"

#include <windows.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>

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

// 把焦點切回目標視窗。
//
// SetForegroundWindow 對非前景行程通常會被 Windows 拒絕，而 ZeroType 正好
// 就不是前景（使用者是在別的 app 裡按熱鍵的）。附掛到目標的輸入佇列才拿得到
// 權限，這是這個限制的標準繞法。
static void FocusPasteTarget() {
  HWND target = g_paste_target;
  if (!target || !IsWindow(target)) return;
  if (GetForegroundWindow() == target) return;  // 焦點沒跑掉，不必動

  // SetForegroundWindow 對非前景行程通常會被 Windows 拒絕，附掛到目標的輸入
  // 佇列才拿得到權限。
  //
  // notes: 只做 SetForegroundWindow，不要再 SetFocus(target) —— target 是頂層
  // 視窗，附掛狀態下對它 SetFocus 會把鍵盤焦點從編輯子視窗搶走，Ctrl+V 就打進
  // 外框而不是編輯區。SetForegroundWindow 本來就會還原視窗內部原本的焦點。
  DWORD self = GetCurrentThreadId();
  DWORD other = GetWindowThreadProcessId(target, nullptr);
  BOOL attached = (self != other) && AttachThreadInput(self, other, TRUE);
  SetForegroundWindow(target);
  if (attached) AttachThreadInput(self, other, FALSE);
  // 焦點切換要一點時間才會落定，太快送 Ctrl+V 會打在切換的空檔。
  // 這裡是 UI 執行緒，但此刻畫面停在「已完成」，50ms 看不出來。
  Sleep(50);
}

// Simulates Ctrl+V (Windows paste shortcut) using Win32 SendInput.
// Equivalent to macOS CGEvent Cmd+V in AppDelegate.swift.
static void SimulatePaste() {
  FocusPasteTarget();

  INPUT inputs[4] = {};

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

  SendInput(4, inputs, sizeof(INPUT));
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
          SimulatePaste();
          result->Success(nullptr);
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

  // ── Control channel (stub) ──────────────────────────────────────────────
  // On Windows, cancel is triggered directly from the Flutter overlay widget.
  // The Dart side sets a handler on this channel; the native side is not
  // expected to invoke it on Windows.
  g_control_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/control",
          &flutter::StandardMethodCodec::GetInstance());

  g_control_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        result->Success(nullptr);
      });
}
