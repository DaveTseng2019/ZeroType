#include "picker_window.h"

#include <windows.h>
#include <windowsx.h>
#include <imm.h>
#include <shellscalingapi.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kClassName[] = L"ZeroTypePickerWindow";

// 版面尺寸都以 96 DPI 為基準，畫之前再乘上實際 DPI（見 Scale）。
constexpr int kWidth = 520;
constexpr int kPadX = 14;
constexpr int kPadY = 8;
constexpr int kFilterHeight = 38;
constexpr int kRowHeight = 30;
constexpr int kHintHeight = 26;
constexpr int kMaxRows = 8;
constexpr int kFontSize = 15;
constexpr int kHintFontSize = 12;
constexpr int kRadius = 12;
constexpr int kMarkerWidth = 3;
constexpr int kCaretGap = 6;

const COLORREF kBackground = RGB(0x1C, 0x1C, 0x1E);
const COLORREF kForeground = RGB(0xF5, 0xF5, 0xF7);
const COLORREF kMuted = RGB(0x8E, 0x8E, 0x93);
const COLORREF kBorder = RGB(0x3A, 0x3A, 0x3E);
const COLORREF kRowSelected = RGB(0x2E, 0x2E, 0x33);
// 品牌橘，跟 AppTheme.primaryOrange 同一個值
const COLORREF kAccent = RGB(0xFF, 0x7A, 0x00);
// 有焦點時的外框。用品牌橘的六成亮度 —— 整框滿版的橘太搶眼，會蓋過清單裡
// 真正要看的那一列反白。
const COLORREF kAccentDim = RGB(0x99, 0x49, 0x00);

// 剛顯示的這段時間內丟掉的焦點不算「使用者點到別處」。
//
// notes: Windows 的前景權限是熱鍵那一刻給的，經過 Dart 繞一圈再回來搶前景時，
// 偶爾會被原本的前景視窗搶回去（EmEditor 實測第一次按就會）。這段時間內收到
// WM_KILLFOCUS 就再搶一次，而不是把浮窗收掉。
constexpr ULONGLONG kSettleMs = 400;

// 多久檢查一次貼上目標還在不在。500ms 是「關掉視窗後浮窗跟著消失」看起來
// 即時、又不會讓一個閒置的浮窗每秒醒來太多次的折衷。
constexpr UINT kWatchdogMs = 500;
constexpr UINT_PTR kWatchdogTimerId = 1;

HWND g_hwnd = nullptr;
HFONT g_font = nullptr;
HFONT g_hint_font = nullptr;
HCURSOR g_arrow = nullptr;
UINT g_dpi = 96;

std::vector<std::wstring> g_items;   // 原始清單，索引就是回報給 Dart 的 index
std::vector<std::wstring> g_folded;  // 同一順序的小寫版，過濾時比對用
std::vector<int> g_matched;          // 通過過濾的原始索引
std::wstring g_filter;
int g_selected = 0;  // g_matched 裡的位置
int g_scroll = 0;    // 目前捲到第幾筆（g_matched 裡的位置）

// 自己關視窗時 WM_KILLFOCUS 會跟著來，那一下不算「使用者點到別處」。
bool g_closing = false;
ULONGLONG g_shown_at = 0;
bool g_settle_retried = false;

// 有沒有鍵盤焦點。外框跟著它變色 —— 焦點被別的視窗搶走時浮窗還在畫面上，
// 但打字不會進來，外框是唯一看得出這件事的地方。
bool g_focused = false;

// 用鍵盤時把滑鼠游標藏起來：游標剛好停在某一列上的話，它會一直把反白搶回去，
// 也擋住正在看的字。滑鼠真的移動了才讓它回來。
bool g_hide_cursor = false;
POINT g_last_cursor_pos = {LONG_MIN, LONG_MIN};

void (*g_on_pick)(int) = nullptr;
void (*g_on_cancel)(const char*) = nullptr;
bool (*g_target_alive)() = nullptr;

// 叫出來的當下目標就已經不在了（例如從 ZeroType 自己的視窗按熱鍵），那就別看門，
// 不然浮窗會一出現就被自己收掉，看起來像熱鍵沒反應。
bool g_watch_target = false;

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

// 換行的詞彙在清單裡只佔一行，字面照舊（送出去的是原文，不是這個）。
std::wstring OneLine(const std::wstring& text) {
  std::wstring out = text;
  for (auto& ch : out) {
    if (ch == L'\r' || ch == L'\n' || ch == L'\t') ch = L' ';
  }
  return out;
}

std::wstring Fold(const std::wstring& text) {
  std::wstring out = text;
  if (!out.empty()) {
    ::CharLowerBuffW(out.data(), static_cast<DWORD>(out.size()));
  }
  return out;
}

// 換 DPI：字型的大小是用 g_dpi 算出來的，值變了就得整批重做。
void SetDpi(UINT dpi);

void EnsureFonts() {
  if (g_font && g_hint_font) return;
  auto make = [](int size, int weight) {
    LOGFONTW lf = {};
    lf.lfHeight = -Scale(size);
    lf.lfWeight = weight;
    lf.lfQuality = CLEARTYPE_QUALITY;
    lf.lfCharSet = DEFAULT_CHARSET;
    wcscpy_s(lf.lfFaceName, L"Microsoft JhengHei UI");
    return ::CreateFontIndirectW(&lf);
  };
  if (!g_font) g_font = make(kFontSize, FW_NORMAL);
  if (!g_hint_font) g_hint_font = make(kHintFontSize, FW_NORMAL);
}

void SetDpi(UINT dpi) {
  if (dpi < 48 || dpi == g_dpi) return;
  g_dpi = dpi;
  if (g_font) {
    ::DeleteObject(g_font);
    g_font = nullptr;
  }
  if (g_hint_font) {
    ::DeleteObject(g_hint_font);
    g_hint_font = nullptr;
  }
  EnsureFonts();
}

int VisibleRows() {
  return std::min(kMaxRows, std::max(1, static_cast<int>(g_matched.size())));
}

int WindowHeight() {
  return Scale(kFilterHeight) + VisibleRows() * Scale(kRowHeight) +
         Scale(kHintHeight) + Scale(kPadY);
}

// 讓選到的那一筆一定在可視範圍內。
void EnsureSelectionVisible() {
  const int rows = VisibleRows();
  if (g_selected < g_scroll) g_scroll = g_selected;
  if (g_selected >= g_scroll + rows) g_scroll = g_selected - rows + 1;
  const int max_scroll = std::max(0, static_cast<int>(g_matched.size()) - rows);
  g_scroll = std::clamp(g_scroll, 0, max_scroll);
}

// 過濾規則：關鍵字（小寫化後）是不是詞彙的子字串。中文沒有大小寫，
// 小寫化只影響英數，剛好讓英文詞彙不分大小寫。
void ApplyFilter() {
  const std::wstring needle = Fold(g_filter);
  g_matched.clear();
  for (size_t i = 0; i < g_items.size(); ++i) {
    if (needle.empty() || g_folded[i].find(needle) != std::wstring::npos) {
      g_matched.push_back(static_cast<int>(i));
    }
  }
  g_selected = 0;
  g_scroll = 0;
}

// 高度會隨著過濾結果變，寬度與左上角不動（使用者可能已經把它拖到別處）。
void Layout() {
  if (!g_hwnd) return;
  RECT rc = {};
  ::GetWindowRect(g_hwnd, &rc);
  const int w = rc.right - rc.left;
  const int h = WindowHeight();
  if (h == rc.bottom - rc.top) return;
  ::SetWindowPos(g_hwnd, HWND_TOPMOST, 0, 0, w, h,
                 SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER);
  ::SetWindowRgn(g_hwnd,
                 ::CreateRoundRectRgn(0, 0, w + 1, h + 1, Scale(kRadius),
                                      Scale(kRadius)),
                 TRUE);
}

// 中文輸入法的組字視窗要跟著關鍵字走，不然候選字會蓋在清單上或跑到畫面角落。
void MoveCompositionWindow() {
  if (!g_hwnd) return;
  HIMC imc = ::ImmGetContext(g_hwnd);
  if (!imc) return;
  COMPOSITIONFORM form = {};
  form.dwStyle = CFS_POINT;
  form.ptCurrentPos.x = Scale(kPadX);
  form.ptCurrentPos.y = Scale(kFilterHeight) - Scale(kPadY);
  ::ImmSetCompositionWindow(imc, &form);
  ::ImmReleaseContext(g_hwnd, imc);
}

void Refresh() {
  Layout();
  MoveCompositionWindow();
  if (g_hwnd) ::InvalidateRect(g_hwnd, nullptr, FALSE);
}

// 用鍵盤操作時把游標藏起來，並記住此刻的位置 —— 之後只有真的移動過才算數。
void HideCursorForKeyboard() {
  ::GetCursorPos(&g_last_cursor_pos);
  if (g_hide_cursor) return;
  g_hide_cursor = true;
  ::SetCursor(nullptr);
}

void ShowCursorAgain() {
  if (!g_hide_cursor) return;
  g_hide_cursor = false;
  ::SetCursor(g_arrow);
}

void Paint(HWND hwnd) {
  PAINTSTRUCT ps = {};
  HDC dc = ::BeginPaint(hwnd, &ps);
  RECT rc = {};
  ::GetClientRect(hwnd, &rc);

  // 離屏繪製：每按一個鍵整片都要重畫，直接畫在視窗 DC 上會閃。
  HDC mem = ::CreateCompatibleDC(dc);
  HBITMAP bmp = ::CreateCompatibleBitmap(dc, rc.right, rc.bottom);
  HGDIOBJ old_bmp = ::SelectObject(mem, bmp);

  HBRUSH bg = ::CreateSolidBrush(kBackground);
  ::FillRect(mem, &rc, bg);
  ::DeleteObject(bg);

  ::SetBkMode(mem, TRANSPARENT);
  HGDIOBJ old_font = ::SelectObject(mem, g_font);

  const int pad = Scale(kPadX);
  const int filter_h = Scale(kFilterHeight);

  // ── 過濾用的關鍵字列（同時是拖曳把手）──
  RECT filter_rc = {pad, 0, rc.right - pad, filter_h};
  const bool empty_filter = g_filter.empty();
  const std::wstring filter_text =
      empty_filter ? std::wstring(L"輸入關鍵字過濾…") : g_filter;
  ::SetTextColor(mem, empty_filter ? kMuted : kForeground);
  ::DrawTextW(mem, filter_text.c_str(), static_cast<int>(filter_text.size()),
              &filter_rc, DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);

  // 文字游標：畫在關鍵字後面，讓人看得出這裡可以打字
  if (!empty_filter) {
    SIZE size = {};
    ::GetTextExtentPoint32W(mem, g_filter.c_str(),
                            static_cast<int>(g_filter.size()), &size);
    RECT caret = {pad + size.cx + Scale(2), filter_h / 2 - Scale(kFontSize) / 2,
                  pad + size.cx + Scale(2) + std::max(1, Scale(1)),
                  filter_h / 2 + Scale(kFontSize) / 2};
    HBRUSH caret_brush = ::CreateSolidBrush(kAccent);
    ::FillRect(mem, &caret, caret_brush);
    ::DeleteObject(caret_brush);
  }

  RECT line = {0, filter_h, rc.right, filter_h + 1};
  HBRUSH divider = ::CreateSolidBrush(kBorder);
  ::FillRect(mem, &line, divider);

  // ── 清單 ──
  const int row_h = Scale(kRowHeight);
  if (g_matched.empty()) {
    RECT row = {pad, filter_h, rc.right - pad, filter_h + row_h};
    const std::wstring msg = g_items.empty()
                                 ? std::wstring(L"還沒有常用詞彙")
                                 : std::wstring(L"沒有符合的詞彙");
    ::SetTextColor(mem, kMuted);
    ::DrawTextW(mem, msg.c_str(), static_cast<int>(msg.size()), &row,
                DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
  } else {
    const int rows = VisibleRows();
    for (int i = 0; i < rows; ++i) {
      const int pos = g_scroll + i;
      if (pos >= static_cast<int>(g_matched.size())) break;
      const int top = filter_h + i * row_h;
      RECT row = {0, top, rc.right, top + row_h};
      if (pos == g_selected) {
        HBRUSH sel = ::CreateSolidBrush(kRowSelected);
        ::FillRect(mem, &row, sel);
        ::DeleteObject(sel);
        RECT marker = {0, top, Scale(kMarkerWidth), top + row_h};
        HBRUSH accent = ::CreateSolidBrush(kAccent);
        ::FillRect(mem, &marker, accent);
        ::DeleteObject(accent);
      }
      RECT text = {pad, top, rc.right - pad, top + row_h};
      const std::wstring label = OneLine(g_items[g_matched[pos]]);
      ::SetTextColor(mem, pos == g_selected ? kForeground : kMuted);
      ::DrawTextW(mem, label.c_str(), static_cast<int>(label.size()), &text,
                  DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX |
                      DT_END_ELLIPSIS);
    }
  }

  // ── 底部提示（同時是拖曳把手）──
  const int hint_top = filter_h + VisibleRows() * row_h;
  RECT hint_line = {0, hint_top, rc.right, hint_top + 1};
  ::FillRect(mem, &hint_line, divider);
  ::DeleteObject(divider);

  ::SelectObject(mem, g_hint_font);
  ::SetTextColor(mem, kMuted);
  RECT hint = {pad, hint_top, rc.right - pad, rc.bottom};
  const std::wstring hint_text = L"↑↓ 選擇   Enter 貼上   Esc 取消   拖曳可移動";
  ::DrawTextW(mem, hint_text.c_str(), static_cast<int>(hint_text.size()), &hint,
              DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_NOPREFIX);
  if (!g_matched.empty()) {
    const std::wstring counter = std::to_wstring(g_selected + 1) + L"/" +
                                 std::to_wstring(g_matched.size());
    ::DrawTextW(mem, counter.c_str(), static_cast<int>(counter.size()), &hint,
                DT_SINGLELINE | DT_VCENTER | DT_RIGHT | DT_NOPREFIX);
  }
  ::SelectObject(mem, old_font);

  // 外框：深色底浮在深色視窗上時，沒有這條線就看不出邊界。
  // 有鍵盤焦點時換成品牌橘並加粗，沒焦點就退回灰線。
  const int bw = g_focused ? std::max(1, Scale(2)) : 1;
  HPEN pen = ::CreatePen(PS_SOLID, bw, g_focused ? kAccentDim : kBorder);
  HGDIOBJ old_pen = ::SelectObject(mem, pen);
  HGDIOBJ old_brush = ::SelectObject(mem, ::GetStockObject(NULL_BRUSH));
  // 筆畫是以路徑為中心畫的，內縮半個筆寬才不會有一半被視窗區域切掉
  ::RoundRect(mem, bw / 2, bw / 2, rc.right - bw / 2, rc.bottom - bw / 2,
              Scale(kRadius), Scale(kRadius));
  ::SelectObject(mem, old_brush);
  ::SelectObject(mem, old_pen);
  ::DeleteObject(pen);

  ::BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
  ::SelectObject(mem, old_bmp);
  ::DeleteObject(bmp);
  ::DeleteDC(mem);
  ::EndPaint(hwnd, &ps);
}

void Close() {
  if (!g_hwnd) return;
  ::KillTimer(g_hwnd, kWatchdogTimerId);
  g_watch_target = false;
  g_closing = true;
  ::ShowWindow(g_hwnd, SW_HIDE);
  g_closing = false;
  ShowCursorAgain();
}

void Cancel(const char* reason) {
  if (!g_hwnd || !::IsWindowVisible(g_hwnd)) return;
  Close();
  if (g_on_cancel) g_on_cancel(reason);
}

void Pick() {
  if (g_matched.empty()) return;
  const int index = g_matched[g_selected];
  // 先收起視窗再回報：焦點要先離開這裡，Dart 端接著才貼得回原本的視窗。
  Close();
  if (g_on_pick) g_on_pick(index);
}

void MoveSelection(int delta) {
  HideCursorForKeyboard();
  if (g_matched.empty()) return;
  const int last = static_cast<int>(g_matched.size()) - 1;
  g_selected = std::clamp(g_selected + delta, 0, last);
  EnsureSelectionVisible();
  ::InvalidateRect(g_hwnd, nullptr, FALSE);
}

// 滑鼠 y 座標落在哪一筆（g_matched 裡的位置）。不在清單上回 -1。
int RowAt(int y) {
  const int filter_h = Scale(kFilterHeight);
  const int row_h = Scale(kRowHeight);
  if (y < filter_h) return -1;
  const int i = (y - filter_h) / row_h;
  if (i < 0 || i >= VisibleRows()) return -1;
  const int pos = g_scroll + i;
  return pos < static_cast<int>(g_matched.size()) ? pos : -1;
}

void ForceForeground(HWND hwnd);

LRESULT CALLBACK PickerProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  switch (msg) {
    case WM_PAINT:
      Paint(hwnd);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_SETCURSOR:
      // 鍵盤操作中就不畫游標。這個訊息只在滑鼠事件時來，所以按鍵當下還要另外
      // 呼叫 SetCursor(nullptr)（見 HideCursorForKeyboard）。
      if (g_hide_cursor && LOWORD(lparam) == HTCLIENT) {
        ::SetCursor(nullptr);
        return TRUE;
      }
      break;
    case WM_NCHITTEST: {
      // 上面的關鍵字列與下面的提示列當作標題列，按住可以把整個浮窗拖走；
      // 中間的清單維持可點選。
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ::ScreenToClient(hwnd, &pt);
      const int filter_h = Scale(kFilterHeight);
      const int hint_top = filter_h + VisibleRows() * Scale(kRowHeight);
      if (pt.y < filter_h || pt.y >= hint_top) return HTCAPTION;
      return HTCLIENT;
    }
    case WM_NCLBUTTONDBLCLK:
      // WS_POPUP 沒有最大化這回事，雙擊「標題列」什麼都不要做
      return 0;
    case WM_KEYDOWN:
      switch (wparam) {
        case VK_ESCAPE:
          Cancel("esc");
          return 0;
        case VK_RETURN:
          Pick();
          return 0;
        case VK_UP:
          MoveSelection(-1);
          return 0;
        case VK_DOWN:
          MoveSelection(1);
          return 0;
        case VK_PRIOR:
          MoveSelection(-VisibleRows());
          return 0;
        case VK_NEXT:
          MoveSelection(VisibleRows());
          return 0;
        case VK_BACK:
          HideCursorForKeyboard();
          if (!g_filter.empty()) {
            g_filter.pop_back();
            ApplyFilter();
            Refresh();
          }
          return 0;
        default:
          break;
      }
      break;
    case WM_CHAR: {
      // 退格與 Enter 都會另外送 WM_CHAR，那兩個在 WM_KEYDOWN 處理過了。
      const wchar_t ch = static_cast<wchar_t>(wparam);
      if (ch >= L' ' && ch != 0x7F) {
        HideCursorForKeyboard();
        g_filter.push_back(ch);
        ApplyFilter();
        Refresh();
      }
      return 0;
    }
    case WM_MOUSEMOVE: {
      // 視窗因為過濾而改變高度時，Windows 會補送一則 WM_MOUSEMOVE，游標其實
      // 沒動。位置真的變了才算使用者在用滑鼠。
      POINT now = {};
      ::GetCursorPos(&now);
      if (now.x == g_last_cursor_pos.x && now.y == g_last_cursor_pos.y) return 0;
      g_last_cursor_pos = now;
      ShowCursorAgain();
      const int pos = RowAt(GET_Y_LPARAM(lparam));
      if (pos >= 0 && pos != g_selected) {
        g_selected = pos;
        ::InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSEWHEEL: {
      const int delta = GET_WHEEL_DELTA_WPARAM(wparam) > 0 ? -1 : 1;
      MoveSelection(delta);
      return 0;
    }
    case WM_LBUTTONDOWN: {
      const int pos = RowAt(GET_Y_LPARAM(lparam));
      if (pos >= 0) {
        g_selected = pos;
        Pick();
      }
      return 0;
    }
    case WM_TIMER:
      // 原本要貼上的視窗或輸入框不見了就收掉自己
      if (wparam == kWatchdogTimerId && g_watch_target && g_target_alive &&
          !g_target_alive()) {
        Cancel("target-gone");
      }
      return 0;
    case WM_KILLFOCUS:
      // 丟掉焦點不收浮窗，只把外框轉灰 —— 使用者要一邊看原本的工作畫面一邊
      // 挑詞。收起的方式剩三種：Esc、選一筆、再按一次熱鍵。
      g_focused = false;
      ::InvalidateRect(hwnd, nullptr, FALSE);
      if (g_closing) return 0;
      // 剛開的那一瞬間丟掉焦點多半是前景權限的競爭，不是使用者點走了，再搶一次。
      if (!g_settle_retried && ::GetTickCount64() - g_shown_at < kSettleMs) {
        g_settle_retried = true;
        ForceForeground(hwnd);
      }
      return 0;
    case WM_SETFOCUS:
      g_focused = true;
      ::InvalidateRect(hwnd, nullptr, FALSE);
      MoveCompositionWindow();
      return 0;
    case WM_DPICHANGED: {
      // 浮窗被拖到另一個縮放比例的螢幕。這裡連寬度一起重算 —— Layout() 只動
      // 高度（它要保住使用者拖出來的位置），寬度留著就會變成大字塞小框。
      SetDpi(HIWORD(wparam));
      const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
      const int w = Scale(kWidth);
      const int h = WindowHeight();
      ::SetWindowPos(hwnd, HWND_TOPMOST, suggested->left, suggested->top, w, h,
                     SWP_NOACTIVATE | SWP_NOZORDER);
      ::SetWindowRgn(hwnd,
                     ::CreateRoundRectRgn(0, 0, w + 1, h + 1, Scale(kRadius),
                                          Scale(kRadius)),
                     TRUE);
      ::InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    default:
      break;
  }
  return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}

void EnsureWindow() {
  if (g_hwnd) return;

  g_arrow = ::LoadCursorW(nullptr, IDC_ARROW);

  WNDCLASSW wc = {};
  wc.lpfnWndProc = PickerProc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = g_arrow;
  ::RegisterClassW(&wc);

  // 這個視窗要收鍵盤，所以**不能**加 WS_EX_NOACTIVATE（錄音藥丸剛好相反）。
  // WS_EX_TOOLWINDOW 讓它不出現在工作列與 Alt+Tab。
  g_hwnd = ::CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kClassName, L"",
                             WS_POPUP, 0, 0, 10, 10, nullptr, nullptr,
                             ::GetModuleHandleW(nullptr), nullptr);
  if (g_hwnd) g_dpi = ::GetDpiForWindow(g_hwnd);
}

// 把自己拉到前景。
//
// notes: 熱鍵按下時 Windows 本來就會給我們前景權限，SetForegroundWindow 多半直接
// 成功；但 Dart 端繞了一圈才呼叫到這裡，權限有可能已經過期。附掛到當下前景執行緒
// 的輸入佇列是 channel_handler 的 FocusPasteTarget 用了同樣理由的做法。
void ForceForeground(HWND hwnd) {
  HWND fg = ::GetForegroundWindow();
  if (fg == hwnd) {
    ::SetFocus(hwnd);
    return;
  }
  const DWORD self = ::GetCurrentThreadId();
  const DWORD fg_thread = fg ? ::GetWindowThreadProcessId(fg, nullptr) : 0;
  const BOOL attached =
      fg_thread && fg_thread != self && ::AttachThreadInput(self, fg_thread, TRUE);
  ::SetForegroundWindow(hwnd);
  ::SetActiveWindow(hwnd);
  ::SetFocus(hwnd);
  if (attached) ::AttachThreadInput(self, fg_thread, FALSE);
}

// 使用者的插入點在螢幕上的位置。拿得到回 true，[caret] 是螢幕座標。
//
// 前景視窗此刻還是使用者正在打字的地方（浮窗還沒出現），所以問它的 UI 執行緒。
// GetGUIThreadInfo 的 rcCaret 是相對 hwndCaret 的 client 座標。
//
// notes: 只有用系統插入點的程式問得到（EmEditor、記事本、Office）。Chrome、
// VS Code 這類自己畫游標的拿不到 rcCaret，退而用有焦點的那個控制項的左上角；
// 兩個都沒有就回 false，由呼叫端改用螢幕上三分之一的老位置。
bool CaretRectOnScreen(RECT* caret) {
  HWND fg = ::GetForegroundWindow();
  if (!fg) return false;
  GUITHREADINFO gui = {};
  gui.cbSize = sizeof(gui);
  if (!::GetGUIThreadInfo(::GetWindowThreadProcessId(fg, nullptr), &gui)) {
    return false;
  }

  if (gui.hwndCaret && ::IsWindow(gui.hwndCaret) &&
      (gui.rcCaret.right > gui.rcCaret.left ||
       gui.rcCaret.bottom > gui.rcCaret.top)) {
    POINT tl = {gui.rcCaret.left, gui.rcCaret.top};
    POINT br = {gui.rcCaret.right, gui.rcCaret.bottom};
    ::ClientToScreen(gui.hwndCaret, &tl);
    ::ClientToScreen(gui.hwndCaret, &br);
    *caret = {tl.x, tl.y, br.x, br.y};
    return true;
  }

  HWND anchor = gui.hwndFocus ? gui.hwndFocus : fg;
  if (!::IsWindow(anchor)) return false;
  RECT wr = {};
  if (!::GetWindowRect(anchor, &wr)) return false;
  // 控制項可能整片都是編輯區，取左上角當錨點就好
  *caret = {wr.left, wr.top, wr.left, wr.top};
  return true;
}

std::string Describe(const char* prefix) {
  char buf[256] = {};
  RECT rc = {};
  if (g_hwnd) ::GetWindowRect(g_hwnd, &rc);
  sprintf_s(buf, "%s visible=%d foreground=%d dpi=%u pos=(%ld,%ld) size=%ldx%ld",
            prefix, g_hwnd && ::IsWindowVisible(g_hwnd) ? 1 : 0,
            g_hwnd && ::GetForegroundWindow() == g_hwnd ? 1 : 0, g_dpi, rc.left,
            rc.top, rc.right - rc.left, rc.bottom - rc.top);
  return buf;
}

}  // namespace

void PickerPrepare() {
  EnsureWindow();
  EnsureFonts();
}

std::string PickerShow(const std::vector<std::string>& items) {
  // 現在的前景視窗＝使用者正在打字的地方。錨點與螢幕都要在搶焦點之前取得。
  RECT caret = {};
  const bool has_caret = CaretRectOnScreen(&caret);
  HMONITOR monitor =
      has_caret ? ::MonitorFromPoint(POINT{caret.left, caret.top},
                                     MONITOR_DEFAULTTONEAREST)
                : ::MonitorFromWindow(::GetForegroundWindow(),
                                      MONITOR_DEFAULTTOPRIMARY);

  EnsureWindow();
  if (!g_hwnd) return "常用詞彙：視窗建立失敗";
  // notes: 一定要在算寬高之前問目標螢幕的 DPI。g_dpi 是建視窗那一刻抓的，
  // 那時視窗還在主螢幕；等 SetWindowPos 把它擺到高 DPI 螢幕才收到
  // WM_DPICHANGED 就太遲了 —— 第一次叫出來會變成大字塞在小框裡。
  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (SUCCEEDED(::GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    SetDpi(dpi_x);
  }
  EnsureFonts();

  g_items.clear();
  g_folded.clear();
  g_items.reserve(items.size());
  g_folded.reserve(items.size());
  for (const auto& item : items) {
    g_items.push_back(Widen(item));
    g_folded.push_back(Fold(g_items.back()));
  }
  g_filter.clear();
  ApplyFilter();
  g_hide_cursor = false;
  ::GetCursorPos(&g_last_cursor_pos);

  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  RECT work = {};
  if (::GetMonitorInfoW(monitor, &mi)) {
    work = mi.rcWork;
  } else {
    ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  }

  const int w = Scale(kWidth);
  const int h = WindowHeight();
  const int gap = Scale(kCaretGap);
  int x;
  int y;
  if (has_caret) {
    // 插入點的正下方，貼齊它的左緣；下面塞不下就翻到上面去
    x = caret.left;
    y = caret.bottom + gap;
    if (y + h > work.bottom) y = caret.top - gap - h;
  } else {
    x = work.left + (work.right - work.left - w) / 2;
    y = work.top + (work.bottom - work.top - h) / 3;
  }
  x = std::clamp(x, static_cast<int>(work.left),
                 std::max(static_cast<int>(work.left), static_cast<int>(work.right) - w));
  y = std::clamp(y, static_cast<int>(work.top),
                 std::max(static_cast<int>(work.top), static_cast<int>(work.bottom) - h));

  ::SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE);
  ::SetWindowRgn(
      g_hwnd,
      ::CreateRoundRectRgn(0, 0, w + 1, h + 1, Scale(kRadius), Scale(kRadius)),
      TRUE);
  g_shown_at = ::GetTickCount64();
  g_settle_retried = false;
  g_focused = false;
  g_watch_target = g_target_alive && g_target_alive();
  if (g_watch_target) {
    ::SetTimer(g_hwnd, kWatchdogTimerId, kWatchdogMs, nullptr);
  }
  ::ShowWindow(g_hwnd, SW_SHOW);
  ForceForeground(g_hwnd);
  MoveCompositionWindow();
  ::InvalidateRect(g_hwnd, nullptr, FALSE);

  return Describe(has_caret ? "常用詞彙：對齊插入點" : "常用詞彙：找不到插入點，置中");
}

void PickerHide() {
  Close();
}

bool PickerRefocusIfUnfocused() {
  if (!g_hwnd || !::IsWindowVisible(g_hwnd) || g_focused) return false;
  ForceForeground(g_hwnd);
  // 這段期間使用者可能已經換到別的視窗打字，看門的對象跟著換
  g_watch_target = g_target_alive && g_target_alive();
  if (g_watch_target) {
    ::SetTimer(g_hwnd, kWatchdogTimerId, kWatchdogMs, nullptr);
  }
  return true;
}

void PickerSetCallbacks(void (*on_pick)(int index),
                        void (*on_cancel)(const char* reason)) {
  g_on_pick = on_pick;
  g_on_cancel = on_cancel;
}

void PickerSetTargetAliveCheck(bool (*alive)()) {
  g_target_alive = alive;
}
