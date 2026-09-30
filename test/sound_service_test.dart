import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/sound_service.dart';

/// 組一個最小合法 WAV：RIFF/WAVE + fmt (16 bytes) + data，byteRate 與 dataSize
/// 自訂，方便斷言 [wavDuration] 算出的長度。
Uint8List makeWav({required int byteRate, required int dataSize}) {
  final bytes = BytesBuilder();
  void u32(int v, {bool big = false}) {
    final bd = ByteData(4);
    big ? bd.setUint32(0, v, Endian.big) : bd.setUint32(0, v, Endian.little);
    bytes.add(bd.buffer.asUint8List());
  }

  void u16(int v) {
    final bd = ByteData(2);
    bd.setUint16(0, v, Endian.little);
    bytes.add(bd.buffer.asUint8List());
  }

  u32(0x52494646, big: true); // 'RIFF'
  u32(36 + dataSize); // chunk size，測試不驗證這個值
  u32(0x57415645, big: true); // 'WAVE'

  u32(0x666d7420, big: true); // 'fmt '
  u32(16); // fmt chunk size
  u16(1); // PCM
  u16(1); // mono
  u32(byteRate ~/ 2); // sampleRate（16-bit mono 時 byteRate = sampleRate*2）
  u32(byteRate);
  u16(2); // blockAlign
  u16(16); // bitsPerSample

  u32(0x64617461, big: true); // 'data'
  u32(dataSize);
  bytes.add(Uint8List(dataSize));

  return bytes.takeBytes();
}

void main() {
  group('wavDuration', () {
    test('16kHz 16-bit mono、1 秒資料算出 1000ms', () {
      const byteRate = 16000 * 2;
      final wav = makeWav(byteRate: byteRate, dataSize: byteRate);
      expect(wavDuration(wav), const Duration(milliseconds: 1000));
    });

    test('Windows 內建提示音等級的短檔（130ms）', () {
      const byteRate = 22050 * 2;
      final wav = makeWav(byteRate: byteRate, dataSize: (byteRate * 0.13).round());
      expect(wavDuration(wav)!.inMilliseconds, closeTo(130, 2));
    });

    test('非 WAV（沒有 RIFF/WAVE 頭）回 null', () {
      expect(wavDuration(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])), isNull);
    });

    test('太短、連 header 都不到回 null', () {
      expect(wavDuration(Uint8List(4)), isNull);
    });
  });

  group('wavAudibleDuration（錄音開頭要切多長）', () {
    // 16kHz mono：每個 20ms 音框 320 個取樣，依 [levels] 逐框填入同一個振幅
    Uint8List wavWithFrames(List<int> levels) {
      const sampleRate = 16000;
      final wav = makeWav(byteRate: sampleRate * 2, dataSize: levels.length * 640);
      final bd = ByteData.sublistView(wav);
      for (var f = 0; f < levels.length; f++) {
        for (var i = 0; i < 320; i++) {
          bd.setInt16(44 + (f * 320 + i) * 2, levels[f], Endian.little);
        }
      }
      return wav;
    }

    // 切到殘響結束就會吃掉使用者聽到「叮」就開口的第一個字；
    // 殘響比峰值低 20 dB 以上，錄進去也壓不過人聲
    test('只算到最後一個在峰值 −20 dB 以內的音框，殘響不算', () {
      // 3 框響（60ms）＋ 1 框 −14 dB ＋ 10 框 −30 dB 的殘響
      final wav = wavWithFrames([10000, 10000, 10000, 2000, ...List.filled(10, 300)]);
      expect(wavAudibleDuration(wav), const Duration(milliseconds: 80));
    });

    test('非 WAV 回 null，呼叫端就不切', () {
      expect(wavAudibleDuration(Uint8List.fromList(List.filled(16, 1))), isNull);
    });

    // 預設提示音的實際檔案。檔長 836ms，聽得到的部分約 300ms。
    // 2026-10-01 實測：聽到提示音就刻意馬上開口，人聲最早出現在錄音的 1100ms。
    // 切除量＝320ms 延遲＋這個值，超過 400 就逼近那條線；回到用檔長切（1276ms）
    // 已經證實會吃掉開頭的字
    test('Speech On.wav 聽得到的長度遠短於檔長',
        skip: !File(r'C:\Windows\Media\Speech On.wav').existsSync(), () {
      final bytes = File(r'C:\Windows\Media\Speech On.wav').readAsBytesSync();
      final audible = wavAudibleDuration(bytes)!;
      expect(audible.inMilliseconds, lessThan(400));
      expect(audible.inMilliseconds, greaterThan(100));
    });
  });

  group('repeatCountFor', () {
    test('長度未知就當作已經夠長，不重播', () {
      expect(repeatCountFor(null), 1);
    });

    test('已經比門檻長就不重播', () {
      expect(repeatCountFor(const Duration(milliseconds: 1000)), 1);
    });

    test('剛好等於門檻不重播', () {
      expect(repeatCountFor(kMinSoundDuration), 1);
    });

    // 開始提示音每多播一次，錄音開頭就要多切掉一份（見 trimLeadingPcm）。
    // 門檻訂在 800ms 就是為了讓預設的 Speech On.wav 只播一次；這條斷言破了
    // 代表切掉的長度又變回兩倍，使用者會抱怨開頭的字被吃掉。
    test('836ms 音檔（Speech On.wav 實測值）在 800ms 門檻下只播 1 次', () {
      expect(
        repeatCountFor(const Duration(milliseconds: 836)),
        1,
      );
    });

    // 130ms 音檔在 800ms 門檻下理論要 7 次，但頂到上限 5
    test('130ms 音檔在 800ms 門檻下被上限頂在 5 次', () {
      expect(
        repeatCountFor(const Duration(milliseconds: 130)),
        5,
      );
    });

    test('極短音檔（10ms）被上限頂在 5 次，不會連環爆炸', () {
      expect(
        repeatCountFor(const Duration(milliseconds: 10)),
        5,
      );
    });

    test('0 或負長度視為未知，不重播', () {
      expect(repeatCountFor(Duration.zero), 1);
    });
  });
}
