import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/features/phrases/phrase_controller.dart';
import 'package:zero_type/shared/widgets/action_icon.dart';

class PhrasePage extends ConsumerWidget {
  const PhrasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final phrasesAsync = ref.watch(phraseControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '常用詞彙',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(phraseControllerProvider.notifier).openFile(),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('編輯檔案'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton.icon(
                  onPressed: () => ref.invalidate(phraseControllerProvider),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('重新載入'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '在歷史記錄按「加入常用詞彙」把文字存進來，隨時複製取用；'
              '「編輯檔案」是直接改 phrases.json，改完按「重新載入」',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withAlpha(150),
                  ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: phrasesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('讀取失敗：$e')),
                data: (phrases) => phrases.isEmpty
                    ? _buildEmptyState(context, colorScheme)
                    : _buildList(context, ref, colorScheme, phrases),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmarks_outlined,
            size: 64,
            color: colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有常用詞彙',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(100),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '到歷史記錄挑一句加進來吧',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withAlpha(70),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    List<String> phrases,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withAlpha(30)),
      ),
      child: ListView.separated(
        itemCount: phrases.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: colorScheme.onSurface.withAlpha(20)),
        itemBuilder: (context, index) {
          final phrase = phrases[index];
          return ListTile(
            title: Text(phrase, maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ActionIcon(
                  icon: Icons.copy_outlined,
                  tooltip: '複製文字',
                  onTap: () async {
                    await ref
                        .read(phraseControllerProvider.notifier)
                        .copy(phrase);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已複製'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                ActionIcon(
                  icon: Icons.delete_outline,
                  tooltip: '刪除',
                  // 刪除用品牌橘，不用紅色
                  color: colorScheme.primary,
                  onTap: () => ref
                      .read(phraseControllerProvider.notifier)
                      .remove(phrase),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
