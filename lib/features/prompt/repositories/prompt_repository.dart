import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';

class PromptRepository {
  PromptRepository({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  Future<File> _getCustomPromptFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/SpeechToText_Custom.prompt');
  }

  Future<String> getDefaultSpeechPrompt() async {
    try {
      final content = await rootBundle.loadString('prompts/SpeechToText.prompt');
      return content.trim();
    } catch (e) {
      print('[PromptRepo] ERROR loading SpeechToText.prompt from assets: $e');
    }
    return '請將語音精確轉換成繁體中文，並依語意加上適當的標點符號。';
  }

  Future<String> getSpeechPrompt() async {
    try {
      final file = await _getCustomPromptFile();
      if (await file.exists()) {
        final content = (await file.readAsString()).trim();
        if (content.isNotEmpty) return content;
      }
    } catch (e) {
      print('[PromptRepo] Error reading custom prompt: $e');
    }
    return await getDefaultSpeechPrompt();
  }

  Future<String> saveSpeechPrompt(String prompt) async {
    final cleaned = prompt.trim();
    try {
      final file = await _getCustomPromptFile();
      await file.writeAsString(cleaned, flush: true);
    } catch (e) {
      print('[PromptRepo] Error saving custom prompt: $e');
    }
    await _prefs.setString(AppConstants.speechPromptKey, cleaned);
    return cleaned;
  }

  Future<String> resetSpeechPrompt() async {
    try {
      final file = await _getCustomPromptFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      print('[PromptRepo] Error deleting custom prompt: $e');
    }
    await _prefs.remove(AppConstants.speechPromptKey);
    return await getDefaultSpeechPrompt();
  }
}
