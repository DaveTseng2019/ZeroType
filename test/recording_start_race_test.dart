import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:zero_type/core/services/recording_service.dart';

/// 假的錄音平台：記下麥克風現在是不是開著。
class _FakeRecordPlatform extends RecordPlatform {
  bool micOpen = false;
  int streamsOpened = 0;
  StreamController<Uint8List>? _ctrl;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<Stream<Uint8List>> startStream(
      String recorderId, RecordConfig config) async {
    micOpen = true;
    streamsOpened++;
    _ctrl = StreamController<Uint8List>();
    return _ctrl!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    micOpen = false;
    await _ctrl?.close();
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

/// 重現「錄音還在啟動時就停止或取消，麥克風會一直開著」。
///
/// startRecording 在真正開串流之前要先 await getTemporaryDirectory()。
/// 這段期間 stopRecording／cancelRecording 找不到串流，等 startRecording
/// 跑完，串流照樣打開，之後沒有任何路徑會關它。
///
/// 修法：stopRecording／cancelRecording 先等進行中的 startRecording 跑完。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late _FakeRecordPlatform platform;
  late Completer<void> tempDirGate;

  setUp(() {
    platform = _FakeRecordPlatform();
    RecordPlatform.instance = platform;
    tempDirGate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') {
        // 卡住，模擬「錄音還在啟動」的那段空檔
        await tempDirGate.future;
        return Directory.systemTemp.path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });

  test('啟動中按 Esc（cancelRecording），麥克風最後要是關的', () async {
    final rs = RecordingService();
    final starting = rs.startRecording();

    // 使用者按下熱鍵後馬上按 Esc。取消會等啟動跑完，所以這裡先不 await。
    final cancelling = rs.cancelRecording();
    tempDirGate.complete(); // startRecording 繼續往下跑
    await starting;
    await cancelling;

    expect(platform.streamsOpened, 1, reason: '前提：串流確實被打開過');
    expect(platform.micOpen, isFalse,
        reason: '取消之後才打開的串流沒有人關，麥克風一直開著');
  });

  test('啟動中再按一次熱鍵（stopRecording），麥克風最後要是關的', () async {
    final rs = RecordingService();
    final starting = rs.startRecording();

    final stopping = rs.stopRecording(); // 快速連按兩次熱鍵
    tempDirGate.complete();
    await starting;
    final path = await stopping;

    expect(path, isNull, reason: '前提：停止時還沒有任何音訊');
    expect(platform.streamsOpened, 1, reason: '前提：串流確實被打開過');
    expect(platform.micOpen, isFalse,
        reason: '停止之後才打開的串流沒有人關，麥克風一直開著');
  });
}
