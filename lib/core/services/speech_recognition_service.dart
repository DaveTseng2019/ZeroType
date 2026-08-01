import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

typedef TranscriptionResult = ({
  String text,
  int? inputTokens,
  int? outputTokens,
});

class SpeechRecognitionService {
  SpeechRecognitionService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<TranscriptionResult> transcribe({
    required String audioFilePath,
    required String apiKey,
    required String provider,
    required String model,
    required String prompt,
    String? customEndpoint,
  }) async {
    print('[SpeechRecognition] Transcribing with $provider ($model)...');

    switch (provider) {
      case 'openai':
        return _transcribeWithOpenAI(
          audioFilePath: audioFilePath,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          customEndpoint: customEndpoint,
        );
      case 'gemini':
        return _transcribeWithGemini(
          audioFilePath: audioFilePath,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          customEndpoint: customEndpoint,
        );
      case 'openrouter':
        return _transcribeWithOpenRouter(
          audioFilePath: audioFilePath,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          customEndpoint: customEndpoint,
        );
      default:
        throw Exception('不支援的語音辨識服務商：$provider');
    }
  }

  Future<TranscriptionResult> _transcribeWithOpenAI({
    required String audioFilePath,
    required String apiKey,
    required String model,
    required String prompt,
    String? customEndpoint,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFilePath,
        filename: File(audioFilePath).uri.pathSegments.last,
      ),
      'model': model,
      'response_format': 'json',
      if (prompt.isNotEmpty) 'prompt': prompt,
    });

    final url = (customEndpoint != null && customEndpoint.isNotEmpty)
        ? customEndpoint
        : 'https://api.openai.com/v1/audio/transcriptions';

    final response = await _dio.post<dynamic>(
      url,
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
    );

    // Parse JSON response to extract text and token usage
    Map<String, dynamic>? data;
    if (response.data is Map<String, dynamic>) {
      data = response.data as Map<String, dynamic>;
    } else if (response.data is String) {
      try {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } catch (_) {
        return (
          text: (response.data as String).trim(),
          inputTokens: null,
          outputTokens: null,
        );
      }
    }

    final text = (data?['text'] as String? ?? '').trim();
    final usageMap = data?['usage'] as Map<String, dynamic>?;
    final inputTokens = usageMap?['input_tokens'] as int?;
    final outputTokens = usageMap?['output_tokens'] as int?;

    return (text: text, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  Future<TranscriptionResult> _transcribeWithGemini({
    required String audioFilePath,
    required String apiKey,
    required String model,
    required String prompt,
    String? customEndpoint,
  }) async {
    print('[Gemini] Start direct transcription: $audioFilePath');

    final fileToUpload = File(audioFilePath);
    if (!fileToUpload.existsSync()) {
      throw Exception('找不到音檔：$audioFilePath');
    }

    final mimeType = audioFilePath.endsWith('.wav')
        ? 'audio/wav'
        : (audioFilePath.endsWith('.mp3') ? 'audio/mpeg' : 'audio/mp4');
    final audioBytes = await fileToUpload.readAsBytes();
    final base64Audio = base64Encode(audioBytes);

    final finalPrompt =
        prompt.isEmpty ? 'Generate a transcript of the speech.' : prompt;

    final url = (customEndpoint != null && customEndpoint.isNotEmpty)
        ? '$customEndpoint/$model:generateContent'
        : 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'contents': [
            {
              'parts': [
                {'text': finalPrompt},
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Audio,
                  }
                },
              ],
            },
          ],
        },
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final candidates = response.data?['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Gemini 轉譯失敗：無候選回應');
      }

      final parts = candidates[0]['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini 轉譯失敗：內容為空');
      }

      final text = (parts[0]['text'] as String? ?? '').trim();

      // Extract token usage from usageMetadata
      final usageMeta =
          response.data?['usageMetadata'] as Map<String, dynamic>?;
      final inputTokens = usageMeta?['promptTokenCount'] as int?;
      final outputTokens = usageMeta?['candidatesTokenCount'] as int?;

      print('[Gemini] Success! tokens: in=$inputTokens out=$outputTokens');
      return (text: text, inputTokens: inputTokens, outputTokens: outputTokens);
    } on DioException catch (e) {
      print('[Gemini] DioException: ${e.message}');
      print('[Gemini] Status: ${e.response?.statusCode}');
      rethrow;
    }
  }

  Future<TranscriptionResult> _transcribeWithOpenRouter({
    required String audioFilePath,
    required String apiKey,
    required String model,
    required String prompt,
    String? customEndpoint,
  }) async {
    print('[OpenRouter] Start transcription: $audioFilePath');

    final fileToUpload = File(audioFilePath);
    if (!fileToUpload.existsSync()) {
      throw Exception('找不到音檔：$audioFilePath');
    }

    // OpenRouter 沒有 /audio/transcriptions 端點，
    // 音訊要以 base64 走 chat/completions 的 input_audio。
    final ext = audioFilePath.split('.').last.toLowerCase();
    final format = const {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'}
            .contains(ext)
        ? ext
        : 'wav';
    final base64Audio = base64Encode(await fileToUpload.readAsBytes());

    final finalPrompt = prompt.isEmpty
        ? 'Generate a transcript of the speech. Output only the transcript.'
        : prompt;

    final url = (customEndpoint != null && customEndpoint.isNotEmpty)
        ? customEndpoint
        : 'https://openrouter.ai/api/v1/chat/completions';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': finalPrompt},
                {
                  'type': 'input_audio',
                  'input_audio': {
                    'data': base64Audio,
                    'format': format,
                  },
                },
              ],
            },
          ],
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final choices = response.data?['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('OpenRouter 轉譯失敗：無候選回應');
      }

      final text =
          (choices[0]['message']?['content'] as String? ?? '').trim();

      final usage = response.data?['usage'] as Map<String, dynamic>?;
      final inputTokens = usage?['prompt_tokens'] as int?;
      final outputTokens = usage?['completion_tokens'] as int?;

      // 上游供應商決定 input_audio 吃不吃得到。實測同一個 model id 被路由到不吃音訊的
      // 供應商時，音訊會被默默丟掉：prompt_tokens 不再隨音檔長度增加，模型只看到文字。
      final upstream = response.data?['provider'];
      final audioBytes = base64Audio.length * 3 ~/ 4;
      print('[OpenRouter] Success! provider=$upstream '
          'tokens: in=$inputTokens out=$outputTokens '
          '(audio ${audioBytes ~/ 1024}KB / ${format})');
      return (text: text, inputTokens: inputTokens, outputTokens: outputTokens);
    } on DioException catch (e) {
      print('[OpenRouter] DioException: ${e.message}');
      print('[OpenRouter] Status: ${e.response?.statusCode}');
      rethrow;
    }
  }

  /// 純文字第二段：轉錄完成後用字典校正拼寫。
  /// 只支援 chat 型服務商（gemini／openrouter）；openai 走 whisper prompt 偏置。
  Future<TranscriptionResult> correctTranscript({
    required String apiKey,
    required String provider,
    required String model,
    required String prompt,
    String? customEndpoint,
  }) async {
    switch (provider) {
      case 'gemini':
        final url = (customEndpoint != null && customEndpoint.isNotEmpty)
            ? '$customEndpoint/$model:generateContent'
            : 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
          },
          options: Options(
            headers: {
              'x-goog-api-key': apiKey,
              'Content-Type': 'application/json',
            },
          ),
        );
        final candidates = response.data?['candidates'] as List?;
        final parts = (candidates != null && candidates.isNotEmpty)
            ? (candidates[0]['content']?['parts'] as List?)
            : null;
        final text = (parts != null && parts.isNotEmpty)
            ? (parts[0]['text'] as String? ?? '').trim()
            : '';
        final usageMeta =
            response.data?['usageMetadata'] as Map<String, dynamic>?;
        return (
          text: text,
          inputTokens: usageMeta?['promptTokenCount'] as int?,
          outputTokens: usageMeta?['candidatesTokenCount'] as int?,
        );
      case 'openrouter':
        final url = (customEndpoint != null && customEndpoint.isNotEmpty)
            ? customEndpoint
            : 'https://openrouter.ai/api/v1/chat/completions';
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: {
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
        );
        final choices = response.data?['choices'] as List?;
        final text = (choices != null && choices.isNotEmpty)
            ? ((choices[0]['message']?['content'] as String? ?? '').trim())
            : '';
        final usage = response.data?['usage'] as Map<String, dynamic>?;
        return (
          text: text,
          inputTokens: usage?['prompt_tokens'] as int?,
          outputTokens: usage?['completion_tokens'] as int?,
        );
      default:
        throw Exception('不支援文字校正的服務商：$provider');
    }
  }
}
