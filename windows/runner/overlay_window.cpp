#include "overlay_window.h"

#include <windows.h>
#include <windowsx.h>

#include <algorithm>
#include <string>

namespace {

constexpr wchar_t kClassName[] = L"ZeroTypeOverlayWindow";

// 版面尺寸都以 96 DPI 為基準，畫之前再乘上實際 DPI（見 Scale）。
constexpr int kHeight = 40;
constexpr int kPadX = 16;
constexpr int kDot = 8;
constexpr int kGap = 10;
constexpr int kBarCount = 5;
constexpr int kBarWidth = 3;
constexpr int kBarGap = 3;
constexpr int kBarMinHeight = 4;
constexpr int kBarMaxHeight = 20;
constexpr int kClose = 12;
constexpr int kBottomMargin = 12;
constexpr int kFontSize = 15;

// Flutter 版藥丸的固定亂數係數，讓每根長條的靈敏度不一樣。
constexpr double kBarFactors[kBarCount] = {0.72, 0.95, 0.55, 0.86, 0.63};

const COLORREF kBackground = RGB(0x1C, 0x1C, 0x1E);
// 文字與 ✕ 一律白色（對比 15.6:1）；階段由圓點與波形條的顏色帶。
const COLORREF kForeground = RGB(0xF5, 0xF5, 0xF7);

HWND g_hwnd = nullptr;
HFONT g_font = nullptr;
UINT g_dpi = 96;
std::wstring g_message;
COLORREF g_accent = RGB(0x30, 0xD1, 0x58);
bool g_bars = false;
double g_amplitude = 0.0;
void (*g_on_cancel)() = nullptr;

int Scale(int value) {
  return MulDiv(value, static_cast<int>(g_dpi), 96);
}

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int len = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                        static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                        out.data(), len);
  return out;
}

COLORREF AccentFor(const std::string& status, const std::wstring& message) {
  // 準備中（等藍牙麥克風就緒）在 Dart 端跟錄音共用 'recording' 這個 status，
  // 訊息文字是唯一能分辨的地方 —— 那段收到的音訊會被丟掉，顏色不能說在錄。
  if (message.rfind(L"準備中", 0) == 0) return RGB(0xFF, 0xAA, 0x00);
  if (status == "saving") return RGB(0xFF, 0xAA, 0x00);
  if (status == "transcribing") return RGB(0x63, 0xB3, 0xFF);
  if (status == "cancelling") return RGB(0x9E, 0x9E, 0x9E);
  return RGB(0x30, 0xD1, 0x58);
}

void EnsureFont() {
  if (g_font) return;
  LOGFONTW lf = {};
  lf.lfHeight = -Scale(kFontSize);
  lf.lfWeight = FW_SEMIBOLD;
  lf.lfQuality = CLEARTYPE_QUALITY;
  lf.lfCharSet = DEFAULT_CHARSET;
  wcscpy_s(lf.lfFaceName, L"Microsoft JhengHei UI");
  g_font = ::CreateFontIndirectW(&lf);
}

int TextWidth(const std::wstring& text) {
  HDC dc = ::GetDC(nullptr);
  HGDIOBJ old = ::SelectObject(dc, g_font);
  SIZE size = {};
  ::GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()), &size);
  ::SelectObject(dc, old);
  ::ReleaseDC(nullptr, dc);
  return size.cx;
}

int ContentWidth() {
  int w = Scale(kPadX) + Scale(kDot) + Scale(kGap);
  if (g_bars) w += kBarCount * Scale(kBarWidth + kBarGap) + Scale(kGap);
  w += TextWidth(g_message) + Scale(kGap) + Scale(kClose) + Scale(kPadX);
  return w;
}

void Paint(HWND hwnd) {
  PAINTSTRUCT ps = {};
  HDC dc = ::BeginPaint(hwnd, &ps);
  RECT rc = {};
  ::GetClientRect(hwnd, &rc);

  // 離屏繪製：振幅一秒更新十幾次，直接畫在視窗 DC 上會閃。
  HDC mem = ::CreateCompatibleDC(dc);
  HBITMAP bmp = ::CreateCompatibleBitmap(dc, rc.right, rc.bottom);
  HGDIOBJ old_bmp = ::SelectObject(mem, bmp);

  HBRUSH bg = ::CreateSolidBrush(kBackground);
  ::FillRect(mem, &rc, bg);
  ::DeleteObject(bg);

  const int mid = rc.bottom / 2;
  int x = Scale(kPadX);

  HBRUSH accent = ::CreateSolidBrush(g_accent);
  HGDIOBJ old_brush = ::SelectObject(mem, accent);
  HGDIOBJ old_pen = ::SelectObject(mem, ::GetStockObject(NULL_PEN));
  const int dot = Scale(kDot);
  ::Ellipse(mem, x, mid - dot / 2, x + dot + 1, mid + dot / 2 + 1);
  x += dot + Scale(kGap);

  if (g_bars) {
    for (int i = 0; i < kBarCount; ++i) {
      const double level = std::clamp(g_amplitude * kBarFactors[i], 0.0, 1.0);
      const int h = Scale(kBarMinHeight) +
                    static_cast<int>(Scale(kBarMaxHeight - kBarMinHeight) * level);
      RECT bar = {x, mid - h / 2, x + Scale(kBarWidth), mid + h / 2};
      ::FillRect(mem, &bar, accent);
      x += Scale(kBarWidth + kBarGap);
    }
    x += Scale(kGap);
  }
  ::SelectObject(mem, old_brush);
  ::DeleteObject(accent);

  HGDIOBJ old_font = ::SelectObject(mem, g_font);
  ::SetBkMode(mem, TRANSPARENT);
  ::SetTextColor(mem, kForeground);
  RECT text = {x, 0, rc.right, rc.bottom};
  ::DrawTextW(mem, g_message.c_str(), static_cast<int>(g_message.size()), &text,
              DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
  ::SelectObject(mem, old_font);

  // ✕：靠右，點下去取消這次錄音。
  const int c = Scale(kClose);
  const int cx = rc.right - Scale(kPadX) - c;
  HPEN pen = ::CreatePen(PS_SOLID, std::max(1, Scale(2)), kForeground);
  ::SelectObject(mem, pen);
  ::MoveToEx(mem, cx, mid - c / 2, nullptr);
  ::LineTo(mem, cx + c, mid + c / 2);
  ::MoveToEx(mem, cx + c, mid - c / 2, nullptr);
  ::LineTo(mem, cx, mid + c / 2);
  ::SelectObject(mem, old_pen);
  ::DeleteObject(pen);

  ::BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
  ::SelectObject(mem, old_bmp);
  ::DeleteObject(bmp);
  ::DeleteDC(mem);
  ::EndPaint(hwnd, &ps);
}

LRESULT CALLBACK OverlayProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  switch (msg) {
    case WM_PAINT:
      Paint(hwnd);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONDOWN: {
      RECT rc = {};
      ::GetClientRect(hwnd, &rc);
      // 只有右邊的 ✕ 算取消 —— 整片都能點的話，想把藥丸推開的一下就把錄音砍了。
      if (GET_X_LPARAM(lparam) >= rc.right - Scale(kPadX) - Scale(kClose) * 2 &&
          g_on_cancel) {
        g_on_cancel();
      }
      return 0;
    }
    default:
      return ::DefWindowProcW(hwnd, msg, wparam, lparam);
  }
}

void EnsureWindow() {
  if (g_hwnd) return;

  WNDCLASSW wc = {};
  wc.lpfnWndProc = OverlayProc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  ::RegisterClassW(&wc);

  // WS_EX_NOACTIVATE 是必要的：這個視窗一旦搶到焦點，錄音結束時要貼回去的
  // 那個目標視窗就變成它自己了。WS_EX_TOOLWINDOW 讓它不出現在工作列與 Alt+Tab。
  g_hwnd = ::CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kClassName, L"",
      WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, ::GetModuleHandleW(nullptr),
      nullptr);
  g_dpi = ::GetDpiForWindow(g_hwnd);
}

}  // namespace

void OverlayShow(const std::string& status, const std::string& message) {
  EnsureWindow();
  if (!g_hwnd) return;
  EnsureFont();

  g_message = Widen(message);
  g_accent = AccentFor(status, g_message);
  g_bars = (status == "recording" && g_message.rfind(L"準備中", 0) != 0) ||
           status == "saving";
  if (!g_bars) g_amplitude = 0.0;

  const int w = ContentWidth();
  const int h = Scale(kHeight);

  // notes: 只認主螢幕的工作區。多螢幕時藥丸永遠出現在主螢幕的工作列上方，
  // 不會跟著滑鼠或前景視窗跑。要跟的話改用 MonitorFromWindow(前景視窗)。
  RECT work = {};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const int x = work.left + (work.right - work.left - w) / 2;
  const int y = work.bottom - h - Scale(kBottomMargin);

  ::SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
  // 圓角：每次改寬度都要重設，區域是以視窗大小為準的。
  ::SetWindowRgn(g_hwnd, ::CreateRoundRectRgn(0, 0, w + 1, h + 1, h, h), TRUE);
  ::ShowWindow(g_hwnd, SW_SHOWNOACTIVATE);
  ::InvalidateRect(g_hwnd, nullptr, FALSE);
}

void OverlayHide() {
  if (g_hwnd) ::ShowWindow(g_hwnd, SW_HIDE);
  g_amplitude = 0.0;
}

void OverlaySetAmplitude(double amplitude) {
  if (!g_hwnd || !::IsWindowVisible(g_hwnd) || !g_bars) return;
  g_amplitude = std::clamp(amplitude, 0.0, 1.0);
  ::InvalidateRect(g_hwnd, nullptr, FALSE);
}

void OverlaySetCancelCallback(void (*callback)()) {
  g_on_cancel = callback;
}
