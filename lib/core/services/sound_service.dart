import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';

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

/// Windows 內建語音提示音（對應 macOS 預設音效）
const Map<String, String> kWindowsSounds = {
  kDefaultStartSound: r'C:\Windows\Media\Speech On.wav',
  kDefaultStopSound: r'C:\Windows\Media\Speech Off.wav',
  kDefaultCancelSound: r'C:\Windows\Media\Speech Misrecognition.wav',
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
      _playWindows(path);
      return;
    }
    if (!Platform.isMacOS) return;
    try {
      await Process.run('afplay', [path]);
    } catch (_) {
      // 忽略音效錯誤
    }
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
