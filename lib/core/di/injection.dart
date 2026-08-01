import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sound_service.dart';
import '../services/speech_recognition_service.dart';
import '../services/hotkey_service.dart';
import '../services/tray_service.dart';
import '../../features/history/repositories/history_repository.dart';

// notes: 單一行程的桌面 app，top-level 單例就夠；測試從未 mock 這些服務，
// 需要注入點時再引入 provider
late final SharedPreferences appPrefs;
late final Dio dio;
late final SpeechRecognitionService speechService;
late final HotkeyService hotkeyService;
late final TrayService trayService;
late final SoundService soundService;
late final HistoryRepository historyRepository;

Future<void> configureDependencies() async {
  appPrefs = await SharedPreferences.getInstance();
  dio = Dio();
  speechService = SpeechRecognitionService(dio: dio);
  hotkeyService = HotkeyService(prefs: appPrefs);
  trayService = TrayService();
  soundService = SoundService(prefs: appPrefs);
  historyRepository = HistoryRepository();
}
