import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/latency_log.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';
import 'package:zero_type/core/services/tray_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/history/repositories/history_repository.dart';
import 'package:zero_type/features/model_config/presentation/controllers/model_config_controller.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';

// ── 假的依賴 ────────────────────────────────────────────────────────────────
// 不改 lib：injection.dart 的單例是 late final，測試在第一次使用前自己指定；
// 檔案類的服務（歷史、延遲紀錄、字典）用真的，但 path_provider 導到暫存資料夾。

class _FakeSound implements SoundService {
  @override
  Duration get startSoundAudibleDuration => Duration.zero;
  @override
  Future<void> playStartSound() async {}
  @override
  Future<void> playStopSound() async {}
  @override
  Future<void> playCancelSound() async {}
  @override
  Future<void> playFailedSound() async {}
  @override
  Future<void> playRecordingStoppedSound() async {}
  @override
  Future<void> pauseMusic() async {}
  @override
  Future<void> resumeMusic() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeTray implements TrayService {
  final calls = <bool>[];
  @override
  Future<void> setRecording(bool recording, {bool quick = false}) async =>
      calls.add(recording);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 辨識服務：呼叫進來之後卡住，等測試放行，才能在「辨識中」插入動作。
class _FakeSpeech implements SpeechRecognitionService {
  Completer<void> started = Completer<void>();
  Completer<TranscriptionResult> result = Completer<TranscriptionResult>();

  @override
  Future<TranscriptionResult> transcribe({
    required String audioFilePath,
    required String apiKey,
    required String provider,
    required String model,
    required String prompt,
    String? customEndpoint,
    String hotwords = '',
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRecordPlatform extends RecordPlatform {
  bool micOpen = false;
  StreamController<Uint8List>? ctrl;

  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<Stream<Uint8List>> startStream(
      String recorderId, RecordConfig config) async {
    micOpen = true;
    ctrl = StreamController<Uint8List>();
    return ctrl!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    micOpen = false;
    await ctrl?.close();
    return null;
  }

  @override
  Future<void> cancel(String recorderId) => stop(recorderId);
  @override
  Future<bool> isRecording(String recorderId) async => micOpen;
  @override
  Future<bool> isPaused(String recorderId) async => false;
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Future<void> dispose(String recorderId) async {}
  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];
  @override
  Future<void> start(String recorderId, RecordConfig config,
          {required String path}) async =>
      throw UnimplementedError();
  @override
  Future<void> pause(String recorderId) async {}
  @override
  Future<void> resume(String recorderId) async {}
  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);
  @override
  Future<bool> isEncoderSupported(
          String recorderId, AudioEncoder encoder) async =>
      true;
  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream.empty();
}

class _FakeSpeechProvider extends SpeechProviderController {
  @override
  Future<SpeechProviderConfig> build() async => (
        providerId: 'local', // 本機服務商：一段式、不需要金鑰
        modelId: 'test-model',
        apiKey: null,
        customEndpoint: null,
      );
}

class _FakePrompt extends SpeechPromptController {
  @override
  Future<String> build() async => '';
}

/// 0.5 秒、夠大聲的正弦波：過得了 hasAnySound，太短不做動態範圍判斷。
Uint8List _speechLikePcm() {
  const n = 8000;
  final bd = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    bd.setInt16(i * 2, (8000 * sin(2 * pi * 440 * i / 16000)).round(),
        Endian.little);
  }
  return bd.buffer.asUint8List();
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// 重現「辨識中按取消沒有效果；如果接著開始新的錄音，新錄音會被舊流程覆蓋」。
///
/// _stopAndProcess 只在停止錄音後檢查一次 _cancelled，辨識回來之後不再檢查。
/// 新一輪 _startRecording 又會把 _cancelled 設回 false。
///
/// 修法：控制器的錄音輪次編號（_session），每次 await 回來先比對。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory sandbox;
  final tray = _FakeTray();
  final speech = _FakeSpeech();
  late _FakeRecordPlatform platform;
  var pasteCount = 0;

  setUpAll(() async {
    sandbox = Directory.systemTemp.createTempSync('zerotype_race_');
    // 所有 path_provider 的位置都導到暫存資料夾，不碰使用者真的歷史紀錄
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => sandbox.path);

    SharedPreferences.setMockInitialValues({});
    appPrefs = await SharedPreferences.getInstance();
    soundService = _FakeSound();
    trayService = tray;
    speechService = speech;
    historyRepository = HistoryRepository();
    latencyLog = LatencyLog();
  });

  tearDownAll(() {
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    platform = _FakeRecordPlatform();
    RecordPlatform.instance = platform;
    speech
      ..started = Completer<void>()
      ..result = Completer<TranscriptionResult>();
    tray.calls.clear();
    pasteCount = 0;

    messenger.setMockMethodCallHandler(
        const MethodChannel('com.zerotype.app/keyboard'), (call) async {
      switch (call.method) {
        case 'simulatePaste':
          pasteCount++;
          return true;
        case 'describePasteTarget':
          return 'test';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.zerotype.app/permission'),
        (call) async => call.method == 'checkAccessibility' ? true : null);
    for (final name in ['overlay', 'control']) {
      messenger.setMockMethodCallHandler(
          MethodChannel('com.zerotype.app/$name'), (_) async => null);
    }
    messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      speechProviderControllerProvider.overrideWith(_FakeSpeechProvider.new),
      speechPromptControllerProvider.overrideWith(_FakePrompt.new),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// 錄一段話、按熱鍵停止，停在「辨識中」。回傳停止流程的 Future。
  /// 包在 record 裡：async 函式直接回 Future 會被攤平成「等它跑完」。
  Future<({Future<void> stopping})> recordUntilTranscribing(
      ZeroTypeController ctrl, ProviderContainer c) async {
    await ctrl.toggleRecording(); // 開始
    expect(c.read(zeroTypeControllerProvider).status, ZeroTypeStatus.recording,
        reason: '前提：已在錄音');
    platform.ctrl!.add(_speechLikePcm());
    await _settle();
    final stopping = ctrl.toggleRecording(); // 停止，送辨識
    await speech.started.future;
    expect(c.read(zeroTypeControllerProvider).status,
        ZeroTypeStatus.transcribing,
        reason: '前提：已在辨識中');
    return (stopping: stopping);
  }

  test('辨識中按 Esc 取消，辨識結果不該再貼上', () async {
    final c = makeContainer();
    final ctrl = c.read(zeroTypeControllerProvider.notifier);
    final (:stopping) = await recordUntilTranscribing(ctrl, c);

    await ctrl.cancel(); // 使用者按 Esc
    expect(c.read(zeroTypeControllerProvider).status, ZeroTypeStatus.idle,
        reason: '前提：取消後畫面已回到閒置');

    speech.result.complete((
      text: '不該出現的文字',
      inputTokens: null,
      outputTokens: null,
      audioInputTokens: null,
      costUsd: null,
    ));
    await stopping;

    expect(pasteCount, 0, reason: '已經取消了，文字仍然被貼上');
  });

  test('取消後馬上開始新錄音，舊流程不該把新錄音改成閒置', () async {
    final c = makeContainer();
    final ctrl = c.read(zeroTypeControllerProvider.notifier);
    final (:stopping) = await recordUntilTranscribing(ctrl, c);

    await ctrl.cancel(); // Esc
    await ctrl.toggleRecording(); // 馬上錄下一段
    expect(c.read(zeroTypeControllerProvider).status, ZeroTypeStatus.recording,
        reason: '前提：新的一段已經在錄');
    expect(platform.micOpen, isTrue, reason: '前提：新錄音的麥克風開著');

    speech.result.complete((
      text: '舊的辨識結果',
      inputTokens: null,
      outputTokens: null,
      audioInputTokens: null,
      costUsd: null,
    ));
    await stopping; // 舊流程跑完

    expect(platform.micOpen, isTrue, reason: '前提：麥克風實際上還在收音');
    expect(c.read(zeroTypeControllerProvider).status, ZeroTypeStatus.recording,
        reason: '麥克風還開著，狀態卻被舊流程改掉了（圖示、Esc、逾時都失效）');
  });
}
