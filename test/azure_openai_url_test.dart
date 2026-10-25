import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';

void main() {
  const want = 'https://res.openai.azure.com/openai/deployments/gpt-4o-transcribe'
      '/audio/transcriptions?api-version=$kAzureApiVersion';

  test('只填主機時組出部署路徑', () {
    expect(azureTranscriptionUrl('https://res.openai.azure.com', 'gpt-4o-transcribe'), want);
    expect(azureTranscriptionUrl(' https://res.openai.azure.com/ ', 'gpt-4o-transcribe'), want);
  });

  test('已帶 /openai 或 /openai/v1 時不重複', () {
    expect(azureTranscriptionUrl('https://res.openai.azure.com/openai', 'gpt-4o-transcribe'), want);
    expect(azureTranscriptionUrl('https://res.openai.azure.com/openai/v1/', 'gpt-4o-transcribe'), want);
  });

  test('完整位址原樣使用', () {
    expect(azureTranscriptionUrl(want, 'other'), want);
  });

  test('金鑰測試用 v1 models 路徑', () {
    expect(azureModelsUrl('https://res.openai.azure.com/'),
        'https://res.openai.azure.com/openai/v1/models');
  });

  test('沒填端點時丟出錯誤', () {
    expect(() => azureTranscriptionUrl('', 'gpt-4o-transcribe'), throwsException);
    expect(() => azureModelsUrl(null), throwsException);
  });
}
