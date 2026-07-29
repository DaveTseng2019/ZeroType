# Zero Type

> 一個 Vibe Coding 出來的繁體中文語音輸入工具。

市面上大多數語音辨識軟體對繁體中文（特別是台灣人慣用的晶晶體中英混用語境）支援度有限，且背後處理邏輯不透明。ZeroType 透過直接串接外部 LLM API，打造一套開放、透明、可自訂的語音辨識輸入系統。

**你只需要自備 API Key，其餘一切開源。**

---

## ✨ 功能特色

### 🎙️ 全局快捷鍵錄音
- 自訂全局快捷鍵（預設 `⌥ Option + Space`，Windows 顯示為 `Alt + Space`），在任何應用程式中觸發錄音
- 錄音中顯示浮動音波 Overlay，提供即時視覺回饋
- 按下 `Esc` 或點擊取消按鈕可中止錄音

### 🧠 AI 驅動的語音辨識
- 支援 **OpenAI**（`gpt-4o-transcribe`）、**Google Gemini**（`gemini-*`）與 **OpenRouter**（一把 Key 通吃多家模型）三種語音辨識後端
- OpenRouter 模型清單由官方 API 線上取得（只列支援音訊輸入的模型），下拉選單直接顯示每百萬 token 費率並標示「推薦」；離線時退回內建清單
- 免費模型（`:free`）排在清單最後並附可用性警告，僅建議測試用
- 辨識完成後，結果自動貼至游標所在位置（模擬 `⌘V` / `Ctrl+V`）
- 支援自訂 API Endpoint（可使用 OpenAI-compatible 的第三方服務）

### 🇹🇼 針對繁體中文深度優化的提示詞
內建的轉錄提示詞針對台灣使用情境做了以下優化：

| 功能 | 說明 |
|------|------|
| **晶晶體支援** | 中英文混用語句自然處理，英文單字保留原文不翻譯、不中文化 |
| **智慧過濾廢詞** | 自動剔除「嗯」、「啊」、「呃」、「喔」、「那個」、「然後」、「基本上」等停頓填充詞 |
| **口誤修正偵測** | 偵測到「不對」、「應該是」、「我說錯了」、「才對」等字眼，自動捨棄前段錯誤並保留修正內容 |
| **智慧標點** | 根據語意自動補上逗號、句號，不需手動停頓 |
| **自動條列輸出** | 偵測到序數（第一、第二）或連接詞（首先、然後、最後）時，自動轉為 `1. 2. 3.` 或 `- ` 格式並換行 |
| **格式口語還原** | 說出「大寫」、「小寫」、「空格」、「底線」、「驚嘆號」等，自動還原為對應字元 |
| **空白錄音保護** | 錄音檔為空時直接返回空字串，嚴禁自行幻想內容 |

### 📖 自訂字典
- 可設定個人化的專有名詞字典（人名、品牌、術語）
- 辨識時優先採用字典用字，確保拼寫正確

### ⚙️ 設定頁面
- 深色 / 淺色模式切換
- 開機自動啟動；開啟後可再勾選「啟動時縮小至系統匣」，開機不跳視窗
- 快捷鍵自訂（支援任意組合鍵，按鍵標籤依平台顯示 `⌘/⌥` 或 `Win/Alt`）
- 錄音開始 / 結束提示音可挑選系統內建音效（macOS 與 Windows 各自的音效清單）
- 麥克風權限與輔助使用權限狀態即時顯示

### 🪟 Windows 支援
- 自訂標題列：拖曳移動視窗、最小化，關閉鍵等於縮到系統匣（程式繼續在背景待命）
- 系統匣圖示可隨時叫回視窗或結束程式

---

## 🔧 使用前準備

### 系統需求
- macOS 11.0+ 或 Windows 10/11
- Flutter 3.x（如需自行 build）

### 必要系統授權
1. **麥克風** — 錄音所需
2. **輔助使用（Accessibility，僅 macOS）** — 模擬鍵盤輸入（`⌘V` 貼上）所需

### API Key
前往以下任一服務申請 API Key：
- [OpenAI](https://platform.openai.com/api-keys)（支援 Transcribe 語音辨識）
- [Google AI Studio](https://aistudio.google.com/app/apikey)（支援 Gemini 多模態）
- [OpenRouter](https://openrouter.ai/keys)（一把 Key 使用 Gemini / GPT Audio 等多家音訊模型）

---

## 🚀 執行方式

### 方法一：直接下載（推薦）

1. 前往 [Releases](https://github.com/nick1ee/ZeroType/releases) 頁面下載最新版本
2. macOS：開啟 `.dmg` 並將 **ZeroType.app** 拖入 Applications 資料夾；Windows：直接執行 `zero_type.exe`
3. 首次執行時，依照提示授予以下權限：
   - **麥克風** — 語音輸入所需
   - **輔助使用（Accessibility，macOS）** — 模擬鍵盤貼上所需
4. 在 App 內的「模型設定」填入你的 API Key，即可開始使用

### 方法二：從原始碼執行（進階）

**開發模式**

```bash
git clone https://github.com/nick1ee/ZeroType.git
cd ZeroType
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 產生 freezed / riverpod / auto_route 程式碼
flutter run -d macos      
# Windows 則用 -d windows
```

**正式版建置**

```bash
flutter build macos --release
# 產物在 build/macos/Build/Products/Release/ZeroType.app

flutter build windows --release
# 產物在 build\windows\x64\runner\Release\zero_type.exe
```

---

## 🔄 更新方式

**一般使用者**：到 [Releases](https://github.com/nick1ee/ZeroType/releases) 下載新版，直接覆蓋舊的 `.app` / `.exe` 即可。設定與歷史紀錄存放在使用者資料目錄，覆蓋安裝不會遺失。

**從原始碼更新**

```bash
git pull
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d macos      # 或重新 build release
```

> 注意：只要 `pubspec.yaml` 或任何 `@freezed` / `@riverpod` / route 相關檔案有變動，就必須重跑 `build_runner`，否則會編譯失敗。

---

## 🌍 語言支援 & 貢獻 (Localization & Contribution)

- **地區限制**：目前此 App 主要針對 **台灣使用情境** 設計，輸出內容以 **繁體中文** 與 **英文** 為主。未來是否有增加其他語言支援？若「有緣」的話之後再行考慮。
- **回報問題與協助**：如果你在使用上發現任何問題，或是單純想提供改進建議，歡迎直接發 **Issue** 或發 **Pull Request** 給我。只要我有看到訊息，第一時間就會來幫大家處理與解決。

---

## 📜 版本更新紀錄 (Release Notes)

### [v1.0.3] - 當前版本
- **Windows 支援** 🪟
  - 可在 Windows 建置與執行：錄音、系統匣圖示、提示音效全部到位。
  - 自訂標題列支援拖曳移動與最小化，關閉鍵改為縮到系統匣。
  - 快捷鍵設定的按鍵標籤依平台顯示（`Win` / `Alt` 取代 `⌘` / `⌥`）。
  - 「開機自動啟動」新增「啟動時縮小至系統匣」選項，且每次啟動會重新寫入登錄檔路徑，移動執行檔後不會失效。
- **新增 OpenRouter 供應商** 🔀
  - 一把 API Key 即可使用 Gemini、GPT Audio 等多家音訊模型。
  - 模型清單改由 OpenRouter API 線上取得（僅列支援音訊輸入的模型），含即時費率；離線時退回內建清單。
  - 下拉選單顯示每百萬 token 輸入／輸出價格，並依品質級距與價位自動標示「推薦」。
  - 免費模型移到清單最後並標註可用性警告。

### [v1.0.2]
- **新增歷史紀錄頁** 🎨
  - 提供歷史產生逐字稿的紀錄語音檔，並可提供檢視。
  - 新增總轉寫次數與總花費（USD）的持久化累計統計。
- **最長錄音自訂** ⏱️
  - 設定中新增「最長錄音時間」選項，範圍 1-5 分鐘，預設為 1 分鐘。
- **編輯器優化** ✍️
  - 提示詞編輯框寬度與高度現在會隨視窗大小自適應，不再固定長度。

### [v1.0.1]
- **錄音音效支援** 🔊 — 可設定錄音開始與結束提示音。
- **功能修復** 🐛 — 修正 macOS 上視窗關閉後無法再次開啟的問題。
- **提示詞優化** 📝 — 進一步精簡轉錄用的系統 Prompt。

---

## 📝 License

MIT — 自由使用、修改、散布，唯需自備 API Key。
