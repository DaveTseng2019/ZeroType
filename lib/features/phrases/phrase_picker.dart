import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/paste_service.dart';
import 'package:zero_type/features/log/log_controller.dart';
import 'package:zero_type/features/phrases/phrase_controller.dart';

final phrasePickerProvider = Provider<PhrasePicker>((ref) => PhrasePicker(ref));

/// 常用詞彙選擇器：按熱鍵叫出原生浮窗（windows/runner/picker_window.cpp），
/// 挑一句就貼到剛剛在打字的地方 —— 同一句話不用再講第二次。
///
/// 走的是跟語音辨識結果一樣的貼上路徑：先記住目標視窗，選好之後
/// [pasteText] 負責切焦點、送 Ctrl+V、還原剪貼簿。
class PhrasePicker {
  PhrasePicker(this._ref) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final Ref _ref;

  static const _channel = MethodChannel('com.zerotype.app/picker');
  static const _keyboardChannel = MethodChannel('com.zerotype.app/keyboard');

  /// 開著的那一份清單。原生端回報的是索引，要靠這份對回文字。
  List<String> _shown = const [];
  bool _open = false;

  LogController get _log => _ref.read(logControllerProvider.notifier);

  /// 熱鍵的進入點，同一顆鍵有三種結果：
  ///
  /// - 沒開 → 叫出來
  /// - 開著但焦點在別的視窗（外框是灰的）→ 把焦點要回來，繼續用同一份清單
  /// - 開著而且正拿著焦點 → 收起來
  ///
  /// 中間那一種是必要的：浮窗丟了焦點不會自己關，而沒有焦點時 Esc 送不進去，
  /// 少了這條路就只能用滑鼠點它。
  Future<void> open() async {
    // 錄音中不讓選擇器插隊：它會搶走焦點，等一下辨識結果就貼不回原本的視窗。
    if (_ref.read(zeroTypeControllerProvider).isActive) {
      _log.info('錄音中，先結束或取消再叫常用詞彙');
      return;
    }

    // 趁焦點還在使用者剛剛打字的地方，先把貼上目標記下來。要在浮窗出現或搶回
    // 焦點之前，不然記到的就是浮窗自己了。取回焦點時也要重記 —— 這段期間他
    // 可能已經換到另一個視窗打字，該貼的是那裡。
    try {
      await _keyboardChannel.invokeMethod<void>('rememberPasteTarget');
    } catch (_) {}

    if (_open) {
      final refocused =
          await _channel.invokeMethod<bool>('refocus') ?? false;
      if (!refocused) await close();
      return;
    }

    final phrases = await _ref.read(phraseControllerProvider.future);
    _shown = phrases;
    _open = true;
    try {
      // 原生端回的是診斷字串：有沒有真的顯示、有沒有拿到前景、開在哪個座標。
      // 浮窗沒出現時這一行是唯一的線索（見紀錄頁，需開偵錯）。
      final report = await _channel.invokeMethod<String>('show', {
        'items': phrases,
      });
      _log.debug(report ?? '常用詞彙：原生端沒有回報');
      // 浮窗開在插入點旁邊，眼睛不一定在那裡；提示音是它出來了的第二個訊號
      unawaited(soundService.playPhrasePickerSound());
    } catch (e) {
      _open = false;
      _log.error('叫不出常用詞彙選擇器：$e');
    }
  }

  Future<void> close() async {
    if (!_open) return;
    _open = false;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  Future<void> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'picked':
        _open = false;
        final index = call.arguments as int;
        if (index < 0 || index >= _shown.length) return;
        await _paste(_shown[index]);
      case 'cancelled':
        _open = false;
        if (call.arguments == 'target-gone') {
          _log.info('原本要貼上的視窗已經不在，常用詞彙收起');
        }
    }
  }

  Future<void> _paste(String text) async {
    final outcome = await pasteText(text);
    _log.debug('貼上：${outcome.target}');
    if (outcome.pasted) {
      _log.info(text);
    } else {
      _log.error('沒貼上（焦點切不回原本的視窗，或按熱鍵時焦點在 ZeroType 自己'
          '身上）；文字已複製到剪貼簿');
      // 貼上失敗時畫面上什麼都不會發生，沒有聲音就只能等使用者自己發現
      unawaited(soundService.playFailedSound());
    }
  }
}
