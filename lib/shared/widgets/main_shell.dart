import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/app_lifecycle.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/dictionary/presentation/pages/dictionary_page.dart';
import 'package:zero_type/features/history/presentation/controllers/history_controller.dart';
import 'package:zero_type/features/settings/presentation/controllers/settings_controller.dart';
import 'package:zero_type/features/history/presentation/pages/history_page.dart';
import 'package:zero_type/features/log/log_page.dart';
import 'package:zero_type/features/model_config/presentation/pages/model_config_page.dart';
import 'package:zero_type/features/phrases/phrase_page.dart';
import 'package:zero_type/features/prompt/presentation/pages/prompt_page.dart';
import 'package:zero_type/features/settings/presentation/pages/settings_page.dart';

class MainShellPage extends ConsumerStatefulWidget {
  const MainShellPage({super.key});

  @override
  ConsumerState<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends ConsumerState<MainShellPage> {
  static const String _permissionPromptKey = 'has_shown_permission_prompt_v1';
  bool _needsPermissionPrompt = false;
  bool _dialogShown = false;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = appPrefs;
    if (!prefs.containsKey(_permissionPromptKey)) {
      await prefs.setBool(_permissionPromptKey, true);
      if (mounted) setState(() => _needsPermissionPrompt = true);
    }
  }

  void _showPermissionPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security_outlined,
                color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('需要系統權限'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ZeroType 需要以下兩項系統權限才能正常運作：',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            _PermissionItem(
              icon: Icons.accessibility_new,
              title: '輔助使用',
              description: '系統設定 > 隱私權與安全性 > 輔助使用',
              note: '用於自動貼上辨識結果',
            ),
            const SizedBox(height: 12),
            _PermissionItem(
              icon: Icons.mic,
              title: '麥克風',
              description: '系統設定 > 隱私權與安全性 > 麥克風',
              note: '用於錄製語音',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍後再說'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _activeIndex = 0); // Settings is now index 0
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildMain();
  }

  void _confirmQuit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('結束 ZeroType'),
        content: const Text('確定要結束 ZeroType 嗎？結束後全域熱鍵將無法使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: quitApp,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('結束'),
          ),
        ],
      ),
    );
  }

  Widget _buildMain() {
    if (_needsPermissionPrompt && !_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPermissionPrompt(context);
      });
    }

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 44,
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  // notes: 只換這顆標題，視窗標題不動 —— app_lifecycle 的
                  // FindWindowW 靠 'ZeroType' 這個標題認既有視窗
                  child: const DragToMoveArea(
                    child: Center(child: _TitleLabel()),
                  ),
                ),
                // macOS 仍有原生紅綠燈按鈕,只在 Windows/Linux 顯示自訂按鈕
                if (!Platform.isMacOS) ...[
                  _WindowButton(
                    icon: Icons.remove,
                    onTap: windowManager.minimize,
                  ),
                  _WindowButton(
                    icon: Icons.close,
                    onTap: windowManager.hide, // 關閉 = 縮到系統匣
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedIndex: _activeIndex,
                  onDestinationSelected: (index) {
                    if (index == 5) {
                      ref.invalidate(historyControllerProvider);
                      ref.invalidate(historyStatsProvider);
                    }
                    if (index == 0) {
                      // 重新查詢系統權限狀態（原 AutoRouteAware didPush 的職責）
                      ref.invalidate(settingsControllerProvider);
                    }
                    setState(() => _activeIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: const SizedBox(height: 16),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Tooltip(
                          message: '結束 ZeroType',
                          child: IconButton(
                            onPressed: () => _confirmQuit(context),
                            icon: const Icon(Icons.power_settings_new),
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 圖示的顏色與大小由 AppTheme 的 navigationRailTheme 決定
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('設定'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('模型'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.edit_note_outlined),
                      selectedIcon: Icon(Icons.edit_note),
                      label: Text('提示詞'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.book_outlined),
                      selectedIcon: Icon(Icons.book),
                      label: Text('字典檔'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bookmarks_outlined),
                      selectedIcon: Icon(Icons.bookmarks),
                      label: Text('常用詞彙'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.history_outlined),
                      selectedIcon: Icon(Icons.history),
                      label: Text('歷史'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: Text('紀錄'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  // notes: IndexedStack 一次建好所有頁（原 AutoTabsRouter 是懶載入），
                  // 頁面初始化都是輕量讀取，桌面 app 無感；歷史頁本來就靠切換時 invalidate 更新
                  child: IndexedStack(
                    index: _activeIndex,
                    children: const [
                      SettingsPage(),
                      ModelConfigPage(),
                      PromptPage(),
                      DictionaryPage(),
                      PhrasePage(),
                      HistoryPage(),
                      LogPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleLabel extends ConsumerWidget {
  const _TitleLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(zeroTypeControllerProvider
        .select((s) => s.status == ZeroTypeStatus.recording));
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          color: recording ? const Color(0xFFE53935) : null,
        );

    if (!recording) return Text('Zero Type', style: style);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFE53935),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('錄音中', style: style),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, required this.onTap});

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        onTap: onTap,
        child: Icon(icon, size: 16),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String description;
  final String note;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(description,
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
              Text(note,
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ],
    );
  }
}
