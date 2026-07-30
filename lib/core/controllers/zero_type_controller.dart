import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'package:zero_type/features/history/domain/repositories/history_repository.dart';
import 'package:zero_type/features/model_config/presentation/controllers/model_config_controller.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';
import 'package:zero_type/features/dictionary/presentation/controllers/dictionary_controller.dart';

part 'zero_type_controller.g.dart';

@Riverpod(keepAlive: true)
class ZeroTypeController extends _$ZeroTypeController {
  late final RecordingService _recordingService;
  bool _cancelled = false;
  DateTime? _recordingStartTime;
  Timer? _maxDurationTimer;

  @override
  ZeroTypeState build() {
    _recordingService = RecordingService();
    ref.onDispose(() => _recordingService.dispose());

    // Listen for cancel signals from the native overlay (X button or ESC)
    const controlChannel = MethodChannel('com.zerotype.app/control');
    controlChannel.setMethodCallHandler((call) async {
      if (call.method == 'cancel') await cancel();
    });

    return const ZeroTypeState();
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
    if (state.status == ZeroTypeStatus.recording) {
      state = state.copyWith(status: ZeroTypeStatus.cancelling);
      unawaited(_showNativeOverlay('cancelling', '取消中'));
      await _recordingService.cancelRecording();
    }
    await getIt<SoundService>().playCancelSound();
    await getIt<SoundService>().resumeMusic();
    state = const ZeroTypeState();
    await _hideNativeOverlay();
  }

  Future<void> _startRecording() async {
    _cancelled = false;

    final config = await ref.read(speechProviderControllerProvider.future);
    if (config.providerId == null || config.providerId!.isEmpty ||
        config.apiKey == null || config.apiKey!.isEmpty ||
        config.modelId == null || config.modelId!.isEmpty) {
      await _showNativeOverlay('error', '請先完成語音辨識模型設定');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
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
      await _showNativeOverlay('error', '請先授權輔助使用權限');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
      return;
    }
    if (!hasPermission) {
      await _showNativeOverlay('error', '請先授權麥克風權限');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
      return;
    }

    // 開了等待麥克風就緒時，提示音改由 onCaptureStart 觸發 —— 那一刻才真的收得到聲音。
    // 提早播只會在藍牙切 HFP 的當下被吃掉，等於沒有提示。
    final warmupTimeout = Duration(
      milliseconds:
          getIt<SharedPreferences>().getInt(AppConstants.recordWarmupMsKey) ?? 0,
    );

    // [優化2] 音效不阻塞錄音啟動
    unawaited(getIt<SoundService>().pauseMusic());
    if (warmupTimeout == Duration.zero) {
      unawaited(getIt<SoundService>().playStartSound());

      // Windows 開啟音訊擷取會壓掉正在播的開始音，先給音效一點頭段
      if (Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    if (!ref.mounted || _cancelled) return;
    state = state.copyWith(status: ZeroTypeStatus.recording, amplitude: 0.0);
    _recordingStartTime = DateTime.now();

    // Start max-duration safety timer from user setting (default 1 min, max 5 min)
    final maxMinutes = getIt<SharedPreferences>()
        .getInt(AppConstants.maxRecordingMinutesKey) ?? 1;
    _maxDurationTimer = Timer(Duration(minutes: maxMinutes), () {
      if (state.status == ZeroTypeStatus.recording) {
        print('[ZeroType] Max recording duration reached, auto-stopping.');
        _stopAndProcess();
      }
    });

    // [優化3] overlay 顯示與錄音初始化同步進行
    try {
      await Future.wait([
        _showNativeOverlay('recording', '錄音中'),
        _recordingService.startRecording(
          deviceId: getIt<SharedPreferences>()
              .getString(AppConstants.inputDeviceIdKey),
          noiseGate: getIt<SharedPreferences>()
                  .getBool(AppConstants.noiseGateEnabledKey) ??
              false,
          noiseGateStrength: getIt<SharedPreferences>()
                  .getDouble(AppConstants.noiseGateStrengthKey) ??
              kDefaultNoiseGateStrength,
          warmupTimeout: warmupTimeout,
          onCaptureStart: () {
            if (ref.mounted && !_cancelled) {
              unawaited(getIt<SoundService>().playStartSound());
            }
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
      state = state.copyWith(
        status: ZeroTypeStatus.error,
        errorMessage: '錄音啟動失敗：$e',
      );
      await _showNativeOverlay('error', '錄音啟動失敗');
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
    }
  }

  Future<TranscriptionResult?> _transcribe(String filePath) async {
    final config = await ref.read(speechProviderControllerProvider.future);
    final prompt = await ref.read(speechPromptControllerProvider.future);
    final dictionaryPrompt =
        await ref.read(dictionaryRepositoryProvider).buildDictionaryPrompt();

    if (config.providerId == null ||
        config.apiKey == null ||
        config.modelId == null) {
      throw Exception('請先完成語音辨識模型設定');
    }

    final finalPrompt =
        dictionaryPrompt.isEmpty ? prompt : '$prompt\n\n$dictionaryPrompt';

    final service = getIt<SpeechRecognitionService>();
    return service.transcribe(
      audioFilePath: filePath,
      apiKey: config.apiKey!,
      provider: config.providerId!,
      model: config.modelId!,
      prompt: finalPrompt,
      customEndpoint: config.customEndpoint,
    );
  }

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
      final stopFuture = _recordingService.stopRecording();
      final soundFuture = getIt<SoundService>().playStopSound();
      getIt<SoundService>().resumeMusic();

      final filePath = await stopFuture;
      await soundFuture;

      if (!ref.mounted || _cancelled || filePath == null) {
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
      final historyRepo = getIt<HistoryRepository>();
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

      // Output
      state = state.copyWith(status: ZeroTypeStatus.done, result: result.text);
      await Clipboard.setData(ClipboardData(text: result.text));
      await Future.delayed(const Duration(milliseconds: 150));

      print('[ZeroType] Simulating paste...');
      const channel = MethodChannel('com.zerotype.app/keyboard');
      await channel.invokeMethod('simulatePaste');

      await _showNativeOverlay('done', '已完成');
      await Future.delayed(const Duration(seconds: 2));

      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
    } catch (e, st) {
      print('[ZeroType] ERROR in _stopAndProcess: $e\n$st');
      if (!ref.mounted || _cancelled) return;
      state = state.copyWith(
        status: ZeroTypeStatus.error,
        errorMessage: e.toString(),
      );
      await _showNativeOverlay('error', '處理失敗：$e');
      await getIt<SoundService>().resumeMusic();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
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
