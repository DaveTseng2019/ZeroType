import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/history/entities/transcription_record.dart';
import 'package:zero_type/features/history/presentation/controllers/history_controller.dart';
import 'package:zero_type/features/log/log_controller.dart';
import 'package:zero_type/features/model_config/presentation/controllers/model_config_controller.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';
import 'package:zero_type/features/dictionary/presentation/controllers/dictionary_controller.dart';

final zeroTypeControllerProvider =
    NotifierProvider<ZeroTypeController, ZeroTypeState>(ZeroTypeController.new);

class ZeroTypeController extends Notifier<ZeroTypeState> {
  late final RecordingService _recordingService;

  /// notes: 訊息寫進紀錄頁，不再用「overlay 顯示 2~3 秒」當 UI —— 那種延遲會把
  /// 流程整個卡住（錯誤要等 3 秒才回到閒置，期間熱鍵沒有反應），訊息也留不下來。
  LogController get _log => ref.read(logControllerProvider.notifier);
  bool _cancelled = false;
  DateTime? _recordingStartTime;
  Timer? _maxDurationTimer;

  /// 精簡模式：不用再按一次熱鍵停止（講完自動停），文字貼上後自動按 Enter 送出
  bool _quickMode = false;
  QuietGate? _quietGate;

  @override
  ZeroTypeState build() {
    _recordingService = RecordingService();
    ref.onDispose(() => _recordingService.dispose());

    // 低階鍵盤鉤子偵測到 Esc 時，原生端會呼叫這裡的 'cancel'
    // （見 windows/runner/channel_handler.cpp 的 LowLevelKeyboardProc）
    const controlChannel = MethodChannel('com.zerotype.app/control');
    controlChannel.setMethodCallHandler((call) async {
      if (call.method == 'cancel') {
        _log.info('已用 Esc 取消');
        await cancel();
      }
    });

    return const ZeroTypeState();
  }

  // notes: 攔 setter 而不是在各個轉換點呼叫 —— 系統匣圖示在視窗隱藏時是唯一的
  // 錄音提示，掛在 widget 的 listener 要等 frame，隱藏時不保證會跑。
  // Esc 取消熱鍵的「武裝」旗標也跟著這裡走同一個理由：回到 idle 的路徑不只
  // cancel() 一條（權限檢查失敗、逾時、辨識完成都會），漏掉任何一條會讓
  // 低階鍵盤鉤子一直保持在監看狀態。
  @override
  set state(ZeroTypeState value) {
    final was = stateOrNull?.status == ZeroTypeStatus.recording;
    final now = value.status == ZeroTypeStatus.recording;
    final wasActive = stateOrNull?.isActive ?? false;
    final nowActive = value.isActive;
    super.state = value;
    if (was != now) {
      unawaited(trayService.setRecording(now, quick: value.quick));
    }
    if (wasActive != nowActive) {
      const controlChannel = MethodChannel('com.zerotype.app/control');
      unawaited(controlChannel
          .invokeMethod<void>('setCancelHotkeyArmed', nowActive)
          .catchError((_) {}));
    }
  }

  Future<void> toggleRecording({bool quick = false}) async {
    print('[ZeroTypeController] Hotkey triggered! Current status: ${state.status}');
    if (state.status == ZeroTypeStatus.recording) {
      await _stopAndProcess();
    } else if (state.status == ZeroTypeStatus.idle) {
      await _startRecording(quick: quick);
    } else if (state.status == ZeroTypeStatus.cancelling) {
      return;
    } else {
      await cancel();
    }
  }

  Future<void> cancel() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _cancelled = true;
    if (state.status == ZeroTypeStatus.recording ||
        state.status == ZeroTypeStatus.warmingUp) {
      state = state.copyWith(status: ZeroTypeStatus.cancelling);
      unawaited(_showNativeOverlay('cancelling', '取消中'));
      await _recordingService.cancelRecording();
    }
    await soundService.playCancelSound();
    await soundService.resumeMusic();
    state = const ZeroTypeState();
    await _hideNativeOverlay();
  }

  Future<void> _startRecording({bool quick = false}) async {
    _cancelled = false;
    _quickMode = quick;
    _quietGate = quick ? QuietGate() : null;

    // 趁焦點還在使用者剛剛打字的地方，先把貼上目標記下來。
    // 要在任何 overlay／視窗操作之前，不然記到的就不是原本那個視窗了。
    const keyboardChannel = MethodChannel('com.zerotype.app/keyboard');
    try {
      await keyboardChannel.invokeMethod<void>('rememberPasteTarget');
    } catch (_) {} // macOS 端沒有這個方法，忽略

    final config = await ref.read(speechProviderControllerProvider.future);
    if (config.providerId == null || config.providerId!.isEmpty ||
        config.apiKey == null || config.apiKey!.isEmpty ||
        config.modelId == null || config.modelId!.isEmpty) {
      _log.error('請先完成語音辨識模型設定');
      await soundService.playCancelSound();
      state = const ZeroTypeState();
      await _hideNativeOverlay();
      return;
    }

    // [優化1] 同時檢查 accessibility 與麥克風權限
    const permissionChannel = MethodChannel('com.zerotype.app/permission');
    bool isAccessibilityOk = false;
    bool hasPermission = false;
    try {
      final results = await Future.wait([
        permissionChannel
            .invokeMethod<bool>('checkAccessibility')
            .then((v) => v ?? false)
            .catchError((_) => false),
        _recordingService.requestPermission().catchError((_) => false),
      ]);
      isAccessibilityOk = results[0] as bool;
      hasPermission = results[1] as bool;
    } catch (_) {}

    if (!ref.mounted || _cancelled) return;
    if (!isAccessibilityOk) {
      _log.error('請先授權輔助使用權限');
      await soundService.playCancelSound();
      state = const ZeroTypeState();
      await _hideNativeOverlay();
      return;
    }
    if (!hasPermission) {
      _log.error('請先授權麥克風權限');
      await soundService.playCancelSound();
      state = const ZeroTypeState();
      await _hideNativeOverlay();
      return;
    }

    // 開了等待麥克風就緒時，提示音改由 onCaptureStart 觸發 —— 那一刻才真的收得到聲音。
    // 提早播只會在藍牙切 HFP 的當下被吃掉，等於沒有提示。
    final warmupTimeout = Duration(
      milliseconds:
          appPrefs.getInt(AppConstants.recordWarmupMsKey) ?? 0,
    );

    // [優化2] 音效不阻塞錄音啟動。
    // 提示音一律由 onCaptureStart 觸發（不論有沒有開等待）—— 那一刻才真的收得到
    // 聲音，也才不會被藍牙切 HFP 的那一下吃掉。
    unawaited(soundService.pauseMusic());

    if (!ref.mounted || _cancelled) return;
    // 等待麥克風就緒時先進 warmingUp：圖示、提示都還不能說「錄音中」，
    // 因為這段收到的音訊會被 MicReadyGate 丟掉，使用者這時講話是白講。
    final warming = warmupTimeout > Duration.zero;
    state = state.copyWith(
      status: warming ? ZeroTypeStatus.warmingUp : ZeroTypeStatus.recording,
      quick: quick,
      amplitude: 0.0,
    );
    if (warming) {
      _armMaxDuration();
    } else {
      _beginRecording();
    }

    // [優化3] overlay 顯示與錄音初始化同步進行
    try {
      await Future.wait([
        _showNativeOverlay(
            'recording', '${warming ? '準備中' : '錄音中'}${_modeLabel(quick)}'),
        _recordingService.startRecording(
          deviceId: appPrefs
              .getString(AppConstants.inputDeviceIdKey),
          // 0 = 不過濾，也是預設值
          noiseGateStrength:
              appPrefs.getDouble(AppConstants.noiseGateStrengthKey) ?? 0,
          warmupTimeout: warmupTimeout,
          onCaptureStart: () {
            if (!ref.mounted || _cancelled) return;
            unawaited(soundService.playStartSound());
            if (state.status != ZeroTypeStatus.warmingUp) return;
            state = state.copyWith(status: ZeroTypeStatus.recording);
            _beginRecording();
            unawaited(
                _showNativeOverlay('recording', '錄音中${_modeLabel(quick)}'));
          },
          onAmplitude: (amp) {
            if (!ref.mounted || _cancelled) return;
            state = state.copyWith(amplitude: amp);
            _updateNativeAmplitude(amp);
            // 精簡模式：講完就自動送出，不必再按一次熱鍵。
            // 只在 recording 判斷 —— warmingUp 的音訊會被丟掉，
            // saving 之後 _stopAndProcess 已經在跑了。
            if (state.status == ZeroTypeStatus.recording &&
                (_quietGate?.accept(amp, DateTime.now()) ?? false)) {
              _quietGate = null;
              print('[ZeroType] Quick mode: silence detected, auto-stopping.');
              unawaited(_stopAndProcess());
            }
          },
        ),
      ]);
    } catch (e, st) {
      print('[ZeroType] startRecording failed: $e\n$st');
      if (!ref.mounted || _cancelled) return;
      _log.error('錄音啟動失敗：$e');
      state = const ZeroTypeState();
      await _hideNativeOverlay();
    }
  }

  /// 真的開始收音的那一刻：計時基準與逾時保險絲都從這裡重算，
  /// 等待麥克風就緒的那幾秒不該被算進錄音長度。
  void _beginRecording() {
    _recordingStartTime = DateTime.now();
    _armMaxDuration();
  }

  /// Max-duration safety timer from user setting (default 1 min, max 5 min)。
  /// warmingUp 也要蓋到 —— 麥克風若一直沒送出訊號（被靜音、被別的程式佔住），
  /// 等待是不會自己結束的，總不能讓麥克風就這樣一直開著。
  void _armMaxDuration() {
    _maxDurationTimer?.cancel();
    final maxMinutes = appPrefs.getInt(AppConstants.maxRecordingMinutesKey) ?? 1;
    _maxDurationTimer = Timer(Duration(minutes: maxMinutes), () {
      switch (state.status) {
        case ZeroTypeStatus.recording:
          print('[ZeroType] Max recording duration reached, auto-stopping.');
          _stopAndProcess();
        case ZeroTypeStatus.warmingUp:
          print('[ZeroType] Mic never became ready, cancelling.');
          cancel();
        default:
          break;
      }
    });
  }

  /// 音訊那一段唯一給的指令。刻意不放任何規則或範例 —— 那些都是模型
  /// 在聽不清楚時會拿來照抄的素材。
  ///
  /// notes: 一定要指定語言。只寫「Generate a transcript」時模型會直接輸出英文，
  /// 而第二段的規則寫著「英文保留原文不翻譯」，於是英文就這樣被留到最後。
  static const _kBareTranscribePrompt =
      '逐字轉錄音檔內容。維持說話者原本的語言，中文一律輸出繁體中文（台灣）。\n'
      '不要翻譯、不要說明、不要加任何前後語，只輸出轉錄結果本身。';

  /// 第二段偶爾會在短句尾巴憑空補一個 `_`（實測 12 次約 2 次）。提示詞壓不掉：
  /// 覆寫區塊點名禁止「底線」時某些輸入失守，改成不點名則換另一批輸入失守，
  /// 兩種寫法的總失敗率一樣。這是確定性的髒字元，用程式砍比繼續調提示詞可靠。
  /// 只有第一段逐字稿本來就沒有 `_` 時才砍——使用者真的講出底線就不該被吃掉。
  static String stripPhantomUnderscore(String corrected, String raw) =>
      raw.contains('_')
          ? corrected
          : corrected.replaceFirst(RegExp(r'\s*_+$'), '');

  /// 短句尾巴的句號拿掉：「好」「知道了」這種一兩個字的回覆，加了句號反而不像
  /// 講出來的話。門檻是不含尾端句號的 5 個字。
  ///
  /// notes: 用程式砍不用提示詞——標點是規則檔一路要求的，為了短句去鬆綁那條規則
  /// 會連長句一起失守。只處理句號（。與 .），問號驚嘆號是語氣，留著。
  static String stripShortSentencePeriod(String text) {
    final trimmed = text.trimRight();
    final stripped = trimmed.replaceFirst(RegExp(r'[。.]+$'), '');
    if (stripped.length == trimmed.length) return text; // 本來就沒有句號
    return stripped.runes.length < 5 ? stripped : text;
  }

  /// 第二段純文字處理：把使用者調過的格式規則原封不動搬過來，只加一句改寫框架，
  /// 讓它知道處理對象是文字而不是音檔。這裡有真實文字當輸入，範例就不再是
  /// 唯一可抄的東西了。
  String _buildTextStagePrompt(
    String rulesPrompt,
    String correctionPrompt,
    String text,
  ) =>
      '以下規則原本用於音訊轉錄，現在改為套用在「已經轉錄好的文字」上。\n'
      '規則與範例只是格式參考，它們的內容不得出現在輸出中。只輸出處理後的文字。\n\n'
      '$rulesPrompt\n\n'
      // notes: 覆寫區塊放在規則之後、待處理文字之前——規則檔裡「內容來自隨附的音檔」
      // 「音檔為空就輸出空字串」在第二段是假前提，模型找不到音檔會判定沒有輸入，
      // 於是回問或加前言（實測「天使多情」5 次有 3 次中招）。靠開頭那句框架壓不住，
      // 要在規則後面用近因覆寫才有效（實測 5/5 乾淨，其他規則不受影響）。
      // 刻意不去 replace 規則檔內文：那份是使用者可編輯的，字串比對隨時會失效。
      '--- 純文字模式，以下覆寫上方規則 ---\n'
      '- 上方規則提到的「音檔」，本次一律改指下方的「待處理文字」。'
      '本次沒有音檔，不代表沒有輸入。\n'
      '- 待處理文字不論多短都是有效內容，若已符合規則就原樣輸出。\n'
      '- 不得回問、不得說明、不得加前言，輸出只能是處理後的文字本身。\n'
      // notes: 短輸入沒別的規則可套時，模型會在句尾憑空補一個 `_`
      // （「天使多情」「風流倜儻」都中過）。當時來源是 step_4 的「口語描述還原成字元」，
      // 那條規則後來整條刪了，但這句留著——只要規則檔還有任何「偵測到 X 就替換」，
      // 沒東西可套的短輸入就會誘發同一種發明行為，這是最後一道防線。
      '- 不得補上待處理文字裡沒有的字元或符號（底線、括號、省略號等），'
      '標點只能加在語意斷點上。\n\n'
      '$correctionPrompt'
      '--- 待處理文字 ---\n$text';

  Future<TranscriptionResult?> _transcribe(String filePath) async {
    final config = await ref.read(speechProviderControllerProvider.future);
    final prompt = await ref.read(speechPromptControllerProvider.future);
    final dictionaryRepo = ref.read(dictionaryRepositoryProvider);

    if (config.providerId == null ||
        config.apiKey == null ||
        config.modelId == null) {
      throw Exception('請先完成語音辨識模型設定');
    }

    // notes: 跟音訊放同一個 context 的東西，模型都可能直接照抄或照著演 —— 字典詞
    // 會被憑空插入（見 buildCorrectionPrompt），格式規則與範例則會在音訊內容偏弱時
    // 被整段當成答案輸出（實測輸出跟 SpeechToText.prompt 的範例一字不差）。
    // 措辭怎麼改都壓不住，所以 chat 型服務商一律兩段式：音訊那段只給最小指令，
    // 規則、範例、字典全部移到第二段純文字處理。whisper（openai）不吃這套，維持原樣。
    final isWhisper = config.providerId == 'openai';
    final dictionaryPrompt =
        isWhisper ? await dictionaryRepo.buildDictionaryPrompt() : '';
    final audioPrompt = isWhisper
        ? (dictionaryPrompt.isEmpty ? prompt : '$prompt\n\n$dictionaryPrompt')
        : _kBareTranscribePrompt;

    final service = speechService;
    final result = await service.transcribe(
      audioFilePath: filePath,
      apiKey: config.apiKey!,
      provider: config.providerId!,
      model: config.modelId!,
      prompt: audioPrompt,
      customEndpoint: config.customEndpoint,
    );

    if (isWhisper || result.text.isEmpty) return result;
    final correctionPrompt = await dictionaryRepo.buildCorrectionPrompt();

    try {
      final corrected = await service.correctTranscript(
        apiKey: config.apiKey!,
        provider: config.providerId!,
        model: config.modelId!,
        prompt: _buildTextStagePrompt(prompt, correctionPrompt, result.text),
        customEndpoint: config.customEndpoint,
      );
      if (corrected.text.isEmpty) return result;
      return (
        text: stripPhantomUnderscore(corrected.text, result.text),
        inputTokens: _sumTokens(result.inputTokens, corrected.inputTokens),
        outputTokens: _sumTokens(result.outputTokens, corrected.outputTokens),
      );
    } catch (e) {
      // notes: 校正失敗不能吃掉逐字稿，退回第一段結果
      print('[ZeroType] Dictionary correction failed, using raw transcript: $e');
      return result;
    }
  }

  int? _sumTokens(int? a, int? b) => a == null ? b : a + (b ?? 0);

  Future<void> _stopAndProcess() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    state = state.copyWith(status: ZeroTypeStatus.saving);
    await _showNativeOverlay('saving', '擷取中');

    final stopTime = DateTime.now();
    final durationMs = _recordingStartTime != null
        ? stopTime.difference(_recordingStartTime!).inMilliseconds
        : null;

    try {
      // notes: 這裡播的是「麥克風真的關了」，跟下面送出貼上前那聲「文字準備好了」
      // 是兩個不同的提示音——中間還有辨識要跑好幾秒，用同一聲會讓人誤以為已經好了。
      final filePath = await _recordingService.stopRecording();
      unawaited(soundService.playRecordingStoppedSound());
      soundService.resumeMusic();

      if (!ref.mounted || _cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
        return;
      }
      if (filePath == null) {
        // 沒訊號、只有底噪，或麥克風根本沒送出資料。要講出來，不然使用者
        // 只會看到什麼都沒發生，還以為熱鍵壞了；也要講是哪一種，才查得下去。
        _log.error('這次沒有送出辨識：'
            '${_recordingService.lastDiscardReason ?? "沒有錄到聲音"}');
        state = const ZeroTypeState();
        await _hideNativeOverlay();
        return;
      }

      state = state.copyWith(status: ZeroTypeStatus.transcribing);
      await _showNativeOverlay('transcribing', '辨識中');

      final config = await ref.read(speechProviderControllerProvider.future);
      final raw = await _transcribe(filePath);
      // 各家 provider 的路徑都收斂在這裡，短句去句號只做這一次
      final result = raw == null
          ? null
          : (
              text: stripShortSentencePeriod(raw.text),
              inputTokens: raw.inputTokens,
              outputTokens: raw.outputTokens,
            );

      if (result == null || result.text.isEmpty) {
        // Cleanup temp file on empty result
        await _recordingService.deleteFile(filePath);
        throw Exception('未能辨識出任何文字');
      }

      // Move audio to history dir and save record
      final historyRepo = historyRepository;
      final audioHistoryPath = await historyRepo.moveAudioFile(filePath);

      final recordId = DateTime.now().millisecondsSinceEpoch.toString();
      final record = TranscriptionRecord(
        id: recordId,
        text: result.text,
        createdAt: DateTime.now(),
        audioPath: audioHistoryPath,
        durationMs: durationMs,
        provider: config.providerId ?? '',
        model: config.modelId ?? '',
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        costUsd: calculateCost(
          config.modelId ?? '',
          result.inputTokens,
          result.outputTokens,
        ),
      );
      await historyRepo.addRecord(record);
      await historyRepo.accumulateStats(record);
      // 歷史頁若正開著,不刷新就看不到剛剛這筆(切換分頁時才會重讀)
      ref.invalidate(historyControllerProvider);
      ref.invalidate(historyStatsProvider);

      // Output
      state = state.copyWith(status: ZeroTypeStatus.done, result: result.text);
      // 貼上是拿剪貼簿當中介，會蓋掉使用者原本複製的東西。這裡在覆蓋的前一刻
      // 記下來，貼完再還原。取「覆蓋前」而不是「錄音前」—— 錄音那幾秒使用者
      // 還是可能複製別的東西，要還原的是最近一次。
      final savedClipboard =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      await Clipboard.setData(ClipboardData(text: result.text));
      await Future.delayed(const Duration(milliseconds: 150));

      // notes: 提示音在送出貼上前響，不 await —— 播放本身不該卡住流程
      unawaited(soundService.playStopSound());

      print('[ZeroType] Simulating paste...');
      const channel = MethodChannel('com.zerotype.app/keyboard');
      // notes: VS 內建終端機收不到注入的按鍵，精簡模式在那裡不會自動送出 —— 那個
      // 控制項的 wndproc 對鍵盤訊息一律不理。曾試過把換行併進剪貼簿讓貼上自帶
      // Enter，可行但使用者不要，別再加回來。
      final autoEnter = _quickMode &&
          (appPrefs.getBool(AppConstants.quickAutoEnterKey) ?? true);
      final pasted = await channel
          .invokeMethod<bool>('simulatePaste', {'pressEnter': autoEnter});
      // 貼上之後才問，這樣 focus= 拿到的是按鍵真正送達那一刻的狀態
      final target =
          await channel.invokeMethod<String>('describePasteTarget') ?? '(未知)';
      _log.debug('貼上目標：$target');
      if (pasted == false) {
        _log.error('沒貼上（焦點切不回原本的視窗，或按熱鍵時焦點在 ZeroType 自己'
            '身上）；文字已複製到剪貼簿');
        // 貼上失敗時畫面上什麼都不會發生，沒有聲音就只能等使用者自己發現
        unawaited(soundService.playFailedSound());
      }

      // 沒貼上時不還原 —— 那時剪貼簿裡的辨識結果是使用者唯一的救援手段
      if (pasted == true && savedClipboard != null && savedClipboard.isNotEmpty) {
        unawaited(_restoreClipboard(savedClipboard, result.text));
      }

      _log.info(result.text);
      state = const ZeroTypeState();
      await _hideNativeOverlay();
    } catch (e, st) {
      print('[ZeroType] ERROR in _stopAndProcess: $e\n$st');
      if (!ref.mounted || _cancelled) return;
      _log.error('處理失敗：$e');
      // 辨識／API 失敗（API Key 錯誤、額度、斷網）畫面上只有紀錄頁看得到，
      // 沒有聲音使用者會一直等一段永遠不會出現的文字
      unawaited(soundService.playFailedSound());
      await soundService.resumeMusic();
      state = const ZeroTypeState();
      await _hideNativeOverlay();
    }
  }

  /// 把剪貼簿還原成貼上前的 [saved]。
  ///
  /// notes: 只顧文字。Flutter 的 Clipboard 只讀得到 text/plain，原本放的是圖片或
  /// 檔案就救不回來（那時 [saved] 是 null，我們乾脆不還原，把辨識結果留著）。
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

  /// 熱鍵按下後要讓使用者看得出走的是哪一條路。
  static String _modeLabel(bool quick) => quick ? '（精簡）' : '（全局）';

  Future<void> showOverlay(String status, String message) =>
      _showNativeOverlay(status, message);

  Future<void> hideOverlay() => _hideNativeOverlay();

  Future<void> _showNativeOverlay(String status, String message) async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('show', {
        'status': status,
        'message': message,
      });
    } catch (_) {}
  }

  Future<void> _hideNativeOverlay() async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  Future<void> _updateNativeAmplitude(double amplitude) async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('updateAmplitude', {
        'amplitude': amplitude,
      });
    } catch (_) {}
  }
}
