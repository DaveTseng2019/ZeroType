# Zero Type

> **這是 fork。** 原作 [nick1ee/ZeroType](https://github.com/nick1ee/ZeroType) 自 2026-03 起未再更新，PR 也無人審查，故另行維護。以下連結皆以本 repo 為準。
>
> **Windows-only**：目前維護者只有 Windows 環境，`macos/` 平台程式碼已於 2026-08 移除（git 歷史可尋回），Release 只提供 Windows build。需要 macOS 支援請回頭參考原作 repo。

一個繁體中文語音輸入工具。按下快捷鍵講話，文字直接貼到游標所在的地方。

辨識可以走雲端 API，也可以完全在自己的 GPU 上跑。

---

## ✨ 功能特色

- **全局快捷鍵錄音** — 在任何程式裡按 `Alt + Z` 開始，再按一次結束。另有精簡模式（`Alt + X`）：講完安靜 1.5 秒自動結束並補 `Enter` 送出。錄音中有浮動音波提示，`Esc` 取消。
- **多種辨識後端** — OpenAI、Google Gemini、OpenRouter（一把 Key 通吃多家模型），以及**本機**辨識：不需要 API Key、不產生費用，音檔與文字都不出這台電腦。
- **只錄到噪音就不送辨識** — 用動態範圍（最大聲的一成 ÷ 最安靜的一成）判斷有沒有人在講話。沒人聲的錄音送給 AI，它不會回「沒聽到」，而是憑空編一整段內容出來。
- **轉錄，不代寫** — 只做最小限度的整理：剔除停頓詞、自動標點、中英混用保留原文不翻譯。規則沒明講要改的一律照原話輸出。命令詞只有「更正」與「換行」兩個。
- **自訂字典** — 人名、品牌、術語寫進字典，以拼寫校正的方式套用（發音相同且字數相同才替換），不會被憑空插入輸出。
- **常用詞彙選擇器** — 同一句話不必再講第二次：按 `Alt + C` 叫出浮窗，打字過濾、`Enter` 直接貼上。
- **設定** — 深色／淺色、開機自動啟動、快捷鍵自訂、提示音、辨識紀錄與費用統計。關閉鍵等於縮到系統匣，程式在背景待命。

---

## 🔧 使用前準備

- **系統**：Windows 10/11。自行 build 需要 Flutter 3.x。
- **權限**：麥克風。
- **API Key**（用雲端辨識才需要）：[OpenAI](https://platform.openai.com/api-keys)、[Google AI Studio](https://aistudio.google.com/app/apikey) 或 [OpenRouter](https://openrouter.ai/keys)。
- **本機辨識**：需要另外安裝辨識端點與一張支援的顯示卡，程式裡「模型設定 → 本機」會給安裝說明。

---

## 🚀 執行方式

### 直接下載（推薦）

1. 到 [Releases](https://github.com/DaveTseng2019/ZeroType/releases) 下載最新版 zip
2. 解壓縮後執行 `zero_type.exe`（DLL 與 `data` 資料夾要留在同一層）
3. 依提示授予麥克風權限
4. 在「模型設定」選服務商並填 API Key

### 從原始碼執行

```bash
git clone https://github.com/DaveTseng2019/ZeroType.git
cd ZeroType
flutter pub get
flutter run -d windows            # 開發模式
flutter build windows --release   # 正式版
```

> 專案不使用任何程式碼產生器（無 build_runner），`pub get` 完直接跑。

---

## 🔄 更新方式

到 [Releases](https://github.com/DaveTseng2019/ZeroType/releases) 下載新版覆蓋舊的執行檔，或在 App 內「設定 → 關於」點「下載更新」。設定與歷史紀錄存在使用者資料目錄，覆蓋不會遺失。

每一版改了什麼，看 [Releases](https://github.com/DaveTseng2019/ZeroType/releases) 頁面。

---

## 🌍 語言支援 & 貢獻

- 主要針對**台灣使用情境**設計，輸出以繁體中文與英文為主。
- 有問題或建議歡迎在 [本 repo](https://github.com/DaveTseng2019/ZeroType) 發 Issue 或 Pull Request。
