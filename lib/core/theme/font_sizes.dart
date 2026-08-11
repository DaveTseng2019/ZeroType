import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';

final fontSizesProvider =
    NotifierProvider<FontSizesController, FontSizes>(FontSizesController.new);

class FontSizesController extends Notifier<FontSizes> {
  @override
  FontSizes build() {
    final jsonStr = appPrefs.getString(AppConstants.fontSizesKey);
    if (jsonStr == null) return FontSizes.defaults;
    try {
      return FontSizes.fromJson(jsonStr);
    } catch (_) {
      return FontSizes.defaults;
    }
  }

  /// 拋出例外時代表 JSON 格式錯誤，呼叫端（設定頁）要自己接住並提示使用者。
  Future<void> setFromJson(String jsonStr) async {
    final parsed = FontSizes.fromJson(jsonStr);
    await appPrefs.setString(AppConstants.fontSizesKey, jsonStr);
    state = parsed;
  }

  Future<void> resetToDefault() async {
    await appPrefs.remove(AppConstants.fontSizesKey);
    state = FontSizes.defaults;
  }
}

/// 設定頁的四級文字大小，可在設定頁以 JSON 編輯，存於 shared_preferences。
///
/// 對照畫面：pageTitle =「設定」、sectionHeader =「快捷鍵」、
/// itemTitle =「全局錄音快捷鍵」、description = 項目下方的說明文字。
class FontSizes {
  const FontSizes({
    this.pageTitle = 24,
    this.sectionHeader = 22,
    this.itemTitle = 18,
    this.description = 15,
  });

  /// 頁面標題（例如「設定」）
  final double pageTitle;
  final double sectionHeader;
  final double itemTitle;

  /// 項目說明文字（例如每個設定項下方的灰色說明）大小
  final double description;

  static const defaults = FontSizes();

  /// 任何字體大小都不可以小於這個值
  static const minSize = 10.0;

  factory FontSizes.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    double read(String key, double fallback) {
      final raw = (map[key] as num?)?.toDouble() ?? fallback;
      if (raw < minSize) {
        throw FormatException('$key 不可小於 $minSize');
      }
      return raw;
    }

    return FontSizes(
      pageTitle: read('pageTitle', defaults.pageTitle),
      sectionHeader: read('sectionHeader', defaults.sectionHeader),
      itemTitle: read('itemTitle', defaults.itemTitle),
      description: read('description', defaults.description),
    );
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'pageTitle': pageTitle,
        'sectionHeader': sectionHeader,
        'itemTitle': itemTitle,
        'description': description,
      });
}
