import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/controllers/zero_type_controller.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/router/router_provider.dart';
import 'core/services/hotkey_service.dart';
import 'core/services/tray_service.dart';
import 'core/state/zero_type_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/history/domain/repositories/history_repository.dart';
import 'shared/widgets/recording_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initWindowManager();
  await configureDependencies();
  await _initLaunchAtStartup();
  runApp(const ProviderScope(child: ZeroTypeApp()));
}

Future<void> _initWindowManager() async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(900, 650),
    minimumSize: Size(700, 500),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'ZeroType',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    // 攔截關閉事件,改為隱藏到系統匣(見 onWindowClose)
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> _initLaunchAtStartup() async {
  final packageInfo = await PackageInfo.fromPlatform();
  launchAtStartup.setup(
    appName: packageInfo.appName,
    appPath: Platform.resolvedExecutable,
    packageName: packageInfo.packageName,
  );
}

class ZeroTypeApp extends ConsumerWidget {
  const ZeroTypeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final appRouter = ref.watch(appRouterProvider);
    
    return MaterialApp.router(
      title: 'ZeroType',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter.config(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _AppInitializer(
        child: Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const RecordingOverlay(),
          ],
        ),
      ),
    );
  }
}

class _AppInitializer extends ConsumerStatefulWidget {
  const _AppInitializer({required this.child});
  final Widget child;

  @override
  ConsumerState<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends ConsumerState<_AppInitializer>
    with WindowListener {
  final _hotkeyService = getIt<HotkeyService>();
  final _trayService = getIt<TrayService>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _hotkeyService.initialize();
    _hotkeyService.setCallback(_onHotkeyActivated);

    await _trayService.initialize(
      onShowWindow: _showWindow,
      onQuit: _quit,
    );

    // Auto-purge expired history records on startup
    final prefs = getIt<SharedPreferences>();
    final retentionDays = prefs.getInt(AppConstants.historyRetentionDaysKey) ?? 7;
    await getIt<HistoryRepository>().purgeExpiredRecords(retentionDays);
  }

  Future<void> _onHotkeyActivated() async {
    await ref.read(zeroTypeControllerProvider.notifier).toggleRecording();
  }

  void _showWindow() {
    windowManager.show();
    windowManager.focus();
  }

  void _quit() {
    _hotkeyService.dispose();
    _trayService.dispose();
    exit(0);
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hotkeyService.dispose();
    _trayService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
