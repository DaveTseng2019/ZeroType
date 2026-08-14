import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/theme/font_sizes.dart';
import 'package:zero_type/features/log/log_controller.dart';

/// 開啟紀錄檔所在的資料夾。
/// notes: 開資料夾而不是開檔 —— .log 不一定有關聯的程式，開檔可能什麼都不會發生；
///   資料夾一定開得起來，而且檔案還沒產生時也不會撲空。
Future<void> _openDebugLogFolder() async {
  final file = await LogController.logFile();
  await launchUrl(Uri.file(file.parent.path),
      mode: LaunchMode.externalApplication);
}

class LogPage extends ConsumerWidget {
  const LogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(logControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final fontSizes = ref.watch(fontSizesProvider);
    final debugOn = appPrefs.getBool(AppConstants.debugLogKey) ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(
            children: [
              Text(
                '執行紀錄',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Text(
                debugOn
                    ? '${entries.length} 筆，偵錯模式開著，另外寫進 debug.log'
                    : '${entries.length} 筆，只留在記憶體',
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              if (debugOn)
                TextButton.icon(
                  onPressed: _openDebugLogFolder,
                  icon: const Icon(Icons.folder_open, size: 24),
                  label: Text('紀錄檔位置',
                      style: TextStyle(fontSize: fontSizes.itemTitle)),
                ),
              TextButton.icon(
                // 偵錯模式開著時一律可按：重開 app 後記憶體是空的，但 debug.log
                // 還在，停用按鈕就沒有任何地方能把它清掉了。
                onPressed: entries.isEmpty && !debugOn
                    ? null
                    : () => ref.read(logControllerProvider.notifier).clear(),
                icon: const Icon(Icons.delete_outline, size: 24),
                label: Text('清空',
                    style: TextStyle(fontSize: fontSizes.itemTitle)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '還沒有訊息',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _LogRow(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isError = entry.level == LogLevel.error;
    final at = entry.at;
    final stamp = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stamp,
            style: TextStyle(
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              entry.message,
              style: TextStyle(
                fontSize: 17,
                color: isError ? cs.error : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
