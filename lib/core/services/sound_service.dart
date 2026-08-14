import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';
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
/// 貼上失敗時播。Windows 端對應「災難性失敗」那顆系統音效。
const String kDefaultPasteFailedSound = '/System/Library/Sounds/Funk.aiff';
/// 麥克風真正關閉那一刻播的音效（跟 [kDefaultStopSound] 不同 —— 那個是「文字準備好了」）。
const String kDefaultRecordingStoppedSound = '/System/Library/Sounds/Tink.aiff';

/// 提示音期間主音量的下限（百分比）。使用者實測的耳機聽閾：主音量 20 以下
/// 就聽不見提示音。0 = 不干預系統音量。
const int kDefaultMinMasterVolumePercent = 20;

/// Windows 內建語音提示音（對應 macOS 預設音效）
///
/// 「錄音結束」配 Speech Off、「辨識完成」配 Notify —— 麥克風開關用同一組
/// Speech On/Off 才成對，文字好了是另一回事，用通知音。
const Map<String, String> kWindowsSounds = {
  kDefaultStartSound: r'C:\Windows\Media\Speech On.wav',
  kDefaultStopSound: r'C:\Windows\Media\Windows Notify.wav',
  kDefaultCancelSound: r'C:\Windows\Media\Speech Misrecognition.wav',
  kDefaultRecordingStoppedSound: r'C:\Windows\Media\Speech Off.wav',
  kDefaultPasteFailedSound: r'C:\Windows\Media\Windows Critical Stop.wav',
};

const Map<String, String> kWindowsSoundLabels = {
  r'C:\Windows\Media\Speech On.wav': '語音開始',
  r'C:\Windows\Media\Speech Off.wav': '語音結束',
  r'C:\Windows\Media\Windows Critical Stop.wav': '災難性失敗',
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

const String _iidAudioEndpointVolume = '{5CDF2C82-841E-4546-9722-0CF74078229A}';

/// 系統主音量。win32 5.15 沒有 IAudioEndpointVolume 的綁定，這裡只手接出用得到的
/// 兩個 vtable 槽位，索引依 endpointvolume.h 的宣告順序（IUnknown 佔 0~2）。
///
/// notes: 手寫 vtable 索引，介面順序變了會叫錯函式。win32 套件補上這個介面就換掉。
class _EndpointVolume extends IUnknown {
  _EndpointVolume(super.ptr);

  /// vtable[7] SetMasterVolumeLevelScalar
  int setMasterVolumeLevelScalar(double level, Pointer<GUID> eventContext) =>
      (ptr.ref.vtable + 7)
          .cast<
              Pointer<
                  NativeFunction<
                      Int32 Function(Pointer, Float, Pointer<GUID>)>>>()
          .value
          .asFunction<int Function(Pointer, double, Pointer<GUID>)>()(
        ptr.ref.lpVtbl,
        level,
        eventContext,
      );

  /// vtable[9] GetMasterVolumeLevelScalar
  int getMasterVolumeLevelScalar(Pointer<Float> pLevel) => (ptr.ref.vtable + 9)
      .cast<Pointer<NativeFunction<Int32 Function(Pointer, Pointer<Float>)>>>()
      .value
      .asFunction<int Function(Pointer, Pointer<Float>)>()(
    ptr.ref.lpVtbl,
    pLevel,
  );
}

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

  String get pasteFailedSoundPath =>
      _prefs.getString(AppConstants.pasteFailedSoundKey) ??
      kDefaultPasteFailedSound;

  /// 提示音期間主音量的下限（0~1）；0 = 不干預系統音量。見 [_boostMaster]。
  double get minMasterVolume =>
      (_prefs.getInt(AppConstants.minMasterVolumeKey) ??
              kDefaultMinMasterVolumePercent) /
          100;

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

  /// 貼上沒送進去時播，預設是系統的「災難性失敗」。
  Future<void> playPasteFailedSound() async {
    if (!soundEnabled) return;
    await _play(pasteFailedSoundPath);
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

  Future<void> _play(String path) async {
    if (Platform.isWindows) {
      await _playWindowsRepeated(path, minMasterVolume);
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
  static Future<void> _playWindowsRepeated(
      String path, double minMasterVolume) async {
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
    _boostMaster(minMasterVolume, (duration ?? kMinSoundDuration) * repeats);
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

  /// ZeroType 在「音量混音器」裡的分軌音量。系統主音量是使用者的選擇，不動它；
  /// 但自己這一軌被拉低或靜音時提示音會整個聽不到，而那不是使用者調過的東西 ——
  /// Windows 會把分軌音量記在登錄檔裡跨次啟動留著，一次誤觸就永遠聽不到。
  /// 要真正靜音請關掉設定頁的音效開關。
  ///
  /// null 代表取不到（沒有輸出裝置、COM 失敗），那就照舊播，不擋流程。
  static ISimpleAudioVolume? _sessionVolume;
  static bool _sessionVolumeTried = false;

  /// 把自身分軌拉回滿格並解除靜音。取不到介面就什麼都不做。
  static void _ensureAudible() {
    if (!_sessionVolumeTried) {
      _sessionVolumeTried = true;
      _sessionVolume = _openSessionVolume();
    }
    final volume = _sessionVolume;
    if (volume == null) return;
    volume.setMute(FALSE, nullptr);
    volume.setMasterVolume(1.0, nullptr);
  }

  /// 取得本行程的預設音訊 session 的音量介面。
  /// 慣例與 [defaultInputDeviceIds] 相同：配置 COMObject 當出參槽位，包成
  /// IUnknown 子類之後記憶體與 refcount 由 win32 的 Finalizer 負責，
  /// 這裡再自己 release()／free() 就是雙重釋放，會在之後某次 GC 無聲崩掉。
  /// 目前的預設播放裝置；沒有可用裝置或 COM 失敗回 null。
  static IMMDevice? _defaultRenderDevice() {
    const eRender = 0;
    const eConsole = 0;
    try {
      // COM 已由 windows/runner/main.cpp 的 CoInitializeEx 初始化過
      final enumerator = MMDeviceEnumerator.createInstance();
      final ppDevice = calloc<COMObject>();
      if (FAILED(
        enumerator.getDefaultAudioEndpoint(eRender, eConsole, ppDevice.cast()),
      )) {
        calloc.free(ppDevice); // 沒包成 IMMDevice，沒有 Finalizer 會來收
        return null; // 沒有可用的播放裝置
      }
      return IMMDevice(ppDevice);
    } catch (e) {
      print('[SoundService] no default render device: $e');
      return null;
    }
  }

  static ISimpleAudioVolume? _openSessionVolume() {
    try {
      final device = _defaultRenderDevice();
      if (device == null) return null;

      final ppManager = calloc<COMObject>();
      final iid = convertToIID(IID_IAudioSessionManager);
      final hr = device.activate(
        iid,
        CLSCTX_ALL,
        nullptr,
        ppManager.cast(),
      );
      calloc.free(iid);
      if (FAILED(hr)) {
        calloc.free(ppManager);
        return null;
      }
      final manager = IAudioSessionManager(ppManager);

      // AudioSessionGuid = null 就是本行程的預設 session，PlaySoundW 走的也是它
      final ppVolume = calloc<COMObject>();
      if (FAILED(manager.getSimpleAudioVolume(nullptr, 0, ppVolume.cast()))) {
        calloc.free(ppVolume);
        return null;
      }
      return ISimpleAudioVolume(ppVolume);
    } catch (e) {
      print('[SoundService] session volume unavailable: $e');
      return null;
    }
  }

  /// 被我們頂高之前的主音量；null 代表現在沒有在頂。
  static double? _savedMaster;
  static Timer? _restoreTimer;

  /// 主音量小於 [minMaster] 就在 [playback] 這段期間頂到 [minMaster]，之後還原。
  /// [minMaster] 為 0 代表關閉這個功能。
  ///
  /// 只用在提示音（[_playWindowsRepeated]）—— 歷史錄音回放是使用者自己按的，
  /// 聽不清楚他會自己調音量，不必替他動系統設定。
  ///
  /// notes: 主音量被靜音時不解除靜音。分軌靜音多半是誤觸，整台靜音是刻意的。
  static void _boostMaster(double minMaster, Duration playback) {
    if (minMaster <= 0) return;
    final endpoint = _endpointVolume();
    if (endpoint == null) return;
    final level = calloc<Float>();
    try {
      if (_savedMaster == null) {
        if (FAILED(endpoint.getMasterVolumeLevelScalar(level))) return;
        if (level.value >= minMaster) return;
        _savedMaster = level.value;
      }
    } finally {
      calloc.free(level);
    }
    endpoint.setMasterVolumeLevelScalar(minMaster, nullptr);
    // 連續播放時只延後還原時間，不會把「原本的音量」覆寫成頂高後的值
    _restoreTimer?.cancel();
    _restoreTimer = Timer(
      playback + const Duration(milliseconds: 300),
      _restoreMaster,
    );
  }

  static void _restoreMaster() {
    _restoreTimer = null;
    final saved = _savedMaster;
    _savedMaster = null;
    if (saved == null) return;
    _endpointVolume()?.setMasterVolumeLevelScalar(saved, nullptr);
  }

  static _EndpointVolume? _endpoint;
  static bool _endpointTried = false;

  static _EndpointVolume? _endpointVolume() {
    if (_endpointTried) return _endpoint;
    _endpointTried = true;
    final ppDevice = _defaultRenderDevice();
    if (ppDevice == null) return null;
    final ppVolume = calloc<COMObject>();
    final iid = convertToIID(_iidAudioEndpointVolume);
    final hr = ppDevice.activate(iid, CLSCTX_ALL, nullptr, ppVolume.cast());
    calloc.free(iid);
    if (FAILED(hr)) {
      calloc.free(ppVolume);
      return null;
    }
    return _endpoint = _EndpointVolume(ppVolume);
  }

  static void _playWindows(String path) {
    // 設定存的是 macOS 音效路徑時，改播對應的 Windows 內建提示音
    final wavPath =
        path.toLowerCase().endsWith('.wav') ? path : kWindowsSounds[path];
    if (wavPath == null || !File(wavPath).existsSync()) {
      print('[SoundService] no Windows sound for: $path');
      return;
    }
    _ensureAudible();
    final native =
        _nativePathCache.putIfAbsent(wavPath, () => wavPath.toNativeUtf16());
    const sndAsync = 0x0001; // SND_ASYNC
    const sndNoDefault = 0x0002; // SND_NODEFAULT
    const sndFilename = 0x00020000; // SND_FILENAME
    _playSoundW(native, 0, sndAsync | sndNoDefault | sndFilename);
  }
}
