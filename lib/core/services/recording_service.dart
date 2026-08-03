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
/// 接通後就算沒人講話也有底噪（實測 200 以上）。20 落在中間，兩邊都有一個數量級的餘裕。
///
/// notes: 門檻寫死，而且注定顧不了兩邊 —— 實測筆電內建麥克風的底噪只有 5~9，
/// 跟藍牙協商期的靜音（0~7）重疊。對這種低底噪麥克風，「偵測到聲音」等於「使用者開口了」，
/// 所以等待麥克風就緒只該對藍牙開啟，其他裝置設 0（設定頁的說明有寫）。
const double kSilentChunkRms = 20;

/// 低於這個 RMS 視為「驅動還沒把訊號接上」的數位靜音。
///
/// 真的在收音的麥克風一定有底噪（實測最安靜的內建麥克風也有 5~9），
/// 全零只會出現在裝置還沒開始送資料的時候。分成兩個門檻是因為
/// [kSilentChunkRms] 那條逾時保險絲是為了救「底噪很低」的麥克風，
/// 但它不該讓全零的死區也放行 —— 實測這支裝置會送 9.5 秒的全零，
/// 比 8 秒的保險絲還久，剩下的 1.5 秒就這樣被錄進檔案開頭。
const double kDeadChunkRms = 1.0;

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
    // 保險絲燒斷也不收全零：那是還沒接上的訊號，不是「安靜的麥克風」。
    // 收了只會讓檔案開頭多一段死區，提示音也會在麥克風真的活過來之前就響。
    if (!held && (now.isBefore(deadline) || rms < kDeadChunkRms)) return false;

    if (!loud) pending.add(chunk); // 逾時放行：這個 chunk 還沒進候選
    return true;
  }
}

/// 「像人聲」的音框門檻與最短累計時長。
///
/// 空音訊送進 chat 型語音模型，它會憑空編出一整段內容 —— 實測
/// gemini-3-flash-preview、gemini-2.5-flash、gemini-2.5-pro 對純靜音分別編出
/// 會議議程、訪談節目、電影台詞，換模型解決不了，只能不要送出去。
///
/// 門檻用實測校準：正常錄音在 RMS 100 以上有 980～1720ms；一筆麥克風幾乎沒收到
/// 東西的只有 360ms，模型對它連跑三次編出三段不同的內容。500ms 落在中間。
///
/// notes: 寧可誤擋也不要誤放 —— 被擋下來使用者看得到「沒有偵測到語音」，重錄就好；
/// 放行的幻覺卻是一段像模像樣的文字，直接貼進文件裡，不一定會被發現。
/// 代價是單字級的短句（「好」約 200~300ms）會被擋掉。
const double kSpeechRms = 100;
const Duration kMinSpeech = Duration(milliseconds: 500);

/// [pcm] 裡 RMS 達到 [kSpeechRms] 的音框累計時長。
Duration speechDuration(Uint8List pcm, {int sampleRate = kRecordSampleRate}) {
  final frameSamples = sampleRate * _kFrameMs ~/ 1000;
  final total = pcm.lengthInBytes ~/ 2;
  final bd = ByteData.sublistView(pcm);
  var frames = 0;
  for (var f = 0; f < total ~/ frameSamples; f++) {
    var sum = 0.0;
    final start = f * frameSamples;
    for (var i = start; i < start + frameSamples; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      sum += s * s.toDouble();
    }
    if (sqrt(sum / frameSamples) >= kSpeechRms) frames++;
  }
  return Duration(milliseconds: frames * _kFrameMs);
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

class RecordingService {
  RecordingService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  String? _currentFilePath;
  StreamSubscription<Uint8List>? _streamSubscription;
  BytesBuilder? _pcm;
  /// 0 代表不過濾。見 [startRecording] 的 noiseGateStrength。
  double _noiseGateStrength = 0;
  DateTime _lastAmplitudeAt = DateTime.fromMillisecondsSinceEpoch(0);

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

    final pcm = _pcm?.takeBytes() ?? Uint8List(0);
    _pcm = null;
    if (pcm.isEmpty || _currentFilePath == null) {
      print('[RecordingService] no audio captured');
      return null;
    }

    final processed = _noiseGateStrength > 0
        ? applyNoiseGate(pcm, marginFactor: _noiseGateStrength)
        : pcm;

    // 沒有人聲就不要送去辨識 —— 模型會憑空編一段出來（見 [kSpeechRms]）。
    // 回 null 走的是既有的「沒錄到東西」路徑，不另外開一種狀態。
    final speech = speechDuration(processed);
    if (speech < kMinSpeech) {
      print('[RecordingService] no speech (${speech.inMilliseconds}ms), '
          'discarding ${pcm.length} bytes');
      return null;
    }

    await File(_currentFilePath!).writeAsBytes(buildWav(processed));
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
