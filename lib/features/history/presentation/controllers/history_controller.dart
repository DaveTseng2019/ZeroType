import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/sound_service.dart';
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
  Timer? _winTimer; // Windows PlaySoundW 播完的計時器

  @override
  Future<List<TranscriptionRecord>> build() async {
    ref.onDispose(_killProcess);
    return historyRepository.getRecords();
  }

  // Safe to call from onDispose — does NOT touch ref
  void _killProcess() {
    _macProcess?.kill();
    _macProcess = null;
    // 只在自己播過時才停 —— PlaySoundW 是全域單軌，無條件停會打斷正在播的提示音
    if (_winTimer != null) {
      _winTimer!.cancel();
      _winTimer = null;
      SoundService.stopWavFile();
    }
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
      // 跟提示音效走同一條 PlaySoundW，不外開預設播放器
      final duration = SoundService.playWavFile(audioPath);
      if (duration == null) {
        // 不是 WAV 或讀不到長度，播不了也不知道何時結束 —— 直接復原按鈕狀態
        ref.read(playingRecordIdProvider.notifier).set(null);
        return;
      }
      _winTimer = Timer(duration, () {
        _winTimer = null;
        if (ref.read(playingRecordIdProvider) == record.id) {
          ref.read(playingRecordIdProvider.notifier).set(null);
        }
      });
    }
  }

  /// 開啟資料夾。所有紀錄都在同一個地方，所以是整頁一顆按鈕，
  /// 不是每筆記錄各一顆。
  Future<void> openDataFolder() async {
    try {
      final dir = (await historyRepository.dataDir()).path;
      if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isWindows) {
        // notes: 分隔符一定要全部換成反斜線。這條路徑目前是純反斜線，但
        // getApplicationSupportDirectory() 之後接任何 '/xxx' 就會變混合分隔符 ——
        // Windows API 吃得下，explorer.exe 的命令列剖析器不吃，它會當成無法辨識的
        // 參數，默默改開預設資料夾（「文件」），看起來就像按鈕跑錯地方。留著當保險。
        await Process.run('explorer.exe', [dir.replaceAll('/', r'\')]);
      }
    } catch (e) {
      print('[HistoryController] openDataFolder error: $e');
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
