#include "channel_handler.h"

#include "overlay_window.h"

#include <windows.h>
#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <atomic>
#include <memory>
#include <string>
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

// 目標視窗裡當時正在打字的那個子控制項。頂層視窗不夠 —— 見 RestoreInnerFocus。
static HWND g_paste_focus = nullptr;

// 記下目前的前景視窗當作貼上目標。ZeroType 自己不能當目標，否則從自己的
// 視窗觸發錄音時會把文字貼進自己；這種情況保留上一次記到的視窗。
static void RememberPasteTarget() {
  HWND hwnd = GetForegroundWindow();
  if (!hwnd) return;
  DWORD pid = 0;
  DWORD tid = GetWindowThreadProcessId(hwnd, &pid);
  if (pid == GetCurrentProcessId()) return;
  g_paste_target = hwnd;

  GUITHREADINFO gui = {};
  gui.cbSize = sizeof(gui);
  g_paste_focus = GetGUIThreadInfo(tid, &gui) ? gui.hwndFocus : nullptr;
}

// 把焦點放回熱鍵按下那一刻的子控制項。
//
// SetForegroundWindow 會還原視窗內部的焦點，但還原到哪由那個程式自己決定，不保證是
// 使用者剛剛在打字的地方 —— EmEditor 實測會落在 EmEditorMenuBar，Ctrl+V 就打進選單列
// 而不是編輯區。所以不能只靠它，要拿記到的子控制項補一次。
//
// notes: 補的是「記到的子控制項」，不是 target 本身。對頂層視窗 SetFocus 會把鍵盤焦點
// 從編輯子視窗搶走，那是更早踩過的坑。跨執行緒 SetFocus 一定要先 AttachThreadInput。
static void RestoreInnerFocus(HWND target) {
  HWND want = g_paste_focus;
  if (!want || !IsWindow(want)) return;
  DWORD self = GetCurrentThreadId();
  DWORD tid = GetWindowThreadProcessId(target, nullptr);
  if (tid == self) return;
  if (!AttachThreadInput(self, tid, TRUE)) return;
  if (GetFocus() != want) SetFocus(want);
  AttachThreadInput(self, tid, FALSE);
}

// 把焦點切回目標視窗。切成功（或本來就沒有目標可切）回 true。
//
// SetForegroundWindow 對非前景行程通常會被 Windows 拒絕。前景權限屬於「當下的
// 前景執行緒」，所以要附掛到它的輸入佇列才拿得到 —— 附掛到 target 的執行緒沒有
// 用，target 此刻正好就不是前景。
static bool FocusPasteTarget() {
  HWND target = g_paste_target;
  // 沒目標＝按熱鍵那一刻焦點在 ZeroType 自己身上，而且還沒記過任何視窗（剛開好的
  // 行程）。這時盲貼給當下的前景視窗只會打進不相干的地方，寧可不貼 —— 文字還在
  // 剪貼簿跟歷史紀錄裡，呼叫端會記一筆錯誤。
  if (!target || !IsWindow(target)) return false;
  HWND fg = GetForegroundWindow();
  if (fg == target) {
    RestoreInnerFocus(target);  // 視窗沒跑掉，但內部焦點可能跑了
    return true;
  }

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
    if (GetForegroundWindow() == target) {
      RestoreInnerFocus(target);
      return true;
    }
  }
  return false;
}

static std::string Utf8(const wchar_t* s) {
  if (!s || !*s) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return {};
  std::string out(static_cast<size_t>(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s, -1, out.data(), n, nullptr, nullptr);
  return out;
}

// 目標視窗內部真正有鍵盤焦點的子控制項。
//
// hwndFocus 只涵蓋 target 自己那條 UI 執行緒。焦點若落在別條執行緒或別的行程
// （WebView2 之類的宿主控制項就是這樣），這裡會拿到 nullptr —— 那件事本身就是線索。
static HWND FocusedChildOfTarget() {
  HWND target = g_paste_target;
  if (!target || !IsWindow(target)) return nullptr;
  GUITHREADINFO gui = {};
  gui.cbSize = sizeof(gui);
  if (!GetGUIThreadInfo(GetWindowThreadProcessId(target, nullptr), &gui)) {
    return nullptr;
  }
  return gui.hwndFocus;
}

static bool IsClass(HWND hwnd, const wchar_t* name) {
  if (!hwnd) return false;
  wchar_t cls[64] = {};
  GetClassNameW(hwnd, cls, 64);
  return wcscmp(cls, name) == 0;
}

// 診斷用：貼上目標到底是誰。
//
// focus= 那一欄才是重點：像 Visual Studio 這種多面板的程式，頂層視窗永遠是同一個
// devenv，真正收到按鍵的是哪個子控制項（終端機分頁還是程式碼編輯器）決定了成敗。
// 貼上失敗時光有頂層視窗的標題看不出差別。
static std::string DescribePasteTarget() {
  HWND target = g_paste_target;
  if (!target) return "(沒記到目標，貼給當下的前景視窗)";
  if (!IsWindow(target)) return "(記到的視窗已經關掉了)";

  wchar_t title[160] = {};
  wchar_t cls[128] = {};
  GetWindowTextW(target, title, 160);
  GetClassNameW(target, cls, 128);

  DWORD pid = 0;
  GetWindowThreadProcessId(target, &pid);

  std::string focus = "(不在同一條 UI 執行緒)";
  if (HWND child = FocusedChildOfTarget()) {
    wchar_t focus_cls[128] = {};
    GetClassNameW(child, focus_cls, 128);
    char buf[64] = {};
    sprintf_s(buf, "0x%p ", reinterpret_cast<void*>(child));
    focus = std::string(buf) + Utf8(focus_cls);
  }

  // 記到的焦點 vs 實際焦點：兩者不一樣就是 RestoreInnerFocus 沒把焦點救回來
  char head[128] = {};
  sprintf_s(head, "hwnd=0x%p pid=%lu 記到的焦點=0x%p ",
            reinterpret_cast<void*>(target), pid,
            reinterpret_cast<void*>(g_paste_focus));
  return std::string(head) + "cls=" + Utf8(cls) + " title=\"" + Utf8(title) +
         "\" focus=" + focus;
}

// Simulates Ctrl+V (Windows paste shortcut) using Win32 SendInput.
// Equivalent to macOS CGEvent Cmd+V in AppDelegate.swift.
// press_enter：精簡模式用，貼上後補一個 Enter 把訊息送出去。
static bool SimulatePaste(bool press_enter) {
  if (!FocusPasteTarget()) return false;

  // VS 內建終端機（Windows Terminal 的 HwndTerminal 宿主控制項）不吃注入的鍵盤
  // 貼上。它的 wndproc 根本沒有 WM_KEYDOWN 分支，鍵盤要進去得靠宿主攔截後呼叫
  // 匯出的 TerminalSendKeyEvent；貼上則只實作在 WM_RBUTTONDOWN 裡，直接讀
  // CF_UNICODETEXT 寫進 pty（microsoft/terminal，src/cascadia/TerminalControl/
  // HwndTerminal.cpp:184 與 :1127）。所以這裡補的是右鍵，跟使用者手動做的一模一樣，
  // 不必去賭 VS 宿主怎麼路由鍵盤。
  //
  // notes: 控制項若正有選取範圍，右鍵是「複製」不是「貼上」（同一個 case 的前半段），
  // 那時這次貼上會沒作用、且剪貼簿被選取內容蓋掉。手動右鍵本來就有同樣的行為，
  // 文字也還在歷史紀錄裡。真的會踩到再處理。
  HWND focus = FocusedChildOfTarget();
  const bool vs_terminal = IsClass(focus, L"HwndTerminalClass");
  if (vs_terminal) {
    // 用 SendMessageTimeout 而不是 PostMessage：精簡模式接著要補 Enter，得先確定
    // 貼上真的處理完了，不然 Enter 會搶在前面把空訊息送出去。ABORTIFHUNG 顧的是
    // 對方沒回應時不要把我們的 UI 執行緒一起卡死。
    DWORD_PTR unused = 0;
    SendMessageTimeout(focus, WM_RBUTTONDOWN, MK_RBUTTON, 0, SMTO_ABORTIFHUNG,
                       1000, &unused);
    SendMessageTimeout(focus, WM_RBUTTONUP, 0, 0, SMTO_ABORTIFHUNG, 1000,
                       &unused);
  }

  INPUT inputs[8] = {};
  UINT count = 0;
  // wScan 一定要填。只給 wVk 的話，產生出來的 WM_KEYDOWN 其 lParam 裡 scan code
  // 是 0；一般 Edit 控制項不在乎（它們吃 TranslateMessage 產出的 WM_CHAR），但
  // 讀 scan code 的宿主控制項會整個忽略這個按鍵 —— VS 內建終端機的
  // HwndTerminalClass 就是這樣，實測 Ctrl+Shift+V 送得出去卻毫無反應。
  // 真實鍵盤本來就同時帶 vk 和 scan code，這裡只是照做。
  auto key = [&](WORD vk, DWORD flags) {
    inputs[count].type = INPUT_KEYBOARD;
    inputs[count].ki.wVk = vk;
    inputs[count].ki.wScan =
        static_cast<WORD>(MapVirtualKeyW(vk, MAPVK_VK_TO_VSC));
    inputs[count].ki.dwFlags = flags;
    ++count;
  };

  if (!vs_terminal) {
    key(VK_CONTROL, 0);
    key('V', 0);
    key('V', KEYEVENTF_KEYUP);
    key(VK_CONTROL, KEYEVENTF_KEYUP);
  }

  if (press_enter) {
    // 跟 Ctrl+V 同一批送出，中間不留空隙 —— 分兩次 SendInput 的話，Enter 可能
    // 趕在目標視窗處理完貼上之前抵達，送出去的就是一則空訊息。
    key(VK_RETURN, 0);
    key(VK_RETURN, KEYEVENTF_KEYUP);
  }

  if (count) SendInput(count, inputs, sizeof(INPUT));
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
        } else if (call.method_name() == "describePasteTarget") {
          result->Success(flutter::EncodableValue(DescribePasteTarget()));
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

  // ── Overlay channel ─────────────────────────────────────────────────────
  // 錄音提示畫在一個置頂的原生小視窗上（overlay_window.cpp），不是 Flutter
  // widget —— 主視窗被蓋住或縮到系統匣時，widget 根本不在畫面上。
  g_overlay_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.zerotype.app/overlay",
          &flutter::StandardMethodCodec::GetInstance());

  OverlaySetCancelCallback([]() {
    if (g_control_channel) {
      g_control_channel->InvokeMethod(
          "cancel", std::make_unique<flutter::EncodableValue>());
    }
  });

  g_overlay_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        auto arg = [args](const char* key) -> const flutter::EncodableValue* {
          if (!args) return nullptr;
          const auto it = args->find(flutter::EncodableValue(key));
          return it == args->end() ? nullptr : &it->second;
        };

        if (call.method_name() == "show") {
          const auto* status = arg("status");
          const auto* message = arg("message");
          OverlayShow(status ? std::get<std::string>(*status) : std::string(),
                      message ? std::get<std::string>(*message) : std::string());
        } else if (call.method_name() == "hide") {
          OverlayHide();
        } else if (call.method_name() == "updateAmplitude") {
          if (const auto* amp = arg("amplitude")) {
            if (const auto* value = std::get_if<double>(amp)) {
              OverlaySetAmplitude(*value);
            }
          }
        }
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
