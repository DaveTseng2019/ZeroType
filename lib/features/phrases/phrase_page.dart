import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/features/phrases/phrase_controller.dart';
import 'package:zero_type/shared/widgets/action_icon.dart';

class PhrasePage extends ConsumerStatefulWidget {
  const PhrasePage({super.key});

  @override
  ConsumerState<PhrasePage> createState() => _PhrasePageState();
}

class _PhrasePageState extends ConsumerState<PhrasePage> {
  // 點一列選取它，F2 才知道要改哪一句；再開始編輯時把那一列換成輸入框。
  int? _selectedIndex;
  int? _editingIndex;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();
  final _listFocus = FocusNode();

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _selectedIndex = index);
    _listFocus.requestFocus();
  }

  void _startEdit(int index, String current) {
    setState(() {
      _selectedIndex = index;
      _editingIndex = index;
      _editController.text = current;
    });
    // 等這一幀的輸入框長出來再搶焦點，並整段選起來方便直接改
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocus.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _cancelEdit() {
    setState(() => _editingIndex = null);
    _listFocus.requestFocus();
  }

  Future<void> _commitEdit() async {
    final index = _editingIndex;
    if (index == null) return;
    final ok = await ref
        .read(phraseControllerProvider.notifier)
        .edit(index, _editController.text);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('沒有修改：內容空白或與其他詞彙重複'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    setState(() => _editingIndex = null);
    _listFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
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
              'Alt+C 叫選擇器　↑↓ 選取　F2 修改　Enter 存　Esc 取消　拖把手排序',
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
                    : _buildList(context, colorScheme, phrases),
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
    ColorScheme colorScheme,
    List<String> phrases,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withAlpha(30)),
      ),
      // 選好一列後，F2 把它換成輸入框。焦點在清單上時這一層才收得到按鍵。
      child: Focus(
        focusNode: _listFocus,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || _editingIndex != null) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          // F2：改目前選取的那一列
          if (key == LogicalKeyboardKey.f2 &&
              _selectedIndex != null &&
              _selectedIndex! < phrases.length) {
            _startEdit(_selectedIndex!, phrases[_selectedIndex!]);
            return KeyEventResult.handled;
          }
          // ↑/↓：移動選取列（還沒選時，↓ 從第一列、↑ 從最後一列開始）
          if (key == LogicalKeyboardKey.arrowDown) {
            final next =
                _selectedIndex == null ? 0 : _selectedIndex! + 1;
            if (next < phrases.length) setState(() => _selectedIndex = next);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            final prev = _selectedIndex == null
                ? phrases.length - 1
                : _selectedIndex! - 1;
            if (prev >= 0) setState(() => _selectedIndex = prev);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ReorderableListView.builder(
          itemCount: phrases.length,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) => ref
              .read(phraseControllerProvider.notifier)
              .reorder(oldIndex, newIndex),
          itemBuilder: (context, index) {
            final phrase = phrases[index];
            final editing = _editingIndex == index;
            final selected = _selectedIndex == index;
            return Container(
              // 詞彙去重後唯一，拿字面當 key 即可
              key: ValueKey(phrase),
              decoration: BoxDecoration(
                color: selected && !editing
                    ? colorScheme.primary.withAlpha(20)
                    : null,
                border: index == phrases.length - 1
                    ? null
                    : Border(
                        bottom: BorderSide(
                            color: colorScheme.onSurface.withAlpha(20))),
              ),
              child: ListTile(
                selected: selected,
                onTap: editing ? null : () => _select(index),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_indicator,
                      color: colorScheme.onSurface.withAlpha(120)),
                ),
                title: editing
                    ? _buildEditor(colorScheme)
                    : Text(phrase,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: editing
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ActionIcon(
                            icon: Icons.edit_outlined,
                            tooltip: '修改（F2）',
                            onTap: () => _startEdit(index, phrase),
                          ),
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
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEditor(ColorScheme colorScheme) {
    // Esc 取消交給這一層攔（TextField 不會吃掉 Escape），Enter 走 onSubmitted。
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
      },
      child: TextField(
        controller: _editController,
        focusNode: _editFocus,
        // 單行才能用 Enter 送出（maxLines:null 時 Enter 會換行）；多行內容用「編輯檔案」
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onSubmitted: (_) => _commitEdit(),
        onTapOutside: (_) => _commitEdit(),
      ),
    );
  }
}
