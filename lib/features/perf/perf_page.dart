import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/theme/font_sizes.dart';
import 'package:zero_type/features/perf/perf_controller.dart';

/// 本機端點 ms/token 超過這個值就標成警示色。正常約 34～48；被節能節流時 200 以上。
const _slowMsPerToken = 120;

class PerfPage extends ConsumerWidget {
  const PerfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(perfControllerProvider);
    final entries = perf.entries;
    final cs = Theme.of(context).colorScheme;
    final fontSizes = ref.watch(fontSizesProvider);
    final median = _medianMsPerToken(entries);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(
            children: [
              Text(
                '效能紀錄',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    '${entries.length} 筆',
                    if (median != null) '本機 ms/token 中位數 $median',
                    if (!perf.enabled) '記錄已關閉',
                  ].join('，'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                ),
              ),
              Tooltip(
                message: '開著時每句辨識記一筆：錄音長度、辨識時間、tokens、ms/token。'
                    '寫進 perf.jsonl。按這裡的清空、清空紀錄分頁或清除歷史時一併刪掉',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('記錄效能',
                        style: TextStyle(fontSize: fontSizes.itemTitle)),
                    Transform.scale(
                      scale: 0.75,
                      child: Switch(
                        value: perf.enabled,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) => ref
                            .read(perfControllerProvider.notifier)
                            .setEnabled(val),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: entries.isEmpty
                    ? null
                    : () => ref.read(perfControllerProvider.notifier).clear(),
                icon: const Icon(Icons.delete_outline, size: 24),
                label: Text('清空',
                    style: TextStyle(fontSize: fontSizes.itemTitle)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const _HeaderRow(),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    perf.enabled ? '還沒有紀錄，說一句話試試' : '打開「記錄效能」之後，每句辨識會記在這裡',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _PerfRow(entry: entries[i]),
                ),
        ),
      ],
    );
  }

  /// 只看本機端點：雲端的 ms/token 含網路，混進來中位數就沒意義
  static int? _medianMsPerToken(List<PerfEntry> entries) {
    final v = entries
        .where((e) => e.provider == 'local')
        .map((e) => e.msPerToken)
        .whereType<int>()
        .toList()
      ..sort();
    return v.isEmpty ? null : v[v.length ~/ 2];
  }
}

// 欄寬：時間、錄音、辨識、tokens、ms/token 固定寬，模型吃剩下的
const _colWidths = [92.0, 88.0, 88.0, 120.0, 104.0];

TextStyle _cellStyle(Color color) => TextStyle(
      fontSize: 16,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = _cellStyle(Theme.of(context).colorScheme.onSurfaceVariant);
    const labels = ['時間', '錄音', '辨識', 'in / out', 'ms/token'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            SizedBox(width: _colWidths[i], child: Text(labels[i], style: style)),
          Expanded(child: Text('模型', style: style)),
        ],
      ),
    );
  }
}

class _PerfRow extends StatelessWidget {
  const _PerfRow({required this.entry});

  final PerfEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final at = entry.at;
    final now = DateTime.now();
    final isToday = at.year == now.year && at.month == now.month && at.day == now.day;
    final hm = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';
    final stamp = isToday ? hm : '${at.month}/${at.day} ${hm.substring(0, 5)}';
    String secs(int? ms) => ms == null ? '—' : '${(ms / 1000).toStringAsFixed(1)} 秒';

    final mpt = entry.msPerToken;
    final isLocal = entry.provider == 'local';
    final slow = isLocal && mpt != null && mpt > _slowMsPerToken;
    final cells = [
      stamp,
      secs(entry.audioMs),
      secs(entry.processingMs),
      entry.inputTokens == null ? '—' : '${entry.inputTokens} / ${entry.outputTokens}',
      mpt == null ? '—' : '$mpt',
    ];
    final providerName = kProviderNames[entry.provider] ?? entry.provider;
    final modelName = kModelNames[entry.model] ?? entry.model;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            SizedBox(
              width: _colWidths[i],
              child: Text(
                cells[i],
                style: _cellStyle(i == 4 && slow ? cs.error : cs.onSurface).copyWith(
                    fontWeight: i == 4 && slow ? FontWeight.bold : null),
              ),
            ),
          Expanded(
            child: Text(
              '$providerName · $modelName',
              overflow: TextOverflow.ellipsis,
              style: _cellStyle(cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
