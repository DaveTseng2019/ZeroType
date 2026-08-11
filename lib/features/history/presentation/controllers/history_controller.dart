import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/features/history/entities/history_stats.dart';
import 'package:zero_type/features/history/entities/transcription_record.dart';
import 'package:zero_type/features/log/log_controller.dart';

// ---------------------------------------------------------------------------
// Stats provider — cumulative, persisted independently of the record list
// ---------------------------------------------------------------------------

final historyStatsProvider =
    FutureProvider<HistoryStats>((ref) => historyRepository.getStats());

// ---------------------------------------------------------------------------
// Playback state — which record id is currently playing
// ---------------------------------------------------------------------------

final playingRecordIdProvider =
    NotifierProvider<PlayingRecordId, String?>(PlayingRecordId.new);

class PlayingRecordId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

// ---------------------------------------------------------------------------
// History controller — manages record list and audio playback
// ---------------------------------------------------------------------------

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, List<TranscriptionRecord>>(
        HistoryController.new);

class HistoryController extends AsyncNotifier<List<TranscriptionRecord>> {
  Process? _macProcess; // macOS afplay

  @override
  Future<List<TranscriptionRecord>> build() async {
    ref.onDispose(_killProcess);
    return historyRepository.getRecords();
  }

  // Safe to call from onDispose — does NOT touch ref
  void _killProcess() {
    _macProcess?.kill();
    _macProcess = null;
  }

  void _stopPlayback() {
    _killProcess();
    ref.read(playingRecordIdProvider.notifier).set(null);
  }

  Future<void> togglePlay(TranscriptionRecord record) async {
    final currentId = ref.read(playingRecordIdProvider);
    final audioPath = record.audioPath;
    if (audioPath == null) return;

    if (currentId == record.id) {
      // Stop current playback
      _stopPlayback();
      return;
    }

    // Stop any existing playback first
    _stopPlayback();

    // Start new playback
    ref.read(playingRecordIdProvider.notifier).set(record.id);

    if (Platform.isMacOS) {
      _macProcess = await Process.start('afplay', [audioPath]);
      _macProcess!.exitCode.then((_) {
        if (ref.read(playingRecordIdProvider) == record.id) {
          ref.read(playingRecordIdProvider.notifier).set(null);
        }
        _macProcess = null;
      });
    } else if (Platform.isWindows) {
      // On Windows, open with default media player (no background control)
      // audioplayers integration can be added here if needed
      await Process.run('powershell', [
        '-Command',
        'Start-Process "$audioPath"',
      ]);
      ref.read(playingRecordIdProvider.notifier).set(null);
    }
  }

  /// 開啟音檔資料夾。所有錄音都在同一個地方，所以是整頁一顆按鈕，
  /// 不是每筆記錄各一顆。
  Future<void> openAudioFolder() async {
    try {
      final dir = (await historyRepository.audioDir()).path;
      if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isWindows) {
        // 分隔符一定要全部換成反斜線。路徑是拿 getApplicationSupportDirectory()
        // （反斜線）接上 '/history_audio' 組出來的，混合分隔符 Windows API 吃得下，
        // 但 explorer.exe 的命令列剖析器不吃 —— 它會當成無法辨識的參數，默默改開
        // 預設資料夾（「文件」），看起來就像按鈕跑錯地方。
        await Process.run('explorer.exe', [dir.replaceAll('/', r'\')]);
      }
    } catch (e) {
      print('[HistoryController] openAudioFolder error: $e');
    }
  }

  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> deleteRecord(String id) async {
    final currentId = ref.read(playingRecordIdProvider);
    if (currentId == id) _stopPlayback();
    await historyRepository.deleteRecord(id);
    ref.invalidateSelf();
  }

  Future<void> clearAll() async {
    _stopPlayback();
    await historyRepository.clearAll();
    ref.invalidateSelf();
    ref.invalidate(historyStatsProvider);
    ref.read(logControllerProvider.notifier).clear();
  }
}
