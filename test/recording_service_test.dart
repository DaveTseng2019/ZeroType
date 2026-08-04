import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:zero_type/core/services/recording_service.dart';

/// 產生 [frames] 個 20ms 音框，每框振幅由 [amplitudes] 指定
Uint8List pcmFrames(List<int> amplitudes) {
  const frameSamples = kRecordSampleRate * 20 ~/ 1000;
  final samples = Int16List(amplitudes.length * frameSamples);
  var i = 0;
  for (final amp in amplitudes) {
    for (var n = 0; n < frameSamples; n++, i++) {
      // 方波：每個取樣的絕對值都等於 amp，RMS 也就是 amp，斷言好寫
      samples[i] = n.isEven ? amp : -amp;
    }
  }
  return samples.buffer.asUint8List();
}

int frameRms(Uint8List pcm, int frameIndex) {
  const frameSamples = kRecordSampleRate * 20 ~/ 1000;
  final samples = Int16List.view(pcm.buffer, pcm.offsetInBytes,
      pcm.lengthInBytes ~/ 2);
  var sum = 0.0;
  final start = frameIndex * frameSamples;
  for (var i = start; i < start + frameSamples; i++) {
    sum += samples[i] * samples[i].toDouble();
  }
  return sqrt(sum / frameSamples).round();
}

void main() {
  const builtIn = InputDevice(id: 'mic-0', label: '內建麥克風');
  const headset = InputDevice(id: 'bt-1', label: '藍牙耳機 (Hands-Free)');

  group('resolveInputDevice', () {
    test('沒指定裝置時用系統預設', () {
      expect(resolveInputDevice([builtIn, headset], null), isNull);
      expect(resolveInputDevice([builtIn, headset], ''), isNull);
    });

    test('指定的裝置存在就選它', () {
      expect(resolveInputDevice([builtIn, headset], 'mic-0'), builtIn);
    });

    // 藍牙斷線後 id 還留在設定裡；不退回預設的話錄音會直接啟動失敗
    test('指定的裝置已消失時退回系統預設', () {
      expect(resolveInputDevice([builtIn], 'bt-1'), isNull);
      expect(resolveInputDevice([], 'mic-0'), isNull);
    });
  });

  // 等待麥克風就緒靠這個門檻分辨「HFP 還在協商」和「麥克風活了」。
  // 判錯任一邊都會讓使用者的第一句話消失，實測值就寫在斷言裡當護欄。
  group('rmsOfPcm16 與靜音門檻', () {
    test('HFP 協商期間的數位靜音低於門檻', () {
      // 實測協商期間每 0.5 秒的 RMS 是 0~7
      for (final amp in [0, 1, 4, 7]) {
        expect(rmsOfPcm16(pcmFrames([amp])), lessThan(kSilentChunkRms));
      }
    });

    test('接通後的底噪與人聲高於門檻', () {
      // 實測底噪 200 起跳、人聲 600~1200
      for (final amp in [200, 665, 1226]) {
        expect(rmsOfPcm16(pcmFrames([amp])), greaterThan(kSilentChunkRms));
      }
    });

    test('空 chunk 回 0，不會除以零', () {
      expect(rmsOfPcm16(Uint8List(0)), 0);
    });

    test('落在奇數 byte offset 也算得出來', () {
      final pcm = pcmFrames([1000]);
      final padded = Uint8List(pcm.length + 1)..setRange(1, pcm.length + 1, pcm);
      final odd = Uint8List.sublistView(padded, 1);
      expect(odd.offsetInBytes.isOdd, isTrue);
      expect(rmsOfPcm16(odd), closeTo(1000, 1));
    });
  });

  // 完全空白的錄音送去辨識，模型會憑空編出一整段內容（實測三個模型對純靜音
  // 各自編出不同的假逐字稿）。這裡只問「有沒有聲音」，不問長短。
  group('hasAnySound', () {
    test('純數位靜音不送出', () {
      expect(hasAnySound(pcmFrames(List.filled(50, 0))), isFalse);
    });

    test('只要有一框有訊號就送出 —— 短到單字也要送', () {
      // 49 框靜音 + 1 框人聲（20ms），舊的 500ms 門檻會把這種擋掉
      expect(
        hasAnySound(pcmFrames([...List.filled(49, 0), 500])),
        isTrue,
      );
      // 高於 kDeadChunkRms(100) 才算有聲音
      expect(hasAnySound(pcmFrames(List.filled(10, 120))), isTrue);
    });

    test('低於 kDeadChunkRms(100) 的音框不算有聲音', () {
      // 2026-08-04 實測：幻覺案例(avg 204/max 3485)跟辨識正確案例(avg 176/max 1872)
      // 幾乎同量級，這個門檻攔不住那組真實案例，只是使用者要求的保守值。
      expect(hasAnySound(pcmFrames(List.filled(10, 90))), isFalse);
    });
  });

  group('MicReadyGate', () {
    final t0 = DateTime(2026, 7, 30, 10, 0, 0);
    final farDeadline = t0.add(const Duration(seconds: 30));
    // 20ms 一框，湊滿 300ms 需要 15 框；用一框當一個 chunk 好算時間
    Uint8List chunk(int amp) => pcmFrames([amp]);

    test('單一爆音不算就緒 —— 這就是提示音早響一秒的那個 bug', () {
      final gate = MicReadyGate(deadline: farDeadline);
      // 協商中的爆音：一個 chunk 很大聲，接著又回到數位靜音
      expect(gate.accept(chunk(3000), t0), isFalse);
      expect(gate.accept(chunk(0), t0.add(const Duration(milliseconds: 20))),
          isFalse);
      // 爆音的候選也要丟掉，不能累積
      expect(gate.pending, isEmpty);
    });

    test('連續 300ms 有聲才就緒，候選片段一併帶出', () {
      final gate = MicReadyGate(deadline: farDeadline);
      var now = t0;
      // 前 15 次落在 0~280ms，都還不到 300ms
      for (var i = 0; i < 15; i++) {
        expect(gate.accept(chunk(500), now), isFalse, reason: '第 $i 框就緒太早');
        now = now.add(const Duration(milliseconds: 20));
      }
      // 第 16 次剛好落在 300ms
      expect(gate.accept(chunk(500), now), isTrue);
      // 開頭這 300ms 是真的人聲，必須補回錄音，否則等於自己吃掉第一個字
      expect(gate.pending.length, 16);
    });

    test('中途斷掉要重算，不能把兩段爆音湊成 300ms', () {
      final gate = MicReadyGate(deadline: farDeadline);
      var now = t0;
      for (var i = 0; i < 10; i++) {
        gate.accept(chunk(500), now);
        now = now.add(const Duration(milliseconds: 20));
      }
      gate.accept(chunk(0), now); // 斷了
      now = now.add(const Duration(milliseconds: 20));
      for (var i = 0; i < 10; i++) {
        expect(gate.accept(chunk(500), now), isFalse, reason: '斷掉後應重新計時');
        now = now.add(const Duration(milliseconds: 20));
      }
    });

    test('逾時就放行底噪很低的麥克風，並且不吞掉當下這個 chunk', () {
      final gate = MicReadyGate(deadline: t0.add(const Duration(seconds: 1)));
      expect(gate.accept(chunk(6), t0), isFalse);
      // 保險絲燒斷：內建麥克風的底噪(5~9)永遠跨不過 kSilentChunkRms，不能無限等
      expect(gate.accept(chunk(6), t0.add(const Duration(seconds: 2))), isTrue);
      expect(gate.pending.length, 1);
    });

    test('逾時就算就緒，全零也放行 —— 否則帶降噪的耳機永遠等不到', () {
      final gate = MicReadyGate(deadline: t0.add(const Duration(seconds: 1)));
      expect(gate.accept(chunk(0), t0), isFalse);
      // 實測 WF-C510 接通後沒人講話可以送滿 23 秒的全零。
      // 曾經改成「全零就繼續等」，結果就緒永遠不觸發，非得先開口才會開始錄。
      expect(gate.accept(chunk(0), t0.add(const Duration(seconds: 2))), isTrue);
      expect(gate.pending.length, 1);
    });
  });

  group('buildWav', () {
    // header 寫錯 API 會直接退回「無法解析的音檔」，且錯誤訊息不會指向這裡
    test('產生可解析的 44-byte PCM16 header', () {
      final pcm = pcmFrames([1000, 1000]);
      final wav = buildWav(pcm);
      final view = ByteData.view(wav.buffer);

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(view.getUint32(4, Endian.little), 36 + pcm.length);
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), kRecordSampleRate);
      expect(view.getUint32(28, Endian.little), kRecordSampleRate * 2);
      expect(view.getUint16(34, Endian.little), 16);
      expect(view.getUint32(40, Endian.little), pcm.length);
      expect(wav.length, 44 + pcm.length);
    });
  });

  group('applyNoiseGate', () {
    // 門檻若改用整段平均值，人聲框會被誤殺 —— 這組斷言就是在守這件事
    test('壓掉底噪框，保留人聲框', () {
      // 8 框底噪(200) + 2 框人聲(6000)：噪音底=200，門檻=600
      final pcm = pcmFrames([200, 200, 200, 200, 200, 200, 200, 200, 6000, 6000]);
      final gated = applyNoiseGate(pcm);

      expect(frameRms(gated, 0), closeTo(20, 2)); // 200 × 0.1
      expect(frameRms(gated, 7), closeTo(20, 2));
      expect(frameRms(gated, 8), 6000); // 人聲原樣通過
      expect(frameRms(gated, 9), 6000);
    });

    test('人聲佔多數時仍以噪音底為準，不吃掉小聲的字', () {
      // 只有 1 框底噪：第 10 百分位仍落在底噪，門檻不會被人聲拉高
      final pcm = pcmFrames([150, 3000, 3000, 3000, 800, 3000, 3000, 3000, 3000, 3000]);
      final gated = applyNoiseGate(pcm);

      expect(frameRms(gated, 0), closeTo(15, 2)); // 底噪被壓
      expect(frameRms(gated, 4), 800); // 小聲的字保留
      expect(frameRms(gated, 1), 3000);
    });

    // 實機抓到的 bug：record 的串流 chunk 是大 buffer 的切片，offsetInBytes 是奇數，
    // Int16List.view 會拋 RangeError。單一 chunk 的錄音會直接走到這裡。
    test('輸入落在奇數 byte offset 也不會拋 RangeError', () {
      final pcm = pcmFrames([200, 200, 200, 200, 200, 200, 200, 200, 6000, 6000]);
      final padded = Uint8List(pcm.length + 1)..setRange(1, pcm.length + 1, pcm);
      final odd = Uint8List.sublistView(padded, 1);
      expect(odd.offsetInBytes.isOdd, isTrue);

      final gated = applyNoiseGate(odd);
      expect(frameRms(gated, 0), closeTo(20, 2));
      expect(frameRms(gated, 8), 6000);
    });

    // 設定頁的「濾除強度」滑桿就是這個參數；它若沒接到門檻上，滑桿等於裝飾品
    test('強度越大門檻越高，壓掉的音框越多', () {
      // 底噪 200 → 強度 3.0 門檻 600（只壓底噪）、強度 6.0 門檻 1200（連 800 也壓）
      final pcm = pcmFrames([200, 200, 200, 200, 200, 200, 200, 200, 800, 6000]);

      final weak = applyNoiseGate(pcm, marginFactor: 3.0);
      expect(frameRms(weak, 8), 800); // 小聲的字留著

      final strong = applyNoiseGate(pcm, marginFactor: 6.0);
      expect(frameRms(strong, 8), closeTo(80, 2)); // 800 × 0.1，被壓掉
      expect(frameRms(strong, 9), 6000); // 人聲仍然通過
    });

    test('太短的音訊原樣回傳', () {
      final tiny = pcmFrames([500]);
      expect(applyNoiseGate(tiny), same(tiny));
      expect(applyNoiseGate(Uint8List(0)).length, 0);
    });
  });
}
