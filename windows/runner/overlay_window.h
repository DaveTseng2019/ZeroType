#ifndef RUNNER_OVERLAY_WINDOW_H_
#define RUNNER_OVERLAY_WINDOW_H_

#include <string>

// 錄音提示藥丸：一個置頂、不搶焦點的小視窗，浮在工作列正上方。
// 主視窗被蓋住或縮到系統匣時，這是唯一看得到的錄音狀態。
void OverlayShow(const std::string& status, const std::string& message);
void OverlayHide();
void OverlaySetAmplitude(double amplitude);

// 按下藥丸右邊的 ✕ 時呼叫（取消這次錄音）。
void OverlaySetCancelCallback(void (*callback)());

#endif  // RUNNER_OVERLAY_WINDOW_H_
