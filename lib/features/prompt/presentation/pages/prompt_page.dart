import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';
import 'package:zero_type/features/prompt/presentation/widgets/prompt_editor.dart';

class PromptPage extends ConsumerWidget {
  const PromptPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speechPrompt = ref.watch(speechPromptControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '提示詞',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '自訂發送給 AI 的系統提示詞',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: PromptEditor(
                title: '語音辨識提示詞',
                subtitle: '提供給語音辨識模型的補充指令',
                icon: Icons.mic,
                value: speechPrompt.value ?? '',
                isLoading: speechPrompt.isLoading,
                onSave: (text) =>
                    ref.read(speechPromptControllerProvider.notifier).save(text),
                onReset: () => ref
                    .read(speechPromptControllerProvider.notifier)
                    .resetToDefault(),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
