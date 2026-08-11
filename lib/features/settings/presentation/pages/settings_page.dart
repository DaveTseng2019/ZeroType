import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'package:zero_type/core/theme/font_sizes.dart';
import 'package:zero_type/core/theme/theme_controller.dart';
import 'package:zero_type/core/utils/version_compare.dart';
import 'package:zero_type/features/log/log_controller.dart';
import '../controllers/settings_controller.dart';

/// 開啟紀錄檔所在的資料夾。
/// notes: 開資料夾而不是開檔 —— .log 不一定有關聯的程式，開檔可能什麼都不會發生；
///   資料夾一定開得起來，而且檔案還沒產生時也不會撲空。
Future<void> _openDebugLogFolder() async {
  final file = await LogController.logFile();
  await launchUrl(Uri.file(file.parent.path),
      mode: LaunchMode.externalApplication);
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Force a full rebuild when page is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) => _invalidateSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fires when user returns from System Preferences
    if (state == AppLifecycleState.resumed) {
      _invalidateSettings();
    }
  }

  // notes: 原 AutoRouteAwareStateMixin 的 didPush/didPopNext 改由 main_shell
  // 切到設定 tab 時 invalidate settingsControllerProvider 達成同樣的權限重查
  void _invalidateSettings() {
    // Invalidating forces the provider to call build() from scratch,
    // ensuring we always get fresh permission states from the OS.
    ref.invalidate(settingsControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeControllerProvider);
    final isDark = themeMode == ThemeMode.dark;
    final settings = ref.watch(settingsControllerProvider);
    final fontSizes = ref.watch(fontSizesProvider);

    // Once the controller finishes its initial async build, immediately
    // re-invalidate to snapshot the freshest OS permission state.
    ref.listen(settingsControllerProvider, (previous, next) {
      if (previous?.isLoading == true && next.hasValue) {
        // Don't invalidate again here — build() already fetched fresh permissions.
        // This listener is kept only for future extensibility.
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '設定',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSizes.pageTitle,
                      ),
                ),
                const SizedBox(height: 32),

                // --- Shortcut Section ---
                _SectionHeader(title: '快捷鍵'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    settings.when(
                      data: (data) => Column(
                        children: [
                          _buildHotkeyTile(
                            context,
                            ref,
                            icon: Icons.keyboard,
                            title: '全局錄音快捷鍵',
                            subtitle: '按下此組合鍵即可開始/停止錄音',
                            hotkey: data.hotkey,
                          ),
                          const Divider(height: 1, indent: 56),
                          _buildHotkeyTile(
                            context,
                            ref,
                            icon: Icons.bolt,
                            title: '精簡模式快捷鍵',
                            subtitle: '講完就自動停止錄音，不必再按一次',
                            hotkey: data.quickHotkey,
                            quick: true,
                          ),
                          const Divider(height: 1, indent: 56),
                          _SettingTile(
                            icon: Icons.keyboard_return,
                            title: '精簡模式自動送出',
                            subtitle: '文字貼上後自動按 Enter；關閉則只貼上不送出',
                            trailing: Switch(
                              value: data.quickAutoEnter,
                              onChanged: (val) => ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleQuickAutoEnter(val),
                            ),
                          ),
                        ],
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- General Settings Section ---
                _SectionHeader(title: '一般設定'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    // Theme Toggle
                    _SettingTile(
                      icon: isDark ? Icons.dark_mode : Icons.light_mode,
                      title: '深色模式',
                      subtitle: '切換應用程式的外觀風格',
                      trailing: _AppToggle(
                        value: isDark,
                        onChanged: (_) =>
                            ref.read(themeControllerProvider.notifier).toggleTheme(),
                        activeIcon: Icons.nightlight_round,
                        inactiveIcon: Icons.wb_sunny_rounded,
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    
                    // Launch at Startup
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.launch,
                        title: '開機啟動',
                        subtitle: '在電腦啟動時自動開啟 ZeroType',
                        trailing: Switch(
                          value: data.launchAtStartup,
                          onChanged: (val) => ref
                              .read(settingsControllerProvider.notifier)
                              .toggleLaunchAtStartup(val),
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    // Startup Minimized (only when launch at startup is on)
                    settings.when(
                      data: (data) => data.launchAtStartup
                          ? Column(
                              children: [
                                const Divider(height: 1, indent: 56),
                                _SettingTile(
                                  icon: Icons.remove_circle_outline,
                                  title: '啟動時縮小至系統匣',
                                  subtitle: '程式啟動時不顯示視窗,僅顯示於系統匣',
                                  trailing: Switch(
                                    value: data.startupMinimized,
                                    onChanged: (val) => ref
                                        .read(settingsControllerProvider.notifier)
                                        .toggleStartupMinimized(val),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // History Retention Days
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.history,
                        title: '歷史記錄保留時間',
                        subtitle: '超過保留天數的記錄將自動刪除',
                        trailing: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 7, label: Text('7天')),
                            ButtonSegment(value: 14, label: Text('14天')),
                            ButtonSegment(value: 30, label: Text('30天')),
                          ],
                          selected: {data.historyRetentionDays},
                          onSelectionChanged: (selection) => ref
                              .read(settingsControllerProvider.notifier)
                              .setHistoryRetentionDays(selection.first),
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // Max Recording Duration
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.timer_outlined,
                        title: '最長錄音時間',
                        subtitle: '超過此時長將自動停止並送出辨識',
                        trailing: SizedBox(
                          width: 200,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Slider(
                                  value: data.maxRecordingMinutes.toDouble(),
                                  min: 1,
                                  max: 5,
                                  divisions: 4,
                                  onChanged: (val) => ref
                                      .read(settingsControllerProvider.notifier)
                                      .setMaxRecordingMinutes(val.round()),
                                ),
                              ),
                              Text(
                                '${data.maxRecordingMinutes} 分鐘',
                                style: TextStyle(
                                  fontSize: fontSizes.description,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // Input Device
                    settings.when(
                      data: (data) => _InputDeviceTile(
                        selectedId: data.inputDeviceId,
                        devices: data.inputDevices,
                        defaultLabel: data.defaultDeviceLabel,
                        commsLabel: data.defaultCommsDeviceLabel,
                        onChanged: (id) => ref
                            .read(settingsControllerProvider.notifier)
                            .setInputDeviceId(id),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // Record Warmup（藍牙 HFP 協商期間的靜音）
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.hourglass_bottom,
                        title: '等待麥克風就緒',
                        subtitle: '換裝置時會自動帶值：名稱有「耳機」給 1 秒，其他給 0。'
                            '時間到就開始收音，不管當下有沒有聲音',
                        trailing: SizedBox(
                          width: 200,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Slider(
                                  // notes: 上限收到 3 秒、刻度 0.1 秒。原本是 8 秒／0.5 秒
                                  // 一格，但那個範圍是為了等 HFP 協商結束才訂的，
                                  // 現在放行條件已改成「不是數位靜音」，等再久也沒有用；
                                  // 0.3 秒這種常用值反而選不到
                                  value: data.recordWarmupMs
                                      .clamp(0, 3000)
                                      .toDouble(),
                                  max: 3000,
                                  divisions: 30,
                                  onChanged: (val) => ref
                                      .read(settingsControllerProvider.notifier)
                                      .setRecordWarmupMs(val.round()),
                                ),
                              ),
                              Text(
                                data.recordWarmupMs == 0
                                    ? '關閉'
                                    : '${(data.recordWarmupMs / 1000).toStringAsFixed(1)} 秒',
                                style: TextStyle(
                                  fontSize: fontSizes.description,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // Noise Gate（0 = 不過濾，不另外做開關）
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.graphic_eq,
                        title: '濾除背景噪音',
                        subtitle: '門檻 = 環境噪音底 × 強度，把明顯低於底噪的片段壓下去。'
                            '0 表示不過濾（預設）；太大會連氣音和小聲的字一起吃掉，'
                            '也可能把音訊挖得太空讓辨識憑空生成內容',
                        trailing: SizedBox(
                          width: 200,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 140,
                                child: Slider(
                                  value: data.noiseGateStrength.clamp(0.0, 6.0),
                                  max: 6.0,
                                  divisions: 12,
                                  onChanged: (val) => ref
                                      .read(settingsControllerProvider.notifier)
                                      .setNoiseGateStrength(val),
                                ),
                              ),
                              Text(
                                data.noiseGateStrength <= 0
                                    ? '關閉'
                                    : data.noiseGateStrength.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: fontSizes.description,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    // Debug Log
                    settings.when(
                      data: (data) => Column(
                        children: [
                          _SettingTile(
                            icon: Icons.bug_report_outlined,
                            title: '偵錯模式',
                            subtitle: '紀錄一併寫到 debug.log，並多記貼上目標等細節；'
                                '平常關著，追問題時才開。清除歷史紀錄時會一併刪掉',
                            trailing: Switch(
                              value: data.debugLog,
                              onChanged: (val) => ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleDebugLog(val),
                            ),
                          ),
                          if (data.debugLog) ...[
                            const Divider(height: 1, indent: 56),
                            _SettingTile(
                              icon: Icons.folder_open,
                              title: '紀錄檔位置',
                              subtitle: '開啟 debug.log 所在的資料夾',
                              trailing: OutlinedButton(
                                onPressed: _openDebugLogFolder,
                                child: const Text('開啟'),
                              ),
                            ),
                          ],
                        ],
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- Font Size Section ---
                _SectionHeader(title: '字體'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    Builder(
                      builder: (context) => _SettingTile(
                        icon: Icons.format_size,
                        title: '文字大小 (JSON)',
                        subtitle: '自訂各層級文字大小',
                        trailing: OutlinedButton(
                          onPressed: () => _showFontSizeEditor(context),
                          child: const Text('編輯'),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- Sound Section ---
                _SectionHeader(title: '音效', subtitle: '開始、結束、完成三個階段的提示音'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    settings.when(
                      data: (data) => _SettingTile(
                        icon: Icons.volume_up,
                        title: '啟用音效',
                        subtitle: '開始與停止錄音時播放提示音',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: data.soundEnabled,
                              onChanged: (val) => ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleSound(val),
                            ),
                            const SizedBox(width: 8),
                            _SoundSequenceButton(
                              enabled: data.soundEnabled,
                              paths: [
                                data.startSound,
                                data.recordingStoppedSound,
                                data.stopSound,
                              ],
                            ),
                          ],
                        ),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    settings.when(
                      data: (data) => _SoundPickerTile(
                        icon: Icons.play_circle_outline,
                        title: '開始錄音音效',
                        subtitle: '按下快捷鍵開始錄音時播放',
                        selectedPath: data.startSound,
                        enabled: data.soundEnabled,
                        slot: 0,
                        onChanged: (path) => ref
                            .read(settingsControllerProvider.notifier)
                            .setStartSound(path),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    settings.when(
                      data: (data) => _SoundPickerTile(
                        icon: Icons.stop_circle_outlined,
                        title: '錄音結束音效',
                        subtitle: '再次按下快捷鍵、麥克風真正關閉時播放',
                        selectedPath: data.recordingStoppedSound,
                        enabled: data.soundEnabled,
                        slot: 1,
                        onChanged: (path) => ref
                            .read(settingsControllerProvider.notifier)
                            .setRecordingStoppedSound(path),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    settings.when(
                      data: (data) => _SoundPickerTile(
                        icon: Icons.task_alt,
                        title: '辨識完成音效',
                        subtitle: '文字辨識完成、貼上前播放',
                        selectedPath: data.stopSound,
                        enabled: data.soundEnabled,
                        slot: 2,
                        onChanged: (path) => ref
                            .read(settingsControllerProvider.notifier)
                            .setStopSound(path),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    _SettingTile(
                      icon: Icons.settings_backup_restore,
                      title: '恢復預設音效',
                      subtitle: '三個音效與開關都回到初始設定',
                      trailing: OutlinedButton(
                        onPressed: () {
                          final notifier =
                              ref.read(settingsControllerProvider.notifier);
                          notifier.toggleSound(true);
                          notifier.setStartSound(kDefaultStartSound);
                          notifier.setRecordingStoppedSound(
                              kDefaultRecordingStoppedSound);
                          notifier.setStopSound(kDefaultStopSound);
                        },
                        child: const Text('恢復'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- System Permission Section ---
                _SectionHeader(title: '系統權限'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    settings.when(
                      data: (data) => _PermissionTile(
                        icon: Icons.accessibility_new,
                        title: '輔助使用權限',
                        subtitle: '自動貼上功能需要此權限以模擬鍵盤動作',
                        isAuthorized: data.isAccessibilityAuthorized,
                        onCheck: () => const MethodChannel('com.zerotype.app/permission')
                            .invokeMethod('openAccessibilitySettings'),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const Divider(height: 1, indent: 56),
                    settings.when(
                      data: (data) => _PermissionTile(
                        icon: Icons.mic,
                        title: '麥克風權限',
                        subtitle: '語音辨識功能需要存取你的麥克風',
                        isAuthorized: data.isMicrophoneAuthorized,
                        onCheck: () => const MethodChannel('com.zerotype.app/permission')
                            .invokeMethod('openMicrophoneSettings'),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // --- About Section ---
                _SectionHeader(title: '關於'),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingTile(
                      icon: Icons.code,
                      title: 'GitHub',
                      subtitle: '原始碼、Issue 回報與版本紀錄',
                      trailing: OutlinedButton(
                        onPressed: () => launchUrl(
                          Uri.parse(AppConstants.githubRepoUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('開啟'),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    const _UpdateCheckTile(),
                  ],
                ),

              ],
            ),
          ),

          // --- Hotkey Recorder Overlay ---
          settings.maybeWhen(
            data: (data) => data.isRecordingHotkey 
              ? _HotkeyRecorderOverlay(
                  onSave: (keys) => ref.read(settingsControllerProvider.notifier).saveHotkey(keys),
                  onClose: () => ref.read(settingsControllerProvider.notifier).stopRecordingHotkey(),
                )
              : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyTile(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required HotKey hotkey,
    bool quick = false,
  }) {
    return InkWell(
      onTap: () => ref
          .read(settingsControllerProvider.notifier)
          .startRecordingHotkey(quick: quick),
      borderRadius: BorderRadius.circular(16),
      child: _SettingTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withAlpha(50),
            ),
          ),
          child: _buildHotkeyDisplay(context, hotkey),
        ),
      ),
    );
  }

  Widget _buildHotkeyDisplay(BuildContext context, HotKey hotkey) {
    final List<Widget> widgets = [];
    
    if (hotkey.modifiers != null) {
      for (final mod in hotkey.modifiers!) {
        String label = '';
        if (mod == HotKeyModifier.meta) label = Platform.isMacOS ? '⌘ Command' : 'Win';
        if (mod == HotKeyModifier.shift) label = '⇧ Shift';
        if (mod == HotKeyModifier.alt) label = Platform.isMacOS ? '⌥ Option' : 'Alt';
        if (mod == HotKeyModifier.control) label = '⌃ Control';
        
        if (label.isNotEmpty) {
          if (widgets.isNotEmpty) widgets.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))));
          widgets.add(_KeyBadge(label: label));
        }
      }
    }

    String keyLabel = 'Key';
    if (hotkey.key is PhysicalKeyboardKey) {
      keyLabel = physicalKeyLabel(hotkey.key as PhysicalKeyboardKey);
    } else if (hotkey.key is LogicalKeyboardKey) {
      keyLabel = (hotkey.key as LogicalKeyboardKey).keyLabel;
    }

    if (widgets.isNotEmpty) widgets.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))));
    widgets.add(_KeyBadge(label: keyLabel.toUpperCase()));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  void _showFontSizeEditor(BuildContext context) {
    final controller =
        TextEditingController(text: ref.read(fontSizesProvider).toJson());
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('文字大小設定'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '由上而下依序是頁面標題、區塊標題、項目標題、項目說明，'
                  '單位 px，皆不可小於 ${FontSizes.minSize.toStringAsFixed(0)}。',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(fontSizesProvider.notifier).resetToDefault();
                setDialogState(() {
                  controller.text = FontSizes.defaults.toJson();
                  error = null;
                });
              },
              child: const Text('還原預設'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(fontSizesProvider.notifier)
                      .setFromJson(controller.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setDialogState(() => error = 'JSON 格式錯誤：$e');
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }

}

/// [PhysicalKeyboardKey.debugName] 在 release build 一律回 null（見
/// keyboard_key.g.dart 的 assert 包裝，release 會被 strip 掉）——
/// 熱鍵畫面之前一直靠這個顯示按鍵，release 版因此永遠只顯示「Key」。
/// 改用 usbHidUsage 自己對應，只涵蓋熱鍵合理會選到的範圍，其餘退回 16 進位代碼。
String physicalKeyLabel(PhysicalKeyboardKey key) {
  final usage = key.usbHidUsage & 0xFFFF;
  if (usage >= 0x04 && usage <= 0x1D) {
    return String.fromCharCode('A'.codeUnitAt(0) + (usage - 0x04));
  }
  if (usage >= 0x1E && usage <= 0x26) {
    return String.fromCharCode('1'.codeUnitAt(0) + (usage - 0x1E));
  }
  if (usage >= 0x3A && usage <= 0x45) {
    return 'F${usage - 0x39}';
  }
  const special = {
    0x27: '0',
    0x28: 'Enter',
    0x29: 'Esc',
    0x2A: 'Backspace',
    0x2B: 'Tab',
    0x2C: 'Space',
    0x2D: '-',
    0x2E: '=',
    0x2F: '[',
    0x30: ']',
    0x31: '\\',
    0x33: ';',
    0x34: "'",
    0x35: '`',
    0x36: ',',
    0x37: '.',
    0x38: '/',
  };
  return special[usage] ?? 'Key 0x${usage.toRadixString(16)}';
}

class _HotkeyRecorderOverlay extends StatefulWidget {
  final Function(List<PhysicalKeyboardKey>) onSave;
  final VoidCallback onClose;
  const _HotkeyRecorderOverlay({required this.onSave, required this.onClose});

  @override
  State<_HotkeyRecorderOverlay> createState() => _HotkeyRecorderOverlayState();
}

class _HotkeyRecorderOverlayState extends State<_HotkeyRecorderOverlay> {
  final FocusNode _focusNode = FocusNode();
  final Set<PhysicalKeyboardKey> _currentlyHeldKeys = {};
  final List<PhysicalKeyboardKey> _recordedKeys = [];
  String _displayText = '等待輸入...';
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _updateDisplayText() {
    if (_recordedKeys.isEmpty) {
      setState(() => _displayText = '等待輸入...');
      return;
    }

    final List<String> parts = [];
    final sortedKeys = List<PhysicalKeyboardKey>.from(_recordedKeys);
    
    // Sort logic
    sortedKeys.sort((a, b) {
      int score(PhysicalKeyboardKey k) {
        if (_isMeta(k)) return 0;
        if (_isControl(k)) return 1;
        if (_isAlt(k)) return 2;
        if (_isShift(k)) return 3;
        return 4;
      }
      return score(a).compareTo(score(b));
    });

    for (final key in sortedKeys) {
      if (_isMeta(key)) {
        final metaLabel = Platform.isMacOS ? '⌘ Command' : 'Win';
        if (!parts.contains(metaLabel)) parts.add(metaLabel);
      } else if (_isControl(key)) {
        if (!parts.contains('⌃ Control')) parts.add('⌃ Control');
      } else if (_isAlt(key)) {
        final altLabel = Platform.isMacOS ? '⌥ Option' : 'Alt';
        if (!parts.contains(altLabel)) parts.add(altLabel);
      } else if (_isShift(key)) {
        if (!parts.contains('⇧ Shift')) parts.add('⇧ Shift');
      } else if (key == PhysicalKeyboardKey.space) {
        parts.add('Space');
      } else {
        // More robust labeling for PhysicalKeyboardKey
        String label = key.debugName ?? 'Key';
        if (label.startsWith('Key ')) {
          label = label.substring(4);
        }
        
        // Handle specific cases or ensure it's uppercase
        if (label.length == 1) {
          label = label.toUpperCase();
        }
        parts.add(label);
      }
    }

    setState(() => _displayText = parts.join(' + '));
  }

  bool _isModifier(PhysicalKeyboardKey key) => _isMeta(key) || _isControl(key) || _isAlt(key) || _isShift(key);
  bool _isMeta(PhysicalKeyboardKey key) => key == PhysicalKeyboardKey.metaLeft || key == PhysicalKeyboardKey.metaRight;
  bool _isControl(PhysicalKeyboardKey key) => key == PhysicalKeyboardKey.controlLeft || key == PhysicalKeyboardKey.controlRight;
  bool _isAlt(PhysicalKeyboardKey key) => key == PhysicalKeyboardKey.altLeft || key == PhysicalKeyboardKey.altRight;
  bool _isShift(PhysicalKeyboardKey key) => key == PhysicalKeyboardKey.shiftLeft || key == PhysicalKeyboardKey.shiftRight;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent) {
            if (_currentlyHeldKeys.isEmpty) {
              _recordedKeys.clear();
              _isFinished = false;
            }

            if (!_recordedKeys.contains(event.physicalKey)) {
              _recordedKeys.add(event.physicalKey);
            }
            _currentlyHeldKeys.add(event.physicalKey);
            _updateDisplayText();
            
            if (event.physicalKey == PhysicalKeyboardKey.escape && _currentlyHeldKeys.length == 1) {
              _recordedKeys.clear();
              widget.onClose();
              return;
            }
          } else if (event is KeyUpEvent) {
            _currentlyHeldKeys.remove(event.physicalKey);
            if (_currentlyHeldKeys.isEmpty) {
              _isFinished = true;
            }
          }
        },
        child: Container(
          color: Colors.black.withOpacity(0.9),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.keyboard, color: Colors.orangeAccent, size: 64),
                    const SizedBox(height: 24),
                    Text(
                      '錄製快捷鍵組合',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 32),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _recordedKeys.isNotEmpty ? Colors.orangeAccent.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orangeAccent.withOpacity(_recordedKeys.isNotEmpty ? 0.1 : 0),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Text(
                        _displayText,
                        style: TextStyle(
                          color: _recordedKeys.isNotEmpty ? Colors.orangeAccent : Colors.white24,
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      '請「同時按住」組合鍵，放開後可重新輸入',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 64),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: widget.onClose,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white60,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('取消', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 24),
                        if (_recordedKeys.isNotEmpty)
                          ElevatedButton(
                            onPressed: () => widget.onSave(_recordedKeys),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 10,
                            ),
                            child: const Text(
                              '儲存設定',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 40,
                right: 40,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 36),
                  onPressed: widget.onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSizes = ref.watch(fontSizesProvider);
    final titleText = Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: fontSizes.sectionHeader,
          ),
    );
    if (subtitle == null) return titleText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        titleText,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle!,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  fontSize: fontSizes.description,
                ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isAuthorized;
  final VoidCallback onCheck;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isAuthorized,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SettingTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isAuthorized ? Colors.green : Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isAuthorized ? Colors.green : Colors.red).withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isAuthorized ? '已授權' : '未授權',
            style: TextStyle(
              color: isAuthorized ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: ref.watch(fontSizesProvider).description,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: onCheck,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('打開設定'),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSizes = ref.watch(fontSizesProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Ensure vertical center alignment
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: fontSizes.itemTitle)),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: fontSizes.description,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData activeIcon;
  final IconData inactiveIcon;

  const _AppToggle({
    required this.value,
    required this.onChanged,
    required this.activeIcon,
    required this.inactiveIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            value ? activeIcon : inactiveIcon,
            size: 20,
            color: value ? Colors.orangeAccent : Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _KeyBadge extends StatelessWidget {
  final String label;
  const _KeyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _UpdateCheckTile extends StatefulWidget {
  const _UpdateCheckTile();

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  String _currentVersion = '';
  String? _latestVersion;
  String? _releaseUrl;
  bool _checking = true;
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _currentVersion = info.version);

    try {
      final response = await dio
          .get(AppConstants.githubLatestReleaseApiUrl);
      final tag = response.data['tag_name'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        _latestVersion = tag.replaceFirst(RegExp(r'^v'), '');
        _releaseUrl = response.data['html_url'] as String?;
        _checking = false;
      });
    } catch (e) {
      print('[SettingsPage] Update check failed: $e');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checkFailed = true;
      });
    }
  }

  bool get _updateAvailable {
    final latest = _latestVersion;
    if (latest == null) return false;
    return isNewerVersion(latest, _currentVersion);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _checking
        ? '檢查更新中...'
        : _checkFailed
            ? '無法檢查更新，請確認網路連線'
            : _updateAvailable
                ? '發現新版本 v$_latestVersion'
                : '已是最新版本';

    return _SettingTile(
      icon: Icons.new_releases_outlined,
      title: '版本',
      subtitle: _currentVersion.isEmpty
          ? subtitle
          : 'v$_currentVersion ・ $subtitle',
      trailing: _updateAvailable
          ? ElevatedButton(
              onPressed: _releaseUrl == null
                  ? null
                  : () => launchUrl(
                        Uri.parse(_releaseUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
              child: const Text('下載更新'),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// 圖示上那個 Ø 的橘色
const kBrandOrange = Color(0xFFEB5E14);

class _InputDeviceTile extends ConsumerWidget {
  /// 空字串 = 系統預設
  final String selectedId;
  final List<InputDevice> devices;
  final String defaultLabel;
  final String commsLabel;
  final ValueChanged<String> onChanged;

  const _InputDeviceTile({
    required this.selectedId,
    required this.devices,
    required this.defaultLabel,
    required this.commsLabel,
    required this.onChanged,
  });

  /// 選「系統預設」時要講清楚那到底是哪一支，不然使用者看不出自己在用藍牙麥克風
  String get _subtitle {
    const base = '藍牙耳機麥克風會使耳機切到通話模式（提示音被吃掉、開頭靜音、底噪變大），可改用其他麥克風';
    if (selectedId.isNotEmpty) return base;
    if (defaultLabel.isEmpty && commsLabel.isEmpty) return base;
    if (commsLabel.isEmpty || commsLabel == defaultLabel) {
      return '目前的系統預設是「$defaultLabel」。$base';
    }
    return '系統預設「$defaultLabel」，預設通訊裝置「$commsLabel」—— '
        '兩者不同時實際用哪一支由 Windows 決定，建議直接指定。$base';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelSize = ref.watch(fontSizesProvider).description;
    // 存的裝置已不存在（拔除／藍牙斷線）就顯示系統預設，錄音端也會自動退回
    final effectiveId =
        devices.any((d) => d.id == selectedId) ? selectedId : '';
    final labels = <String, String>{
      '': '系統預設',
      for (final d in devices) d.id: d.label,
    };

    return _SettingTile(
      icon: Icons.mic_none,
      title: '錄音輸入裝置',
      subtitle: _subtitle,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: DropdownButton<String>(
          value: effectiveId,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(12),
          // 用品牌橘標出目前實際在錄的裝置 —— 這一項選錯，後面所有問題都在追鬼
          selectedItemBuilder: (_) => labels.values.map((label) {
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w600,
                  color: kBrandOrange,
                ),
              ),
            );
          }).toList(),
          items: labels.entries.map((e) {
            return DropdownMenuItem<String>(
              value: e.key,
              child: Text(
                e.value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: labelSize),
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id != null) onChanged(id);
          },
        ),
      ),
    );
  }
}

/// 連續播放時正在播第幾個音效（對應 [_SoundPickerTile.slot]），沒在播是 null。
///
/// notes: 只有這三個 tile 跟按鈕要共用，用全域 ValueNotifier 直接接；
/// 之後有第二處要讀播放狀態再升成 provider。
final ValueNotifier<int?> _playingSoundSlot = ValueNotifier<int?>(null);

class _SoundPickerTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String selectedPath;
  final bool enabled;
  final ValueChanged<String> onChanged;
  /// 在連續播放序列裡的位置，用來標示現在播的是哪一個。
  final int slot;

  const _SoundPickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selectedPath,
    required this.enabled,
    required this.onChanged,
    required this.slot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final labelSize = ref.watch(fontSizesProvider).description;
    // 殘留的 macOS 路徑先對應成 Windows 內建提示音再找清單
    final mappedPath = kSystemSoundLabels.containsKey(selectedPath)
        ? selectedPath
        : kWindowsSounds[selectedPath];
    final effectivePath =
        kSystemSoundLabels.containsKey(mappedPath) && mappedPath != null
            ? mappedPath
            : (kSystemSoundLabels.containsKey(kDefaultStartSound)
                ? kDefaultStartSound
                : kSystemSoundLabels.keys.first);
    final selectedLabel = kSystemSoundLabels[effectivePath] ?? '';

    return ValueListenableBuilder<int?>(
      valueListenable: _playingSoundSlot,
      builder: (context, playingSlot, child) {
        final isPlaying = playingSlot == slot;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: isPlaying ? cs.primary.withOpacity(0.10) : Colors.transparent,
          child: _tile(
              context, cs, labelSize, effectivePath, selectedLabel, isPlaying),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    ColorScheme cs,
    double labelSize,
    String effectivePath,
    String selectedLabel,
    bool isPlaying,
  ) {
    return _SettingTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: effectivePath,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              selectedItemBuilder: (_) => kSystemSoundLabels.entries.map((e) {
                return Center(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: labelSize,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                );
              }).toList(),
              items: kSystemSoundLabels.entries.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value, style: TextStyle(fontSize: labelSize)),
                );
              }).toList(),
              onChanged: enabled
                  ? (path) {
                      if (path != null) onChanged(path);
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            _PlayIconButton(
              icon: isPlaying
                  ? Icons.graphic_eq_rounded
                  : Icons.play_arrow_rounded,
              tooltip: isPlaying ? '播放中…' : '預覽「$selectedLabel」',
              onTap: enabled
                  ? () => soundService.playPreview(effectivePath)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放鍵：沿用歷史頁播放鍵的圓形底色樣式，設定頁這邊放大一號。
class _PlayIconButton extends StatelessWidget {
  const _PlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color =
        onTap != null ? cs.primary : cs.onSurface.withOpacity(0.35);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

/// 依實際錄音流程的順序連續試聽：開始 → 錄音結束 → 辨識完成。
class _SoundSequenceButton extends StatefulWidget {
  const _SoundSequenceButton({required this.paths, required this.enabled});

  final List<String> paths;
  final bool enabled;

  @override
  State<_SoundSequenceButton> createState() => _SoundSequenceButtonState();
}

class _SoundSequenceButtonState extends State<_SoundSequenceButton> {
  bool _playing = false;

  Future<void> _play() async {
    setState(() => _playing = true);
    for (var i = 0; i < widget.paths.length; i++) {
      _playingSoundSlot.value = i;
      await soundService.playPreview(widget.paths[i]);
      // notes: Windows 走 SND_ASYNC，playPreview 回來時最後一段還在響，
      // 用固定間隔隔開；要精準就得改成同步播放並回報實際長度。
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    _playingSoundSlot.value = null;
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PlayIconButton(
      icon: _playing ? Icons.graphic_eq_rounded : Icons.playlist_play_rounded,
      tooltip: _playing ? '播放中…' : '連續播放三段音效範例',
      onTap: widget.enabled && !_playing ? _play : null,
    );
  }
}
