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

    // 目前門檻情境：Speech On.wav 實測約 836ms，900ms 門檻下該播 2 次
    test('836ms 音檔（Speech On.wav 實測值）在 900ms 門檻下重播 2 次', () {
      expect(
        repeatCountFor(const Duration(milliseconds: 836)),
        2,
      );
    });

    // 130ms 音檔在 900ms 門檻下理論要 7 次，但頂到上限 5
    test('130ms 音檔在 900ms 門檻下被上限頂在 5 次', () {
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
