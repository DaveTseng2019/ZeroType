import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/services/sound_service.dart';

void main() {
  const headphones = '{0.0.0.00000000}.{headphones}';
  const speakers = '{0.0.0.00000000}.{speakers}';

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('沒有任何設定時用預設值', () async {
    final prefs = await prefsWith({});
    expect(minMasterVolumePercentFor(prefs, headphones),
        kDefaultMinMasterVolumePercent);
  });

  test('沒設定過的裝置沿用舊版不分裝置的值', () async {
    final prefs = await prefsWith({AppConstants.minMasterVolumeKey: 35});
    expect(minMasterVolumePercentFor(prefs, headphones), 35);
    expect(minMasterVolumePercentFor(prefs, speakers), 35);
  });

  test('每個裝置各自的值互不影響', () async {
    final prefs = await prefsWith({AppConstants.minMasterVolumeKey: 35});
    await prefs.setInt(minMasterVolumeKeyFor(headphones), 15);
    await prefs.setInt(minMasterVolumeKeyFor(speakers), 0);
    expect(minMasterVolumePercentFor(prefs, headphones), 15);
    expect(minMasterVolumePercentFor(prefs, speakers), 0);
  });

  test('取不到裝置時用不分裝置的鍵', () async {
    expect(minMasterVolumeKeyFor(null), AppConstants.minMasterVolumeKey);
    expect(minMasterVolumeKeyFor(''), AppConstants.minMasterVolumeKey);
    final prefs = await prefsWith({AppConstants.minMasterVolumeKey: 40});
    expect(minMasterVolumePercentFor(prefs, null), 40);
  });
}
