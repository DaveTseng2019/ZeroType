import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/features/dictionary/presentation/controllers/dictionary_controller.dart';

class DictionaryPage extends ConsumerStatefulWidget {
  const DictionaryPage({super.key});

  @override
  ConsumerState<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends ConsumerState<DictionaryPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _addWord() async {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    await ref.read(dictionaryControllerProvider.notifier).addWord(word);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wordsAsync = ref.watch(dictionaryControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '字典檔',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '加入常用的專有名詞，提升語音辨識的準確性',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withAlpha(150),
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: '輸入專有名詞…',
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colorScheme.onSurface.withAlpha(50),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colorScheme.onSurface.withAlpha(50),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (_) => _addWord(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addWord,
                  icon: const Icon(Icons.add),
                  label: const Text('加入'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: wordsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('讀取失敗：$e')),
                data: (words) => words.isEmpty
                    ? _buildEmptyState(context, colorScheme)
                    : _buildWordList(context, colorScheme, words),
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
            Icons.book_outlined,
            size: 64,
            color: colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            '字典是空的',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(100),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '加入第一個專有名詞吧',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withAlpha(70),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordList(
    BuildContext context,
    ColorScheme colorScheme,
    List<String> words,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withAlpha(30)),
      ),
      child: ListView.separated(
        itemCount: words.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: colorScheme.onSurface.withAlpha(20)),
        itemBuilder: (context, index) {
          final word = words[index];
          return ListTile(
            title: Text(word),
            trailing: IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: colorScheme.onSurface.withAlpha(120),
                size: 24,
              ),
              onPressed: () => ref
                  .read(dictionaryControllerProvider.notifier)
                  .removeWord(word),
            ),
          );
        },
      ),
    );
  }
}
