#ifndef RUNNER_PICKER_WINDOW_H_
#define RUNNER_PICKER_WINDOW_H_

#include <string>
#include <vector>

// 常用詞彙選擇器：按熱鍵叫出來的置頂小浮窗。打字過濾、↑↓ 選、Enter 送出、
// Esc 或再按一次熱鍵收起，拖曳上下兩列可以搬到不擋事的地方。
//
// 點到別的視窗不會收掉它，只是外框從橘轉灰（灰＝打字不會進來）。
//
// 跟錄音藥丸（overlay_window）最大的不同是這個視窗**要搶焦點** —— 沒有焦點就
// 收不到鍵盤。貼上目標必須在呼叫 PickerShow 之前就記好（見 channel_handler 的
// RememberPasteTarget）。

// 先把視窗建好。第一次叫出來時才臨時建立的話，建視窗那幾毫秒剛好卡在
// 「熱鍵給的前景權限」的空窗期，實測第一次按會看不到浮窗。
void PickerPrepare();

// 回傳診斷字串（是否真的顯示／拿到前景／開在哪），呼叫端寫進紀錄頁。
std::string PickerShow(const std::vector<std::string>& items);

void PickerHide();

// 浮窗開著、但焦點被別的視窗拿走時，把焦點搶回來並回 true。
// 已經有焦點（或根本沒開著）回 false —— 呼叫端那時該做的是收起它。
bool PickerRefocusIfUnfocused();

// on_pick 的參數是 items 裡的索引（過濾之後仍對得回原本那一筆）。
// on_cancel 的 reason 說明是怎麼收掉的（目前只有 esc）。
void PickerSetCallbacks(void (*on_pick)(int index),
                        void (*on_cancel)(const char* reason));

// 貼上目標（熱鍵按下時記到的那個視窗／輸入框）還在不在。浮窗顯示期間每
// kWatchdogMs 問一次，回 false 就自己收掉 —— 沒地方可貼了，留著只是擋路。
void PickerSetTargetAliveCheck(bool (*alive)());

#endif  // RUNNER_PICKER_WINDOW_H_
