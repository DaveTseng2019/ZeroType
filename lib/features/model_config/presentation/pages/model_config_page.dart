import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import '../controllers/model_config_controller.dart';
import '../../entities/ai_provider.dart';

class ModelConfigPage extends ConsumerWidget {
  const ModelConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(providersConfigProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: providersAsync.when(
        data: (config) => SingleChildScrollView(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '模型',
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '設定語音辨識所使用的模型與 API Key',
                style: tt.bodyMedium?.copyWith(color: cs.onSurface.withAlpha(150)),
              ),
              const SizedBox(height: 32),
              
              _ConfigSection(
                title: '語音辨識',
                isRequired: true,
                child: _SpeechConfigSection(providers: config.speechRecognition),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('載入失敗: $err')),
      ),
    );
  }
}

class _ConfigSection extends StatefulWidget {
  const _ConfigSection({
    required this.title,
    required this.isRequired,
    required this.child,
  });

  final String title;
  final bool isRequired;
  final Widget child;

  @override
  State<_ConfigSection> createState() => _ConfigSectionState();
}

class _ConfigSectionState extends State<_ConfigSection> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.onSurface.withAlpha(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 22),
                  ),
                  if (widget.isRequired) ...[
                    const SizedBox(width: 4),
                    const Text('*', style: TextStyle(color: Colors.redAccent, fontSize: 18)),
                  ],
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurface.withAlpha(150),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: widget.child,
            ),
          ],
        ],
      ),
    );
  }
}

class _SpeechConfigSection extends ConsumerWidget {
  const _SpeechConfigSection({required this.providers});
  final List<AiProvider> providers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(speechProviderControllerProvider);
    final cs = Theme.of(context).colorScheme;

    return stateAsync.when(
      data: (state) {
        final selectedProvider = providers.firstWhere(
          (p) => p.id == state.providerId,
          orElse: () => providers.first,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('選擇 Provider', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                if (selectedProvider.url != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(selectedProvider.url!),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text('${selectedProvider.name} 官方網站'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: providers.map((p) {
                final isSelected = p.id == state.providerId;
                return ChoiceChip(
                  label: Text(p.name),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) {
                      ref.read(speechProviderControllerProvider.notifier).selectProvider(p.id);
                    }
                  },
                  backgroundColor: cs.surface,
                  selectedColor: cs.primary.withAlpha(50),
                  labelStyle: TextStyle(
                    color: isSelected ? cs.primary : cs.onSurface.withAlpha(150),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? cs.primary : cs.onSurface.withAlpha(30),
                  ),
                );
              }).toList(),
            ),
            // 本機服務商沒有金鑰可填，也沒有可測試的對象，整塊隱藏。
            if (state.providerId != 'local') ...[
              const SizedBox(height: 24),
              _ApiKeyInput(
                providerId: state.providerId ?? '',
                initialValue: state.apiKey ?? '',
                onSave: (val) => ref.read(speechProviderControllerProvider.notifier).saveApiKey(val),
              ),
            ] else ...[
              const SizedBox(height: 24),
              // key 綁著模型 id：換服務商或換模型都會重建這個面板，
              // 於是 initState 會重新探一次端點狀態。使用者剛點過模型時，
              // 最想知道的就是「那個模型現在跑得起來嗎」。
              _LocalProviderPanel(key: ValueKey('local-${state.modelId}')),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('選擇模型', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('(必填)', style: TextStyle(color: Colors.redAccent.withAlpha(150), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            _ModelDropdown(
              models: selectedProvider.models,
              selectedModelId: state.modelId,
              onChanged: (val) {
                if (val != null) {
                  ref.read(speechProviderControllerProvider.notifier).selectModel(val);
                }
              },
            ),
            const SizedBox(height: 24),
            _AdvancedConfigSection(
              providerId: state.providerId ?? '',
              customEndpoint: state.customEndpoint ?? '',
              onSaveCustomEndpoint: (val) => ref.read(speechProviderControllerProvider.notifier).saveCustomEndpoint(val),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      error: (err, _) => Text('錯誤: $err'),
    );
  }
}


/// 本機服務商沒有金鑰欄位。這裡取而代之的是端點狀態、手動開關，
/// 以及「要不要隨 ZeroType 一起啟動」。
///
/// notes: 本機模型常駐約 1.8 GB VRAM。不用的時候要能收回來，所以停止鍵是必要的，
///        不是方便性功能。
class _LocalProviderPanel extends StatefulWidget {
  const _LocalProviderPanel({super.key});

  @override
  State<_LocalProviderPanel> createState() => _LocalProviderPanelState();
}

class _LocalProviderPanelState extends State<_LocalProviderPanel> {
  /// null 表示還在確認。
  bool? _running;
  bool _busy = false;
  late bool _autoStart;
  late bool _showConsole;
  bool _logOpen = false;
  List<String> _log = const [];
  Timer? _poll;
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    _autoStart = appPrefs.getBool(AppConstants.localSttAutoStartKey) ?? true;
    _showConsole =
        appPrefs.getBool(AppConstants.localSttShowConsoleKey) ?? false;
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }

  /// 展開時每兩秒重讀一次，講完一句就能在這裡看到結果；收合就停掉。
  void _toggleLog() {
    setState(() => _logOpen = !_logOpen);
    _logTimer?.cancel();
    if (!_logOpen) return;
    _refresh();
    _logTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _log = localSttService.readLog());
    });
  }

  /// 狀態與記錄一起更新。使用者按「重新檢查」時想知道的就是這兩件事。
  Future<void> _refresh() async {
    final healthy = await localSttService.isHealthy();
    final log = localSttService.readLog();
    if (mounted) {
      setState(() {
        _running = healthy;
        _log = log;
      });
    }
  }

  /// 模型載進 GPU 要十秒上下，按下啟動後得持續探測，不然畫面會停在「未啟動」。
  void _pollUntilRunning() {
    _poll?.cancel();
    var elapsed = 0;
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      elapsed += 2;
      final healthy = await localSttService.isHealthy();
      final log = localSttService.readLog();
      if (!mounted) return timer.cancel();
      setState(() {
        _running = healthy;
        _log = log;
      });
      if (healthy || elapsed >= 60) {
        timer.cancel();
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    await localSttService.ensureRunning();
    _pollUntilRunning();
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    _poll?.cancel();
    await localSttService.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _running;
    // 找不到辨識程式、或記著的路徑已經不存在，就不給啟動鍵——按了也只會失敗。
    final installed = localSttService.canLaunch;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running == true ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: running == true ? Colors.green : cs.onSurface.withAlpha(100),
              ),
              const SizedBox(width: 8),
              Text(
                running == null
                    ? '本機端點：確認中…'
                    : (running ? '本機端點：執行中' : '本機端點：未啟動'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(width: 8),
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const Spacer(),
              IconButton(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: '重新檢查',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              // 端點在跑但我們不知道它怎麼啟動的（外部啟動）：兩個鍵都不給。
              // 停止鍵打得到 /shutdown，但關掉別人啟動的服務不是我們的事。
              if (running == true && installed)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _stop,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )
              else if (running != true)
                ElevatedButton.icon(
                  onPressed: _busy || !installed ? null : _start,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('啟動'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '本機辨識不需要 API Key，也不會產生費用，但模型常駐約 1.8 GB 顯示記憶體。'
            '${installed ? '暫時不用本機辨識時按「停止」就能收回。' : ''}',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(180), height: 1.5),
          ),
          if (!installed) ...[
            const SizedBox(height: 12),
            _LocalNotInstalledNotice(endpointRunning: running == true),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('隨 ZeroType 一起啟動',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '只有在服務商選「本機」時才會啟動。關閉 ZeroType 時一併關掉。',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoStart,
                onChanged: (val) {
                  setState(() => _autoStart = val);
                  appPrefs.setBool(AppConstants.localSttAutoStartKey, val);
                },
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('啟動時顯示主控台視窗',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '關閉時端點在背景執行，不會有視窗被誤關。'
                      '下次啟動端點才生效；平常看訊息請用下面的「端點記錄」。',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _showConsole,
                onChanged: (val) {
                  setState(() => _showConsole = val);
                  appPrefs.setBool(AppConstants.localSttShowConsoleKey, val);
                },
              ),
            ],
          ),
          const Divider(height: 24),
          const _LocalLaunchSettings(),
          const Divider(height: 24),
          Row(
            children: [
              const Text('端點記錄',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '每一句的耗時與結果',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
              ),
              const Spacer(),
              TextButton(
                onPressed: _toggleLog,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: Text(_logOpen ? '收合' : '展開'),
              ),
            ],
          ),
          if (_logOpen) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.isEmpty
                      ? '（還沒有記錄。端點啟動後才會寫入。）'
                      : _log.join('\n'),
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.6,
                    color: cs.onSurface.withAlpha(200),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApiKeyInput extends ConsumerStatefulWidget {
  const _ApiKeyInput({
    required this.providerId,
    required this.initialValue,
    required this.onSave,
  });

  final String providerId;
  final String initialValue;
  final Function(String) onSave;

  @override
  ConsumerState<_ApiKeyInput> createState() => _ApiKeyInputState();
}

class _ApiKeyInputState extends ConsumerState<_ApiKeyInput> {
  late final TextEditingController _controller;
  bool _obscureText = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_ApiKeyInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.providerId != oldWidget.providerId || widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('API Key', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(width: 4),
            const Text('*', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('(必填)', style: TextStyle(color: Colors.redAccent.withAlpha(150), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: _obscureText,
                decoration: InputDecoration(
                  hintText: '輸入 ${widget.providerId} API Key',
                  hintStyle: TextStyle(color: cs.onSurface.withAlpha(80)),
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off, size: 24),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                widget.onSave(_controller.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API Key 已儲存'), duration: Duration(seconds: 1)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              child: const Text('儲存'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              child: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('測試'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('清除這個 Provider 的 API Key'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ),
      ],
    );
  }

  /// 打各家最便宜的 GET 驗證金鑰，不送音訊、不耗 token
  Future<void> _test() async {
    setState(() => _testing = true);
    final error = await ref
        .read(speechProviderControllerProvider.notifier)
        .testApiKey(_controller.text);
    if (!mounted) return;
    setState(() => _testing = false);
    // 測試結果用聲音也講一次：成功＝辨識完成音效，失敗＝失敗音效，跟實際辨識時聽到的一致
    unawaited(error == null
        ? soundService.playStopSound()
        : soundService.playFailedSound());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'API Key 可用'),
        backgroundColor: error == null ? null : Theme.of(context).colorScheme.error,
        duration: Duration(seconds: error == null ? 2 : 5),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 API Key'),
        content: Text('確定要刪除 ${widget.providerId} 已儲存的 API Key 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(speechProviderControllerProvider.notifier).clearApiKey();
    if (!mounted) return;
    _controller.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key 已清除'), duration: Duration(seconds: 1)),
    );
  }
}

/// 1.50 → "1.5"、2.00 → "2"，並吸收浮點誤差（0.3999… → "0.4"）
String _trimZero(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.models,
    required this.selectedModelId,
    required this.onChanged,
  });

  final List<AiModel> models;
  final String? selectedModelId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withAlpha(30)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: models.any((m) => m.id == selectedModelId) ? selectedModelId : null,
          isExpanded: true,
          hint: const Text('選擇一個模型'),
          itemHeight: null,
          // 收合時只顯示名稱，展開才顯示費率
          selectedItemBuilder: (_) =>
              models.map((m) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(m.name),
                  )).toList(),
          items: models.map((m) {
            final pricing = kModelPricing[m.id];
            final inPerM = m.inputPerM ?? pricing?.inputPerM;
            final outPerM = m.outputPerM ?? pricing?.outputPerM;
            final recommended = m.recommended;
            return DropdownMenuItem(
              value: m.id,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(m.name)),
                        if (recommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primary.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '推薦',
                              style: TextStyle(
                                  fontSize: 11, color: cs.primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (inPerM != null && outPerM != null)
                      Text(
                        inPerM == 0 && outPerM == 0
                            ? '免費'
                            : '輸入 \$${_trimZero(inPerM)}／輸出 \$${_trimZero(outPerM)}（每百萬 token）',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withAlpha(160),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CustomEndpointInput extends StatefulWidget {
  const _CustomEndpointInput({
    required this.providerId,
    required this.initialValue,
    required this.onSave,
  });

  final String providerId;
  final String initialValue;
  final Function(String) onSave;

  @override
  State<_CustomEndpointInput> createState() => _CustomEndpointInputState();
}

class _CustomEndpointInputState extends State<_CustomEndpointInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(_CustomEndpointInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.providerId != oldWidget.providerId || widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('自建模型接口', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '非必填',
                  hintStyle: TextStyle(color: cs.onSurface.withAlpha(80)),
                  filled: true,
                  fillColor: cs.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                  ),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () {
                widget.onSave(_controller.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('接口設定已儲存'), duration: Duration(seconds: 1)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              child: const Text('儲存'),
            ),
          ],
        ),
      ],
    );
  }
}


/// 這台機器上沒有本機辨識程式時顯示的說明。
///
/// notes: 不要在這裡叫使用者去填路徑。不熟電腦的人不知道 venv 是什麼，
///        填錯路徑只會得到一個「啟動失敗」。給一段可以直接貼給 AI 或工程師的字，
///        裝完了 ZeroType 會自己找到。
class _LocalNotInstalledNotice extends StatelessWidget {
  const _LocalNotInstalledNotice({required this.endpointRunning});

  /// 端點連得上。可以假設端點存在，但不能假設它裝在哪——裝在自動搜尋範圍外
  /// 又用排程自啟的人，辨識是好的，只是 ZeroType 管不到它。
  final bool endpointRunning;

  /// notes: 說明只寫「一定是這樣」的事。絕對路徑、port、虛擬環境的資料夾名稱
  ///        都是可以改的值，寫進去只會讓照做的人在別台機器上撞牆，而且這個 repo
  ///        是公開的，不該出現任何一台機器的實際路徑。
  static const _instructions = '請幫我在這台 Windows 電腦上安裝 ZeroType 的本機語音辨識端點：\n'
      '\n'
      '  git clone https://github.com/DaveTseng2019/LocalSTT.git\n'
      '\n'
      '1. 把它放到使用者資料夾底下，資料夾名稱保持 LocalSTT。\n'
      '2. 照該專案 README 的「重建虛擬環境」建立 Python 虛擬環境並安裝相依套件。\n'
      '3. 確認可以用該虛擬環境執行 shim.py。\n'
      '放在這個位置 ZeroType 會自動找到，我不必填任何設定。';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              endpointRunning
                  ? 'ZeroType 找不到本機辨識程式'
                  : '這台電腦上還沒有本機辨識程式',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14, color: cs.primary)),
          const SizedBox(height: 6),
          Text(
            endpointRunning
                ? '端點連得上，辨識可以正常使用。但辨識程式不在 ZeroType 會找的位置，'
                    '所以無法啟動或停止這個服務，只負責連線。'
                    '要交給 ZeroType 管，把程式的完整路徑填進下面的「啟動設定（進階）」。'
                : '本機辨識要另外裝一個小程式。複製下面的說明，貼給 AI 助理或請人代勞；裝好之後這裡會變成「未啟動」，按啟動即可。',
            style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(180), height: 1.5),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: _instructions));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('安裝說明已複製，貼給 AI 助理就可以了'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('複製安裝說明'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 端點的啟動方式。預設是這台機器上的 LocalSTT，但本機模型不會只有一種，
/// 所以路徑、參數與記錄檔都要能改。
///
/// notes: 端點位址不放在這裡。那一份在「進階設定 → 自建模型接口」，
///        辨識請求與 /health、/shutdown 共用同一個值，不要開第二個欄位。
class _LocalLaunchSettings extends StatefulWidget {
  const _LocalLaunchSettings();

  @override
  State<_LocalLaunchSettings> createState() => _LocalLaunchSettingsState();
}

class _LocalLaunchSettingsState extends State<_LocalLaunchSettings> {
  late final TextEditingController _program;
  late final TextEditingController _arguments;
  late final TextEditingController _logPath;

  @override
  void initState() {
    super.initState();
    // 欄位放的是「使用者自己填過的值」，通常是空的。
    // 空欄位由 hintText 顯示自動偵測到的路徑，讓人知道不填也會動。
    _program = TextEditingController(
        text: appPrefs.getString(AppConstants.localSttProgramKey) ?? '');
    _arguments = TextEditingController(
        text: appPrefs.getString(AppConstants.localSttArgumentsKey) ?? '');
    _logPath = TextEditingController(
        text: appPrefs.getString(AppConstants.localSttLogPathKey) ?? '');
  }

  @override
  void dispose() {
    _program.dispose();
    _arguments.dispose();
    _logPath.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await localSttService.saveLaunchSettings(
      program: _program.text,
      arguments: _arguments.text,
      logPath: _logPath.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('啟動設定已儲存，下次啟動端點時生效'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 空欄位顯示自動偵測的結果。這三個欄位平常不該有人去動。
  String _hint(String detected) =>
      detected.isEmpty ? '自動找不到，要用的話請填完整路徑' : '自動：$detected';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget field(String label, String hint, TextEditingController controller) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: cs.onSurface.withAlpha(80), fontSize: 12),
                filled: true,
                fillColor: cs.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.onSurface.withAlpha(30)),
                ),
              ),
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text('啟動設定（進階）',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          '平常不用動。ZeroType 會自己找辨識程式；只有要換成別的本機模型才填這裡。',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          field('啟動程式', _hint(localSttService.program), _program),
          field('啟動參數', _hint(localSttService.arguments), _arguments),
          field('記錄檔', _hint(localSttService.logPath), _logPath),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('儲存'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedConfigSection extends StatelessWidget {
  const _AdvancedConfigSection({
    required this.providerId,
    required this.customEndpoint,
    required this.onSaveCustomEndpoint,
  });

  final String providerId;
  final String customEndpoint;
  final Function(String) onSaveCustomEndpoint;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text(
          '進階設定',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        tilePadding: EdgeInsets.zero,
        expandedAlignment: Alignment.centerLeft,
        children: [
          _CustomEndpointInput(
            providerId: providerId,
            initialValue: customEndpoint,
            onSave: onSaveCustomEndpoint,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
