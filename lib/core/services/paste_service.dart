import 'dart:async';

import 'package:flutter/services.dart';

const _keyboardChannel = MethodChannel('com.zerotype.app/keyboard');

class PasteOutcome {
  const PasteOutcome({required this.pasted, required this.target});

  /// 是否真的送出了貼上。false 代表焦點切不回原本的視窗，文字只留在剪貼簿。
  final bool pasted;

  /// 診斷用的目標描述（頂層視窗 + 真正收到按鍵的子控制項），寫進紀錄頁用。
  final String target;
}

/// 把 [text] 貼到「熱鍵按下那一刻」記下的那個視窗（見原生端的
/// RememberPasteTarget / FocusPasteTarget）。
///
/// 語音辨識結果與常用詞彙走的是同一條路，唯一的差別是 [pressEnter]。
Future<PasteOutcome> pasteText(String text, {bool pressEnter = false}) async {
  // 貼上是拿剪貼簿當中介，會蓋掉使用者原本複製的東西。這裡在覆蓋的前一刻
  // 記下來，貼完再還原。取「覆蓋前」而不是「熱鍵按下時」—— 中間那幾秒使用者
  // 還是可能複製別的東西，要還原的是最近一次。
  final savedClipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  await Clipboard.setData(ClipboardData(text: text));
  await Future.delayed(const Duration(milliseconds: 150));

  final pasted =
      await _keyboardChannel.invokeMethod<bool>('simulatePaste', {
            'pressEnter': pressEnter,
          }) ??
          false;
  // 貼上之後才問，這樣 focus= 拿到的是按鍵真正送達那一刻的狀態
  final target =
      await _keyboardChannel.invokeMethod<String>('describePasteTarget') ??
          '(未知)';

  // 沒貼上時不還原 —— 那時剪貼簿裡的文字是使用者唯一的救援手段
  if (pasted && savedClipboard != null && savedClipboard.isNotEmpty) {
    unawaited(_restoreClipboard(savedClipboard, text));
  }

  return PasteOutcome(pasted: pasted, target: target);
}

/// 把剪貼簿還原成貼上前的 [saved]。
///
/// notes: 只顧文字。Flutter 的 Clipboard 只讀得到 text/plain，原本放的是圖片或
/// 檔案就救不回來（那時 [saved] 是 null，我們乾脆不還原，把貼上的文字留著）。
/// 要做到全格式得在 windows/runner 用 EnumClipboardFormats 逐格式複製一份。
///
/// notes: 固定等 500ms。Ctrl+V 是 SendInput 送出去的，目標視窗什麼時候讀剪貼簿
/// 我們並不知道；還原得太早，貼進去的會是舊內容。慢的目標踩到就把這個值調大。
Future<void> _restoreClipboard(String saved, String pastedText) async {
  await Future.delayed(const Duration(milliseconds: 500));
  // 這 500ms 之間使用者自己複製了別的東西就別蓋掉他。
  // VS 內建終端機「有選取範圍時右鍵是複製」那個情況也會落在這裡。
  final current = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  if (current != pastedText) return;
  await Clipboard.setData(ClipboardData(text: saved));
}
