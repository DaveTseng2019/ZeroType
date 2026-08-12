import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:win32/win32.dart';

/// Whisper 系列模型的原生取樣率，送更高的沒有好處只是變大包
const int kRecordSampleRate = 16000;

/// 噪音門檻的分析音框長度
const int _kFrameMs = 20;

/// 噪音門檻強度預設值，見 [applyNoiseGate] 的 marginFactor
const double kDefaultNoiseGateStrength = 3.0;

typedef AmplitudeCallback = void Function(double amplitude);

/// Windows 目前預設錄音裝置的 endpoint id。
///
/// 「預設裝置」(eConsole) 和「預設通訊裝置」(eCommunications) 可以是不同的兩支麥克風 ——
/// 藍牙耳機常常只被指定成通訊裝置，所以兩個都回傳，由 UI 自己決定怎麼呈現。
/// 回傳的 id 跟 `listInputDevices()` 的 `InputDevice.id` 是同一組（都是 MMDevice endpoint id）。
///
/// notes: 只做 Windows；其他平台回 (null, null)，設定頁就只顯示「系統預設」。
({String? console, String? communications}) defaultInputDeviceIds() {
  if (!Platform.isWindows) return (console: null, communications: null);
  const eCapture = 1;
  const eConsole = 0;
  const eCommunications = 2;

  try {
    // COM 已由 windows/runner/main.cpp 的 CoInitializeEx 初始化過
    final enumerator = MMDeviceEnumerator.createInstance();

    String? idForRole(int role) {
      // win32 的慣例：配置一個 COMObject 當出參槽位，再直接包那個指標（不是 .value）
      final ppDevice = calloc<COMObject>();
      if (FAILED(
        enumerator.getDefaultAudioEndpoint(eCapture, role, ppDevice.cast()),
      )) {
        calloc.free(ppDevice); // 沒包成 IMMDevice，沒有 Finalizer 會來收
        return null; // 沒有可用的錄音裝置
      }

      // 包成 IUnknown 子類之後，記憶體與 refcount 由 win32 的 Finalizer 負責。
      // 這裡再自己 release()／free() 就是雙重釋放，會在之後某次 GC 讓整個程序無聲崩掉。
      final device = IMMDevice(ppDevice);
      final ppId = calloc<Pointer<Utf16>>();
      try {
        if (FAILED(device.getId(ppId))) return null;
        final id = ppId.value.toDartString();
        CoTaskMemFree(ppId.value.cast()); // 字串是 COM 配的，這個要自己還
        return id;
      } finally {
        calloc.free(ppId);
      }
    }

    return (
      console: idForRole(eConsole),
      communications: idForRole(eCommunications),
    );
  } catch (e) {
    print('[RecordingService] defaultInputDeviceIds failed: $e');
    return (console: null, communications: null);
  }
}

/// 一段 PCM16 的 RMS。chunk 可能落在奇數 byte offset，所以用 ByteData 讀。
double rmsOfPcm16(Uint8List pcm) {
  final count = pcm.lengthInBytes ~/ 2;
  if (count == 0) return 0;
  final bd = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    final s = bd.getInt16(i * 2, Endian.little);
    sum += s * s.toDouble();
  }
  return sqrt(sum / count);
}

/// 藍牙 HFP 協商期間麥克風送的是數位靜音（實測 RMS 0~7），
/// 接通後就算沒人講話也有底噪（某些耳機實測 200 以上）。20 落在中間。
///
/// notes: 門檻寫死，而且注定顧不了兩邊 —— 實測筆電內建麥克風的底噪只有 5~9，
/// 跟藍牙協商期的靜音（0~7）重疊。對這種低底噪麥克風，「偵測到聲音」等於「使用者開口了」。
///
/// notes: 「接通後一定有底噪」這個前提對帶 VAD 的耳機**不成立**。
/// 2026-08-03 實測 Sony WF-C510：接通後沒人講話時送的是精確的 0，而且是無限期的
/// （23 秒內 465/476 個 chunk 的 peak 完全為 0），就緒因此永遠不會觸發。
/// 這種耳機的「協商中」與「已接通但安靜」在音訊上完全無法區分，門檻訂多低都沒用。
/// 它們該把等待設 0：串流照收（開頭多約 1 秒靜音，無害），提示音改由第一個
/// 非數位靜音的 chunk 觸發，實測落在 831ms，比使用者開口早 2.3 秒。
const double kSilentChunkRms = 20;

/// 低於這個 RMS 視為沒有聲音訊號（數位靜音或環境底噪，不是有人在講話）。
///
/// 2026-08-04 實測（安靜辦公室、預設麥克風）：3 輪 5 秒純靜音錄音，非零音框
/// 最高只到 2.41；3 輪 5 秒語音錄音，講話的音框最低 11.75。10 曾經是這兩組的
/// 分界，但同一天另一組真實案例推翻了「音量能分辨好壞」的假設——
/// 幻覺輸出那筆錄音（avg RMS 204、max 3485）跟辨識正確那筆（avg 176、max 1872）
/// 幾乎是同一個量級，[hasAnySound] 的「單一音框超過門檻」邏輯本來就攔不住
/// 這種案例，見 [[zerotype-noise-gate-hallucination]] 的後續討論。
/// 拉到 100 是使用者要求的保守值，用來擋掉更明確的低品質音訊，
/// 不是這起幻覺案例的修法。
///
/// 2026-08-12 依使用者校正調到 150 —— 100 是「極安靜」，不是「有聲音」。
///
/// notes: 150 擋不住實際踩到的案例。同日安靜房間、預設麥克風、完全不出聲錄
/// 2.4 秒，未加增益的音框 RMS 最高 178；08-12 09:45 那筆吐出 podcast 開場白的
/// 幻覺錄音最高 365。[hasAnySound] 取的是「任何一個音框」，一次器物碰撞就過關，
/// 要擋住這類錄音門檻得拉到 500 以上，那又開始有吃掉小聲人聲的風險。
/// 真要修這條路得換判別方式（音框 RMS 的動態範圍），不是繼續往上加門檻。
///
/// 用來決定 onCaptureStart（提示音）何時觸發：沒開等待時，第一個超過此門檻的
/// chunk 就代表麥克風真的活了。也是 [hasAnySound] 判斥「整段都沒訊號」的門檻。
/// 不拿來當就緒判斷 —— 見 [MicReadyGate.accept]。
const double kDeadChunkRms = 150.0;

/// 要連續多久不靜音才算麥克風真的活了。
///
/// 實測 HFP 協商快完成時會有一下爆音：單一 chunk 衝過門檻，接著又靜音一整秒。
/// 只看一個 chunk 會誤判，提示音提早響，使用者的頭幾個字還是掉在死區裡。
const Duration kMicReadyHold = Duration(milliseconds: 300);

/// 判斷麥克風是否已經真的在送聲音（藍牙 HFP 協商完成的偵測）。
///
/// 抽成一個類別純粹是為了能測 —— 這段判斷藏在 stream listener 裡已經錯過兩次。
class MicReadyGate {
  MicReadyGate({required this.deadline, this.hold = kMicReadyHold});

  /// 等不到就放行的保險絲
  final DateTime deadline;
  final Duration hold;

  /// 已經累積、但還沒確認的候選片段。就緒時要補進錄音，否則開頭會被自己吃掉。
  final List<Uint8List> pending = [];
  DateTime? _loudSince;

  /// 回 true 代表就緒；此時 [chunk] 已經放進 [pending]，呼叫端直接倒出來即可。
  bool accept(Uint8List chunk, DateTime now) {
    final rms = rmsOfPcm16(chunk);
    final loud = rms >= kSilentChunkRms;
    if (loud) {
      _loudSince ??= now;
      pending.add(chunk);
    } else {
      // 中途斷掉就重算，爆音不能累積成 300ms
      _loudSince = null;
      pending.clear();
    }

    final held = _loudSince != null && now.difference(_loudSince!) >= hold;
    // notes: 保險絲燒斷就算就緒，不再看訊號內容。曾經改成「全零就繼續等」，
    // 但帶降噪的耳機接通後沒人講話時本來就送全零（實測 WF-C510 可以送滿 23 秒），
    // 那條規則會讓就緒永遠不觸發，變成非得先開口才會開始錄。
    // 現在改回時間到就放行 —— 等待值訂在切換完成之後（耳機預設 1 秒，
    // 實測 HFP 切換約 0.93 秒）就夠了，不必再去猜訊號。
    if (!held && now.isBefore(deadline)) return false;

    if (!loud) pending.add(chunk); // 逾時放行：這個 chunk 還沒進候選
    return true;
  }
}

/// [pcm] 裡有沒有任何一個音框不是數位靜音。
///
/// 只問「有沒有聲音」，不管長短大小 —— 完全空白的錄音送去辨識，chat 型模型會
/// 憑空編出一整段內容（實測 gemini-3-flash、2.5-flash、2.5-pro 對純靜音分別編出
/// 會議議程、訪談節目、電影台詞，換模型或改提示詞都壓不住）。
///
/// notes: 曾經把門檻訂成「RMS ≥ 100 累計滿 500ms」，那是在噪音門檻把音訊挖空、
/// 誤以為模型無藥可救的時候加的。根因修掉之後那個門檻只剩副作用 ——
/// 連單字級的短句（「好」約 200~300ms）都會被擋掉。
bool hasAnySound(Uint8List pcm, {int sampleRate = kRecordSampleRate}) {
  final frameSamples = sampleRate * _kFrameMs ~/ 1000;
  final total = pcm.lengthInBytes ~/ 2;
  final bd = ByteData.sublistView(pcm);
  for (var f = 0; f < total ~/ frameSamples; f++) {
    var sum = 0.0;
    final start = f * frameSamples;
    for (var i = start; i < start + frameSamples; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      sum += s * s.toDouble();
    }
    if (sqrt(sum / frameSamples) >= kDeadChunkRms) return true;
  }
  return false;
}

/// 人聲該有的動態範圍下限：音框 RMS 的 p90 ÷ p10。
///
/// 2026-08-12 實測 13 筆真實錄音（同一支麥克風、同一個房間）：正常說話 8 筆
/// 落在 6.2~11.6，只有噪音的 5 筆落在 1.4~2.9。4 落在中間，兩邊各有兩倍餘裕。
const double kMinDynamicRange = 4.0;

/// 短於這個長度就不做動態範圍判斷 —— 音框太少時百分位不穩，寧可送出去。
const Duration kDynamicsMinLength = Duration(seconds: 1);

/// [pcm] 有沒有人聲該有的高低起伏。
///
/// 講話一定有停頓，最安靜的音框會落回底噪，p90 跟 p10 因此拉得很開；只有底噪的
/// 錄音則是一條平的線。用比值而不是絕對音量有兩個好處：
///
/// 1. 同一段錄音自己跟自己比，[applyGain] 的倍率、麥克風本身音量大小都會約掉，
///    不必為每支麥克風校正。絕對門檻（[kDeadChunkRms]）做不到這件事 ——
///    實測純噪音錄音的最大音框 RMS 落在 178~365，跟小聲的人聲根本分不開。
/// 2. 敲擊聲騙不過去：它推高 p90，但沒人講話時 p10 還是貼在底噪上。
///    實測有器物碰撞的那筆噪音錄音仍然只有 2.9。
///
/// notes: 會失效的是「吵雜環境講話」—— 底噪把 p10 頂高，比值掉下來，真的講話
/// 可能被誤擋。目前樣本只有 13 筆、單一麥克風單一環境。誤擋時調降
/// [kMinDynamicRange]，紀錄頁的訊息會指名是這條擋的。
///
/// notes: 百分位只取非零音框。錄音開頭那 200ms 是數位零（麥克風還沒送資料），
/// 短錄音時它們會佔到一成以上，把 p10 壓成 0，比值就變成無限大、形同關閉。
bool hasSpeechDynamics(Uint8List pcm, {int sampleRate = kRecordSampleRate}) {
  final frameSamples = sampleRate * _kFrameMs ~/ 1000;
  final frameCount = pcm.lengthInBytes ~/ 2 ~/ frameSamples;
  if (frameCount * _kFrameMs < kDynamicsMinLength.inMilliseconds) return true;

  final bd = ByteData.sublistView(pcm);
  final rms = <double>[];
  for (var f = 0; f < frameCount; f++) {
    var sum = 0.0;
    final start = f * frameSamples;
    for (var i = start; i < start + frameSamples; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      sum += s * s.toDouble();
    }
    final v = sqrt(sum / frameSamples);
    if (v > 0) rms.add(v);
  }
  if (rms.length < 10) return true;

  rms.sort();
  final p10 = rms[rms.length ~/ 10];
  final p90 = rms[rms.length * 9 ~/ 10];
  return p10 <= 0 || p90 / p10 >= kMinDynamicRange;
}

/// 精簡模式判定「有人在講話」的振幅門檻。振幅是 [_emitAmplitude] 正規化過的
/// 0~1（-50 dBFS → 0，-5 dBFS → 1），0.15 約等於 -43 dBFS。
///
/// notes: 寫死沒有 UI。這是實體世界的旋鈕 —— 藍牙耳機整段音量偏小，
/// 話還沒講完就被切要調低，講完了不停要調高。要調的是這裡跟 [kQuietHold]。
const double kSpeechAmplitude = 0.15;

/// 精簡模式要連續安靜多久才算「講完了」
const Duration kQuietHold = Duration(milliseconds: 1500);

/// 要連續多久超過門檻才算「真的開口了」。
///
/// 只看單一取樣有跨過門檻是不夠的：小聲的麥克風（藍牙耳機實測峰值只有滿刻度的
/// 6%）底噪本來就在門檻上下跳，使用者還沒開口就會有一兩框衝過去。那之後只要
/// 安靜滿 [kQuietHold]，錄音就在他開口前被收掉，送出去的是兩秒環境噪音 ——
/// 模型對這種音訊必定憑空編一整段出來（2026-08-12 實測，編出一段 podcast 開場白）。
///
/// notes: 取樣是每 100ms 一次，300ms 等於要連續 4 框。單字短句（「好。」）
/// 可能撐不到而不會自動停，那時退回按熱鍵停止；反過來早停會整段話丟失又貼上
/// 幻覺文字，代價大得多。
const Duration kMinSpeech = Duration(milliseconds: 300);

/// 精簡模式的自動停止判斷：真的開口過，而且已經安靜滿 [hold]。
///
/// 「開口過」是必要條件 —— 沒有它的話，使用者按下熱鍵後還沒開口的那段安靜
/// 就會直接把錄音收掉。抽成類別純粹是為了能測（同 [MicReadyGate]）。
class QuietGate {
  QuietGate({
    this.threshold = kSpeechAmplitude,
    this.hold = kQuietHold,
    this.minSpeech = kMinSpeech,
  });

  final double threshold;
  final Duration hold;
  final Duration minSpeech;

  bool _heardSpeech = false;
  DateTime? _loudSince;
  DateTime? _quietSince;

  /// 回 true 代表可以停止錄音了
  bool accept(double amplitude, DateTime now) {
    if (amplitude >= threshold) {
      _loudSince ??= now;
      if (now.difference(_loudSince!) >= minSpeech) _heardSpeech = true;
      _quietSince = null;
      return false;
    }
    _loudSince = null; // 斷了就重算，底噪的零星跨越湊不成一次開口
    if (!_heardSpeech) return false;
    _quietSince ??= now;
    return now.difference(_quietSince!) >= hold;
  }
}

/// 從 [devices] 找出 [deviceId] 指定的裝置。
/// 回 null 代表用系統預設 —— 沒指定，或指定的裝置已拔除／藍牙已斷線。
InputDevice? resolveInputDevice(List<InputDevice> devices, String? deviceId) {
  if (deviceId == null || deviceId.isEmpty) return null;
  for (final d in devices) {
    if (d.id == deviceId) return d;
  }
  return null;
}

/// 把 PCM16 加上 44 bytes 的 WAV header。
Uint8List buildWav(
  Uint8List pcm, {
  int sampleRate = kRecordSampleRate,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;

  final out = BytesBuilder();
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk 大小
  header.setUint16(20, 1, Endian.little); // 1 = PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  out.add(header.buffer.asUint8List());
  out.add(pcm);
  return out.takeBytes();
}

/// 噪音門檻：把明顯屬於底噪的音框壓下去。
///
/// 門檻取「音框 RMS 的第 10 百分位（噪音底）× [marginFactor]」，不是整段平均值 ——
/// 以人聲為主的錄音平均值本身就落在人聲區，拿它當門檻會把氣音和句尾整段吃掉。
///
/// notes: 固定衰減沒有 attack/release 包絡，門檻邊緣可能有輕微頓挫；
/// 若聽得出來再改成音框間線性內插增益。
Uint8List applyNoiseGate(
  Uint8List pcm, {
  int sampleRate = kRecordSampleRate,
  double marginFactor = kDefaultNoiseGateStrength,
  double attenuation = 0.1,
}) {
  final frameSamples = sampleRate * _kFrameMs ~/ 1000;
  final totalSamples = pcm.lengthInBytes ~/ 2;
  if (totalSamples < frameSamples * 2) return pcm;

  // 同 _emitAmplitude：串流 chunk 可能落在奇數 offset。錄音只有單一 chunk 時
  // BytesBuilder.takeBytes() 會原樣回傳它，Int16List.view 就會拋 RangeError。
  final aligned = pcm.offsetInBytes.isEven ? pcm : Uint8List.fromList(pcm);
  final samples = Int16List.fromList(
    Int16List.view(aligned.buffer, aligned.offsetInBytes, totalSamples),
  );

  final frameCount = totalSamples ~/ frameSamples;
  final rms = List<double>.filled(frameCount, 0);
  for (var f = 0; f < frameCount; f++) {
    var sum = 0.0;
    final start = f * frameSamples;
    for (var i = start; i < start + frameSamples; i++) {
      sum += samples[i] * samples[i].toDouble();
    }
    rms[f] = sqrt(sum / frameSamples);
  }

  final sorted = List<double>.from(rms)..sort();
  // 用 (n-1) 而不是 n 取名次：短錄音（或幾乎沒有停頓的錄音）只有一兩個安靜音框時，
  // n×0.1 會落到人聲上，門檻被人聲拉高就會反過來吃掉小聲的字。
  final noiseFloor = sorted[((sorted.length - 1) * 0.1).floor()];
  // 下限擋住「整段幾乎數位靜音」時門檻歸零、什麼都過得去的情況
  final threshold = max(noiseFloor * marginFactor, 1.0);

  for (var f = 0; f < frameCount; f++) {
    if (rms[f] >= threshold) continue;
    final start = f * frameSamples;
    for (var i = start; i < start + frameSamples; i++) {
      samples[i] = (samples[i] * attenuation).round();
    }
  }
  return samples.buffer.asUint8List();
}

/// 自動增益：把整段錄音的峰值拉到接近滿刻度。藍牙耳機（尤其 HFP）麥克風輸出
/// 普遍偏小聲，固定的辨識模型輸入音量門檻因此常常吃不到訊號。
///
/// 只放大不衰減 —— 峰值已經夠大聲的錄音（gain ≤ 1）不處理。[maxGain] 頂住
/// 增益上限，避免安靜片段的底噪被一起放大到爆音。
Uint8List applyGain(
  Uint8List pcm, {
  double targetPeak = 0.85,
  double maxGain = 8.0,
}) {
  final totalSamples = pcm.lengthInBytes ~/ 2;
  if (totalSamples == 0) return pcm;

  final aligned = pcm.offsetInBytes.isEven ? pcm : Uint8List.fromList(pcm);
  final samples = Int16List.fromList(
    Int16List.view(aligned.buffer, aligned.offsetInBytes, totalSamples),
  );

  var peak = 0;
  for (final s in samples) {
    final abs = s.abs();
    if (abs > peak) peak = abs;
  }
  if (peak == 0) return pcm;

  final gain = min(targetPeak * 32767 / peak, maxGain);
  if (gain <= 1.0) return pcm;

  for (var i = 0; i < totalSamples; i++) {
    samples[i] = (samples[i] * gain).round().clamp(-32768, 32767);
  }
  return samples.buffer.asUint8List();
}

class RecordingService {
  RecordingService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  String? _currentFilePath;
  StreamSubscription<Uint8List>? _streamSubscription;
  BytesBuilder? _pcm;
  /// 0 代表不過濾。見 [startRecording] 的 noiseGateStrength。
  double _noiseGateStrength = 0;
  DateTime _lastAmplitudeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// [stopRecording] 回 null 的原因，給呼叫端寫進紀錄頁。
  /// 「麥克風沒送資料」跟「只錄到噪音」是兩回事，訊息一樣的話問題查不下去。
  String? lastDiscardReason;

  Future<bool> checkPermission() async {
    return _recorder.hasPermission();
  }

  Future<bool> requestPermission() async {
    // hasPermission() on macOS will trigger the system dialog if not yet decided
    return _recorder.hasPermission();
  }

  /// 系統可用的錄音輸入裝置；失敗時回空清單（設定頁只會顯示「系統預設」）
  Future<List<InputDevice>> listInputDevices() async {
    try {
      return await _recorder.listInputDevices();
    } catch (e) {
      print('[RecordingService] listInputDevices failed: $e');
      return const [];
    }
  }

  Future<void> startRecording({
    AmplitudeCallback? onAmplitude,
    String? deviceId,
    /// 噪音門檻強度，0 代表不過濾（預設）。
    double noiseGateStrength = 0,
    Duration warmupTimeout = Duration.zero,
    /// 真正開始收音的那一刻（提示音在這裡響，才是「可以講了」）
    void Function()? onCaptureStart,
  }) async {
    final dir = await getTemporaryDirectory();
    // The sandbox cache dir may not exist when app-sandbox is disabled in debug.
    // Creating it ensures the output file can actually be written.
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = '${dir.path}/zerotype_$timestamp.wav';
    _noiseGateStrength = noiseGateStrength;

    final device = (deviceId == null || deviceId.isEmpty)
        ? null
        : resolveInputDevice(await listInputDevices(), deviceId);
    if (device == null && deviceId != null && deviceId.isNotEmpty) {
      print('[RecordingService] input device gone, falling back: $deviceId');
    }

    print(
      '[RecordingService] starting at $_currentFilePath '
      '(device: ${device?.label ?? 'default'}, '
      'gate: ${noiseGateStrength > 0 ? 'x$noiseGateStrength' : 'off'}, '
      'warmupTimeout: ${warmupTimeout.inMilliseconds}ms)',
    );

    // 收 PCM 自己寫 WAV，才有機會在送出前套噪音門檻；
    // 順便擺脫 Windows Media Foundation AAC 編碼器只吃 44.1/48 kHz 的限制。
    _pcm = BytesBuilder(copy: false);
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kRecordSampleRate,
        numChannels: 1,
        device: device,
      ),
    );

    _lastAmplitudeAt = DateTime.fromMillisecondsSinceEpoch(0);
    // 藍牙耳機麥克風要等 Windows 把連線從 A2DP 切到 HFP，協商期間送來的是純靜音。
    // 串流照樣立刻開（協商就是被開麥克風觸發的），只是這段資料丟掉不收。
    //
    // 等的是「真的有聲音進來」而不是固定秒數：實測同一支耳機協商時間在 1.5~6.0 秒之間跳，
    // 固定延遲不是太短就是白等。[warmupTimeout] 只當保險絲，避免麥克風真的沒訊號時無限等。
    final openedAt = DateTime.now();
    final gate = warmupTimeout > Duration.zero
        ? MicReadyGate(deadline: openedAt.add(warmupTimeout))
        : null;
    var waiting = gate != null;
    // [onCaptureStart] 跟等不等待無關，只代表「訊號真的進來了」，而且只發一次。
    //
    // notes: 不能改成開串流時就發 —— 提示音是在這個 callback 裡播的，而藍牙從
    // A2DP 切到 HFP 的那一下會把正在播的聲音整個吃掉（實測要 1.5~9.6 秒，
    // 靠固定延遲賭不贏）。等到收得到資料才播，才聽得見。
    var announced = false;
    void announce(Duration waited) {
      announced = true;
      print('[RecordingService] capture started after '
          '${waited.inMilliseconds}ms');
      onCaptureStart?.call();
    }

    _streamSubscription = stream.listen((chunk) {
      if (waiting) {
        if (!gate!.accept(chunk, DateTime.now())) return; // 還在協商，丟掉
        waiting = false;
        announce(DateTime.now().difference(openedAt));
        for (final c in gate.pending) {
          _pcm?.add(c);
        }
        gate.pending.clear();
        if (onAmplitude != null) _emitAmplitude(chunk, onAmplitude);
        return; // 這個 chunk 已經在 pending 裡進去了
      }
      if (!announced && rmsOfPcm16(chunk) >= kDeadChunkRms) {
        announce(DateTime.now().difference(openedAt));
      }
      _pcm?.add(chunk);
      if (onAmplitude != null) _emitAmplitude(chunk, onAmplitude);
    }, onError: (Object e) => print('[RecordingService] stream error: $e'));
  }

  /// 波形用的音量，直接從 PCM 算，不必再走 MethodChannel 輪詢。
  void _emitAmplitude(Uint8List chunk, AmplitudeCallback onAmplitude) {
    final now = DateTime.now();
    if (now.difference(_lastAmplitudeAt).inMilliseconds < 100) return;
    _lastAmplitudeAt = now;

    final count = chunk.lengthInBytes ~/ 2;
    if (count == 0) return;
    // 串流 chunk 是大 buffer 的切片，offsetInBytes 可能是奇數 —— Int16List.view 會拋
    // RangeError。ByteData.getInt16 沒有對齊限制，也不用複製。
    final bd = ByteData.sublistView(chunk);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      sum += s * s.toDouble();
    }
    final rms = sqrt(sum / count);
    final dbfs = rms <= 0 ? -160.0 : 20 * (log(rms / 32768) / ln10);
    // Map practical speech range (-50 dBFS silence → -5 dBFS loud) to 0–1
    onAmplitude(((dbfs + 50) / 45).clamp(0.0, 1.0));
  }

  Future<String?> stopRecording() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;

    final isRec = await _recorder.isRecording();
    print('[RecordingService] calling _recorder.stop()... isRecording=$isRec');
    if (isRec) {
      try {
        await _recorder.stop().timeout(const Duration(seconds: 8));
      } catch (e) {
        print('[RecordingService] _recorder.stop() error/timeout: $e');
      }
    }

    lastDiscardReason = null;
    final pcm = _pcm?.takeBytes() ?? Uint8List(0);
    _pcm = null;
    if (pcm.isEmpty || _currentFilePath == null) {
      print('[RecordingService] no audio captured');
      lastDiscardReason = '麥克風沒有送出任何資料';
      return null;
    }

    final processed = _noiseGateStrength > 0
        ? applyNoiseGate(pcm, marginFactor: _noiseGateStrength)
        : pcm;

    // 整段都是數位靜音就不要送辨識 —— 模型會憑空編一段出來（見 [hasAnySound]）
    if (!hasAnySound(processed)) {
      print('[RecordingService] silence only, discarding ${pcm.length} bytes');
      lastDiscardReason = '整段沒有任何聲音訊號';
      return null;
    }

    // 有聲音但沒有人聲的高低起伏（見 [hasSpeechDynamics]）—— 送出去只會換回
    // 一段憑空編的內容，還要付錢
    if (!hasSpeechDynamics(processed)) {
      print('[RecordingService] flat dynamics, discarding ${pcm.length} bytes');
      lastDiscardReason = '只錄到底噪，聽不出人聲的高低起伏'
          '（動態範圍低於 $kMinDynamicRange）';
      return null;
    }

    final boosted = applyGain(processed);
    await File(_currentFilePath!).writeAsBytes(buildWav(boosted));
    print(
      '[RecordingService] wrote ${pcm.length} bytes PCM → $_currentFilePath',
    );
    return _currentFilePath;
  }

  Future<void> cancelRecording() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _pcm = null;

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
