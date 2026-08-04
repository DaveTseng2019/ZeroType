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
    if (was != now) unawaited(trayService.setRecording(now));
    if (wasActive != nowActive) {
      const controlChannel = MethodChannel('com.zerotype.app/control');
      unawaited(controlChannel
          .invokeMethod<void>('setCancelHotkeyArmed', nowActive)
          .catchError((_) {}));
    }
  }

  Future<void> toggleRecording() async {
    print('[ZeroTypeController] Hotkey triggered! Current status: ${state.status}');
    if (state.status == ZeroTypeStatus.recording) {
      await _stopAndProcess();
    } else if (state.status == ZeroTypeStatus.idle) {
      await _startRecording();
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

  Future<void> _startRecording() async {
    _cancelled = false;

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
        _showNativeOverlay('recording', warming ? '準備中' : '錄音中'),
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
            unawaited(_showNativeOverlay('recording', '錄音中'));
          },
          onAmplitude: (amp) {
            if (ref.mounted && !_cancelled) {
              state = state.copyWith(amplitude: amp);
              _updateNativeAmplitude(amp);
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
        text: corrected.text,
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
        // 整段都是靜音（見 hasAnySound），或麥克風根本沒送出資料。
        // 要講出來，不然使用者只會看到什麼都沒發生，還以為熱鍵壞了。
        _log.error('沒有錄到聲音，這次沒有送出辨識');
        state = const ZeroTypeState();
        await _hideNativeOverlay();
        return;
      }

      state = state.copyWith(status: ZeroTypeStatus.transcribing);
      await _showNativeOverlay('transcribing', '辨識中');

      final config = await ref.read(speechProviderControllerProvider.future);
      final result = await _transcribe(filePath);

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
      await Clipboard.setData(ClipboardData(text: result.text));
      await Future.delayed(const Duration(milliseconds: 150));

      // notes: 提示音在送出貼上前響，不 await —— 播放本身不該卡住流程
      unawaited(soundService.playStopSound());

      print('[ZeroType] Simulating paste...');
      const channel = MethodChannel('com.zerotype.app/keyboard');
      await channel.invokeMethod('simulatePaste');

      _log.info('文字：${result.text}');
      state = const ZeroTypeState();
      await _hideNativeOverlay();
    } catch (e, st) {
      print('[ZeroType] ERROR in _stopAndProcess: $e\n$st');
      if (!ref.mounted || _cancelled) return;
      _log.error('處理失敗：$e');
      await soundService.resumeMusic();
      state = const ZeroTypeState();
      await _hideNativeOverlay();
    }
  }

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
