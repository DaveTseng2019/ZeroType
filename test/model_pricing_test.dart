import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/constants/model_pricing.dart';

void main() {
  test('同一個模型在不同服務商用各自的價目表', () {
    // 1000 音訊 + 1000 文字輸入、100 輸出
    final openai = calculateCost('openai', 'gpt-4o-transcribe', 2000, 100,
        audioInputTokens: 1000);
    final azure = calculateCost('azure', 'gpt-4o-transcribe', 2000, 100,
        audioInputTokens: 1000);
    // OpenAI 不分音訊：2000 × 2.5 + 100 × 10
    expect(openai, closeTo(0.006, 1e-12));
    // Azure 音訊另計：1000 × 6 + 1000 × 2.5 + 100 × 10
    expect(azure, closeTo(0.0095, 1e-12));
  });

  test('沒有音訊明細時全部照一般輸入價', () {
    expect(calculateCost('azure', 'gpt-4o-transcribe', 2000, 100),
        closeTo(0.006, 1e-12));
  });

  test('音訊 token 不會超過總輸入', () {
    expect(calculateCost('azure', 'gpt-4o-transcribe', 100, 0,
            audioInputTokens: 500),
        closeTo(0.0006, 1e-12));
  });

  test('價目表沒有的組合回 null', () {
    expect(calculateCost('local', 'gpt-4o-transcribe', 100, 10), isNull);
    expect(calculateCost('azure', 'whisper', 100, 10), isNull);
    expect(calculateCost('openai', 'gpt-4o-transcribe', null, 10), isNull);
  });
}
