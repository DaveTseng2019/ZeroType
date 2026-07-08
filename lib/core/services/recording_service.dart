import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

typedef AmplitudeCallback = void Function(double amplitude);

class RecordingService {
  RecordingService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  String? _currentFilePath;
  // Use a stream subscription instead of a manual timer + getAmplitude() polling.
  // The manual timer approach caused a deadlock on macOS: in-flight getAmplitude()
  // MethodChannel calls would block stop() on the native side indefinitely.
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  Future<bool> checkPermission() async {
    return _recorder.hasPermission();
  }

  Future<bool> requestPermission() async {
    // hasPermission() on macOS will trigger the system dialog if not yet decided
    return _recorder.hasPermission();
  }

  Future<void> startRecording({AmplitudeCallback? onAmplitude}) async {
    final dir = await getTemporaryDirectory();
    // The sandbox cache dir may not exist when app-sandbox is disabled in debug.
    // Creating it ensures AVAudioRecorder can actually write the file.
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = '${dir.path}/zerotype_$timestamp.m4a';

    print('[RecordingService] starting at $_currentFilePath');
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        // Windows Media Foundation 的 AAC 編碼器只支援 44.1/48 kHz，
        // 16 kHz 會拋 MF_E_INVALIDMEDIATYPE。
        sampleRate: Platform.isWindows ? 44100 : 16000,
      ),
      path: _currentFilePath!,
    );

    final isRec = await _recorder.isRecording();
    print('[RecordingService] isRecording after start: $isRec');

    if (onAmplitude != null) {
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        // Map practical speech range (-50 dBFS silence → -5 dBFS loud) to 0–1
        final normalized = ((amp.current + 50) / 45).clamp(0.0, 1.0);
        onAmplitude(normalized);
      });
    }
  }

  Future<String?> stopRecording() async {
    // Cancel the stream subscription first — this is clean and non-blocking,
    // unlike the old timer approach which left getAmplitude() calls in-flight.
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    final isRec = await _recorder.isRecording();
    print('[RecordingService] calling _recorder.stop()... isRecording=$isRec');
    if (!isRec) {
      // Recorder never started (e.g. file path invalid) — skip stop() to avoid hang.
      print('[RecordingService] recorder not active, skipping stop()');
      return _currentFilePath;
    }
    try {
      await _recorder.stop().timeout(const Duration(seconds: 8));
      print('[RecordingService] _recorder.stop() completed. path=$_currentFilePath');
    } catch (e) {
      print('[RecordingService] _recorder.stop() error/timeout: $e');
    }
    return _currentFilePath;
  }

  Future<void> cancelRecording() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    final isRec = await _recorder.isRecording();
    if (isRec) {
      try {
        await _recorder.stop().timeout(const Duration(seconds: 8));
      } catch (e) {
        print('[RecordingService] cancelRecording stop error: $e');
      }
    }
    await _deleteCurrentFile();
  }

  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Moves [srcPath] to [destPath]. Tries rename first, falls back to copy+delete.
  Future<String> moveFileTo(String srcPath, String destPath) async {
    final srcFile = File(srcPath);
    try {
      await srcFile.rename(destPath);
    } catch (_) {
      await srcFile.copy(destPath);
      await srcFile.delete();
    }
    return destPath;
  }

  Future<void> _deleteCurrentFile() async {
    if (_currentFilePath != null) {
      await deleteFile(_currentFilePath!);
      _currentFilePath = null;
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
