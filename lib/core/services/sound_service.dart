import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';

/// 音效播完至少要有這麼長，太短的系統音效（例如 Speech On.wav 只有一百多毫秒）
/// 聽起來像沒放到，用重播頂到這個長度。
const Duration kMinSoundDuration = Duration(milliseconds: 900);

/// 從 WAV 檔案內容算出播放時長。走訪 chunk 找 'fmt ' 和 'data'，不能假設
/// 固定 offset —— 有些系統音效檔在中間插了額外 chunk（如 LIST）。
/// 解析失敗（非 WAV、檔案損毀）回 null。
Duration? wavDuration(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final bd = ByteData.sublistView(bytes);
  if (bd.getUint32(0, Endian.big) != 0x52494646 /* RIFF */ ||
      bd.getUint32(8, Endian.big) != 0x57415645 /* WAVE */) {
    return null;
  }

  var offset = 12;
  int? byteRate;
  int? dataSize;
  while (offset + 8 <= bytes.length) {
    final id = bd.getUint32(offset, Endian.big);
    final size = bd.getUint32(offset + 4, Endian.little);
    if (id == 0x666d7420 /* fmt  */ && offset + 20 <= bytes.length) {
      byteRate = bd.getUint32(offset + 16, Endian.little);
    } else if (id == 0x64617461 /* data */) {
      dataSize = size;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
    if (byteRate != null && dataSize != null) break;
  }
  if (byteRate == null || byteRate == 0 || dataSize == null) return null;
  return Duration(milliseconds: (dataSize * 1000 / byteRate).round());
}

/// 音效實際長度不到 [minDuration] 就重播頂到夠長；長度未知（解析失敗）就當作
/// 已經夠長，只播一次 —— 猜錯的下限是「不重複」，不是「連環重播」。
/// 上限 5 次防止極短音檔（例如壞掉、只有幾個取樣）被無意義地連放一大串。
int repeatCountFor(Duration? actual, {Duration minDuration = kMinSoundDuration}) {
  if (actual == null || actual <= Duration.zero || actual >= minDuration) {
    return 1;
  }
  return min(5, (minDuration.inMicroseconds / actual.inMicroseconds).ceil());
}

/// 系統音效清單（路徑 → 顯示名稱），依平台切換
final Map<String, String> kSystemSoundLabels =
    Platform.isWindows ? kWindowsSoundLabels : kMacSoundLabels;

const Map<String, String> kMacSoundLabels = {
  '/System/Library/PrivateFrameworks/SpeechObjects.framework/Versions/A/Frameworks/DictationServices.framework/Versions/A/Resources/DefaultRecognitionSound.aiff':
      '語音輸入',
  '/System/Library/Sounds/Basso.aiff': 'Basso',
  '/System/Library/Sounds/Blow.aiff': 'Blow',
  '/System/Library/Sounds/Bottle.aiff': 'Bottle',
  '/System/Library/Sounds/Frog.aiff': 'Frog',
  '/System/Library/Sounds/Funk.aiff': 'Funk',
  '/System/Library/Sounds/Glass.aiff': 'Glass',
  '/System/Library/Sounds/Hero.aiff': 'Hero',
  '/System/Library/Sounds/Morse.aiff': 'Morse',
  '/System/Library/Sounds/Ping.aiff': 'Ping',
  '/System/Library/Sounds/Pop.aiff': 'Pop',
  '/System/Library/Sounds/Purr.aiff': 'Purr',
  '/System/Library/Sounds/Sosumi.aiff': 'Sosumi',
  '/System/Library/Sounds/Submarine.aiff': 'Submarine',
  '/System/Library/Sounds/Tink.aiff': 'Tink',
};

const String kDefaultStartSound = '/System/Library/Sounds/Ping.aiff';
const String kDefaultStopSound = '/System/Library/Sounds/Submarine.aiff';
const String kDefaultCancelSound = '/System/Library/Sounds/Basso.aiff';
/// 麥克風真正關閉那一刻播的音效（跟 [kDefaultStopSound] 不同 —— 那個是「文字準備好了」）。
const String kDefaultRecordingStoppedSound = '/System/Library/Sounds/Tink.aiff';

/// Windows 內建語音提示音（對應 macOS 預設音效）
///
/// 「錄音結束」配 Speech Off、「辨識完成」配 Notify —— 麥克風開關用同一組
/// Speech On/Off 才成對，文字好了是另一回事，用通知音。
const Map<String, String> kWindowsSounds = {
  kDefaultStartSound: r'C:\Windows\Media\Speech On.wav',
  kDefaultStopSound: r'C:\Windows\Media\Windows Notify.wav',
  kDefaultCancelSound: r'C:\Windows\Media\Speech Misrecognition.wav',
  kDefaultRecordingStoppedSound: r'C:\Windows\Media\Speech Off.wav',
};

const Map<String, String> kWindowsSoundLabels = {
  r'C:\Windows\Media\Speech On.wav': '語音開始',
  r'C:\Windows\Media\Speech Off.wav': '語音結束',
  r'C:\Windows\Media\Windows Notify.wav': 'Notify',
  r'C:\Windows\Media\Windows Ding.wav': 'Ding',
  r'C:\Windows\Media\chimes.wav': 'Chimes',
  r'C:\Windows\Media\chord.wav': 'Chord',
  r'C:\Windows\Media\tada.wav': 'Tada',
  r'C:\Windows\Media\Windows Background.wav': 'Background',
  r'C:\Windows\Media\Windows Foreground.wav': 'Foreground',
  r'C:\Windows\Media\Windows Balloon.wav': 'Balloon',
  r'C:\Windows\Media\Windows Notify System Generic.wav': 'System Generic',
  r'C:\Windows\Media\Windows Hardware Insert.wav': 'Hardware Insert',
  r'C:\Windows\Media\Windows Hardware Remove.wav': 'Hardware Remove',
  r'C:\Windows\Media\Windows Message Nudge.wav': 'Message Nudge',
};

class SoundService {
  final SharedPreferences _prefs;

  SoundService({required SharedPreferences prefs}) : _prefs = prefs;

  bool get soundEnabled =>
      _prefs.getBool(AppConstants.soundEnabledKey) ?? true;

  String get startSoundPath =>
      _prefs.getString(AppConstants.startSoundKey) ?? kDefaultStartSound;

  String get stopSoundPath =>
      _prefs.getString(AppConstants.stopSoundKey) ?? kDefaultStopSound;

  String get recordingStoppedSoundPath =>
      _prefs.getString(AppConstants.recordingStoppedSoundKey) ??
      kDefaultRecordingStoppedSound;

  Future<void> playStartSound() async {
    if (!soundEnabled) return;
    // _playWindows 會把殘留的 macOS 路徑對應成內建提示音
    await _play(startSoundPath);
  }

  Future<void> playStopSound() async {
    if (!soundEnabled) return;
    await _play(stopSoundPath);
  }

  Future<void> playCancelSound() async {
    if (!soundEnabled) return;
    await _play(kDefaultCancelSound);
  }

  /// 錄音真正停止（麥克風關閉）那一刻播，跟「文字準備好了」的 [playStopSound] 分開。
  Future<void> playRecordingStoppedSound() async {
    if (!soundEnabled) return;
    await _play(recordingStoppedSoundPath);
  }

  /// 播放任意路徑的音效（供設定頁預覽使用）
  Future<void> playPreview(String path) async {
    await _play(path);
  }

  /// Windows 端的媒體控制走原生 —— play/pause 是切換鍵，原生那邊會先用
  /// peak meter 確認真的有東西在出聲才按，並記住是不是自己按的，
  /// 沒暫停過就不會去恢復。
  static const _keyboardChannel = MethodChannel('com.zerotype.app/keyboard');

  /// 暫停背景音樂（macOS: Apple Music & Spotify；Windows: 媒體鍵）
  Future<void> pauseMusic() async {
    if (Platform.isWindows) {
      try {
        await _keyboardChannel.invokeMethod<void>('pauseMedia');
      } catch (_) {}
      return;
    }
    if (!Platform.isMacOS) return;
    const script = '''
      tell application "Music"
        if it is running then pause
      end tell
      tell application "Spotify"
        if it is running then pause
      end tell
    ''';
    await Process.run('osascript', ['-e', script]);
  }

  /// 恢復背景音樂
  ///
  /// notes: Windows 端刻意不做 —— 只暫停不自動恢復，要不要繼續聽由使用者決定。
  /// （媒體鍵是切換鍵，自動恢復還得記住「是不是自己按的」才不會誤觸發播放，
  /// 不恢復就連這個狀態都不必存在。）
  Future<void> resumeMusic() async {
    if (Platform.isWindows) return;
    if (!Platform.isMacOS) return;
    const script = '''
      tell application "Music"
        if it is running then play
      end tell
      tell application "Spotify"
        if it is running then play
      end tell
    ''';
    await Process.run('osascript', ['-e', script]);
  }

  static Future<void> _play(String path) async {
    if (Platform.isWindows) {
      await _playWindowsRepeated(path);
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await Process.run('afplay', [path]);
    } catch (_) {
      // 忽略音效錯誤
    }
  }

  /// 音效檔太短就重播頂到 [kMinSoundDuration]，見 [repeatCountFor]。
  static Future<void> _playWindowsRepeated(String path) async {
    final wavPath =
        path.toLowerCase().endsWith('.wav') ? path : kWindowsSounds[path];
    if (wavPath == null || !File(wavPath).existsSync()) {
      print('[SoundService] no Windows sound for: $path');
      return;
    }
    Duration? duration;
    try {
      duration = wavDuration(File(wavPath).readAsBytesSync());
    } catch (_) {
      duration = null;
    }
    final repeats = repeatCountFor(duration);
    for (var i = 0; i < repeats; i++) {
      _playWindows(wavPath);
      if (i < repeats - 1) await Future.delayed(duration!);
    }
  }

  /// 播放歷史紀錄的錄音檔（Windows）。跟音效走同一條 PlaySoundW，不外開播放器，
  /// 也不套用 [kMinSoundDuration] 的重播。回傳音檔長度讓呼叫端知道何時播完，
  /// 解析不出長度回 null。
  static Duration? playWavFile(String path) {
    if (!Platform.isWindows) return null;
    Duration? duration;
    try {
      duration = wavDuration(File(path).readAsBytesSync());
    } catch (_) {
      duration = null;
    }
    _playWindows(path);
    return duration;
  }

  /// 停掉 PlaySoundW 正在播的東西（同一時間只有一個，音效與回放共用）。
  static void stopWavFile() {
    if (!Platform.isWindows) return;
    _playSoundW(nullptr, 0, 0);
  }

  static final _playSoundW = DynamicLibrary.open('winmm.dll').lookupFunction<
      Int32 Function(Pointer<Utf16>, IntPtr, Uint32),
      int Function(Pointer<Utf16>, int, int)>('PlaySoundW');

  // SND_ASYNC 播放時路徑字串必須存活到播放結束，
  // 因此快取 native 字串不釋放（最多幾個路徑的固定成本）。
  static final Map<String, Pointer<Utf16>> _nativePathCache = {};

  static void _playWindows(String path) {
    // 設定存的是 macOS 音效路徑時，改播對應的 Windows 內建提示音
    final wavPath =
        path.toLowerCase().endsWith('.wav') ? path : kWindowsSounds[path];
    if (wavPath == null || !File(wavPath).existsSync()) {
      print('[SoundService] no Windows sound for: $path');
      return;
    }
    final native =
        _nativePathCache.putIfAbsent(wavPath, () => wavPath.toNativeUtf16());
    const sndAsync = 0x0001; // SND_ASYNC
    const sndNoDefault = 0x0002; // SND_NODEFAULT
    const sndFilename = 0x00020000; // SND_FILENAME
    _playSoundW(native, 0, sndAsync | sndNoDefault | sndFilename);
  }
}
