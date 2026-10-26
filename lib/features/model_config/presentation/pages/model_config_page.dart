import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/services/local_stt_service.dart'
    show LocalSttHealth, LocalSttRestart, kLocalEngineModelIds;
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
            // 模型選單放在金鑰／本機端點之前：先選模型，再看那個模型怎麼連、跑不跑得起來。
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
              providerId: selectedProvider.id,
              models: selectedProvider.models,
              selectedModelId: state.modelId,
              onChanged: (val) {
                if (val != null) {
                  ref.read(speechProviderControllerProvider.notifier).selectModel(val);
                }
              },
            ),
            // Azure 沒有共用的預設位址，端點是必填，所以從進階設定拉出來放在金鑰前面。
            if (state.providerId == 'azure') ...[
              const SizedBox(height: 24),
              _CustomEndpointInput(
                providerId: 'azure',
                initialValue: state.customEndpoint ?? '',
                onSave: (val) => ref.read(speechProviderControllerProvider.notifier).saveCustomEndpoint(val),
              ),
            ],
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
              // notes: key 不綁模型 id。換模型要在 didUpdateWidget 裡重啟端點，
              //        重建面板就分不出「剛打開頁面」和「剛換了模型」。
              _LocalProviderPanel(
                key: const ValueKey('local'),
                selectedModelId: state.modelId,
              ),
            ],
            if (state.providerId != 'azure') ...[
              const SizedBox(height: 24),
              _AdvancedConfigSection(
                providerId: state.providerId ?? '',
                customEndpoint: state.customEndpoint ?? '',
                onSaveCustomEndpoint: (val) => ref.read(speechProviderControllerProvider.notifier).saveCustomEndpoint(val),
              ),
            ],
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
/// 套用啟動設定之後給使用者看的一句話。存設定與換模型共用。
String _restartMessage(LocalSttRestart result, {required String what}) =>
    switch (result) {
      LocalSttRestart.notRunning => '$what，下次啟動端點時生效',
      LocalSttRestart.restarted => '$what，正在重新啟動端點',
      LocalSttRestart.notLaunchable => '$what，但找不到啟動程式，端點沒有重啟。請到「啟動設定（進階）」填路徑',
      LocalSttRestart.stuck => '$what，但舊端點沒有結束，請按「停止」後再啟動',
    };

class _LocalProviderPanel extends StatefulWidget {
  const _LocalProviderPanel({super.key, required this.selectedModelId});

  /// 模型選單選的那一個。換了就用那個模型的啟動設定重啟端點。
  final String? selectedModelId;

  @override
  State<_LocalProviderPanel> createState() => _LocalProviderPanelState();
}

class _LocalProviderPanelState extends State<_LocalProviderPanel> {
  /// null 表示還在確認。
  bool? _running;

  /// 最近一次 /health 的內容，用來顯示啟動時間。
  LocalSttHealth? _health;
  bool _busy = false;
  late bool _autoStart;
  late bool _showConsole;
  bool _logOpen = false;
  List<String> _log = const [];
  Timer? _poll;

  /// 按下啟動後，等模型載入的最晚時間。null＝現在沒有在等。
  DateTime? _startDeadline;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _autoStart = appPrefs.getBool(AppConstants.localSttAutoStartKey) ?? true;
    _showConsole =
        appPrefs.getBool(AppConstants.localSttShowConsoleKey) ?? false;
  }

  /// 頁面一顯示就查一次，顯示期間每兩秒再查一次；切到別的頁就停。
  ///
  /// notes: 狀態不能只在 initState 查一次。main_shell 用 IndexedStack，七個頁面在
  ///        開視窗那一刻全部建好，那時端點還在載模型（自動啟動約 20 秒），
  ///        於是畫面寫著「未啟動」卻辨識得出結果，除非使用者自己按重新檢查。
  ///        端點也可能是講話時被 ensureRunning 拉起來的，那更不會經過這個頁面。
  /// notes: Visibility.of 會把這個 widget 登記成 IndexedStack 可見性的相依，
  ///        切分頁就會回到這裡——不必從 main_shell 拉一條線進來。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible == _visible) return;
    _visible = visible;
    _poll?.cancel();
    if (!visible) return;
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 選單換了模型：端點在跑、而且跑的不是新選的那個，就用新模型的設定重啟。
  ///
  /// notes: 端點沒回報引擎（舊版 shim、別的端點）時分不出跑的是誰，一律重啟。
  @override
  void didUpdateWidget(covariant _LocalProviderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final model = widget.selectedModelId;
    if (model == null || model == oldWidget.selectedModelId) return;
    if (_runningModelId == model) return;
    // didUpdateWidget 在 build 階段裡，這時不能 setState；等這一格畫完再做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _switchModel(kModelNames[model] ?? model);
    });
  }

  Future<void> _switchModel(String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await _applyLaunchSettings();
    // 端點沒在跑就不必說什麼：下次啟動自然用新模型。
    if (result == LocalSttRestart.notRunning) return;
    messenger.showSnackBar(SnackBar(
      content: Text(_restartMessage(result, what: '已換成 $name')),
      duration: const Duration(seconds: 3),
    ));
  }

  void _onLogExpanded(bool open) {
    setState(() => _logOpen = open);
    if (open) _refresh();
  }

  /// 狀態與記錄一起更新。使用者按「重新檢查」時想知道的就是這兩件事。
  ///
  /// 記錄只在展開時讀——收起來的時候沒人看得到，不必每兩秒開一次檔。
  Future<void> _refresh() async {
    final health = await localSttService.health();
    final healthy = health?.ok ?? false;
    final log = _logOpen ? localSttService.readLog() : _log;
    if (!mounted) return;
    final deadline = _startDeadline;
    setState(() {
      _running = healthy;
      _health = health;
      _log = log;
      // 模型載進 GPU 要十秒上下；起來了、或等過頭了，就把轉圈圈收掉。
      if (deadline != null && (healthy || DateTime.now().isAfter(deadline))) {
        _startDeadline = null;
        _busy = false;
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _startDeadline = DateTime.now().add(const Duration(seconds: 60));
    });
    await localSttService.ensureRunning();
    await _refresh();
  }

  Future<void> _stop() async {
    setState(() {
      _busy = true;
      _startDeadline = null;
    });
    await localSttService.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  /// 啟動設定存好之後：端點正在跑就用新設定重啟，讓設定立刻生效。
  ///
  /// notes: 重啟途中不設 _startDeadline。每兩秒的 _refresh 會在舊端點還活著時看到
  ///        healthy，有 deadline 就會把轉圈圈收掉、按鈕放回來；等新端點拉起來才設。
  Future<LocalSttRestart> _applyLaunchSettings() async {
    setState(() {
      _busy = true;
      _startDeadline = null;
    });
    final result = await localSttService.restartIfRunning();
    if (!mounted) return result;
    setState(() {
      if (result == LocalSttRestart.restarted) {
        _startDeadline = DateTime.now().add(const Duration(seconds: 60));
      } else {
        _busy = false;
      }
    });
    await _refresh();
    return result;
  }

  /// 「啟動於 11:37:03，載入 10.0 秒」。端點沒回報啟動時間（舊版 shim）就是 null。
  String? _startedText() {
    final at = _health?.startedAt;
    if (at == null) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final when = '${sameDay ? '' : '${at.month}/${at.day} '}'
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    final load = _health?.loadSeconds;
    return load == null ? '啟動於 $when' : '啟動於 $when，載入 ${load.toStringAsFixed(1)} 秒';
  }

  /// 端點實際跑的模型 id。端點沒回報引擎、或引擎沒有對應的選單項目，就是 null。
  String? get _runningModelId => kLocalEngineModelIds[_health?.engine];

  /// 「FireRedASR2-AED」。認不得的引擎直接顯示引擎名稱。
  String? _runningModelName() {
    final engine = _health?.engine;
    if (engine == null) return null;
    final id = _runningModelId;
    return id == null ? engine : (kModelNames[id] ?? id);
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
                    : (running
                        ? '本機端點：執行中'
                            '${_runningModelName() == null ? '' : '（${_runningModelName()}）'}'
                        : '本機端點：未啟動'),
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
          if (running == true && _startedText() != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                _startedText()!,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
              ),
            ),
          ],
          // 換模型會自動重啟，平常不會不一致。會出現代表重啟沒成功（舊端點關不掉、
          // 新模型找不到程式），或端點是外部啟動的。講出來，免得以為已經切過去了。
          if (running == true &&
              _runningModelId != null &&
              widget.selectedModelId != null &&
              _runningModelId != widget.selectedModelId) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                '端點跑的是 ${_runningModelName()}，跟上面選的模型不同。'
                '按「停止」再按「啟動」就會換成上面選的模型。',
                style: const TextStyle(fontSize: 13, color: Colors.orange, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '本機辨識不需要 API Key，但模型常駐會佔用顯示記憶體。'
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
          // key 綁模型 id：換模型時輸入框要換成那個模型自己的設定。
          _LocalLaunchSettings(
            key: ValueKey('launch-${widget.selectedModelId}'),
            onSaved: _applyLaunchSettings,
          ),
          const Divider(height: 24),
          // 展開方式跟上面的「啟動設定」一致：同一張卡片裡只用一種展開控制項。
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  const Text('端點記錄',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    '每一句的耗時與結果',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150)),
                  ),
                ],
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              onExpansionChanged: _onLogExpanded,
              children: [
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
            ),
          ),
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
    required this.providerId,
    required this.models,
    required this.selectedModelId,
    required this.onChanged,
  });

  final String providerId;
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
            final pricing = modelPrice(providerId, m.id);
            final inPerM = m.inputPerM ?? pricing?.inputPerM;
            final outPerM = m.outputPerM ?? pricing?.outputPerM;
            final audioPerM = m.inputPerM == null ? pricing?.audioInputPerM : null;
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
                            : audioPerM != null
                                ? '音訊輸入 \$${_trimZero(audioPerM)}／文字輸入 \$${_trimZero(inPerM)}／輸出 \$${_trimZero(outPerM)}（每百萬 token）'
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
    final isAzure = widget.providerId == 'azure';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isAzure) ...[
          Row(
            children: [
              const Text('Azure 資源端點', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('(必填)', style: TextStyle(color: Colors.redAccent.withAlpha(150), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '模型選單的名稱要和 Azure 上的部署名稱相同。',
            style: TextStyle(color: cs.onSurface.withAlpha(150), fontSize: 12),
          ),
        ] else
          const Text('自建模型接口', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: isAzure ? 'https://<資源名稱>.openai.azure.com' : '非必填',
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
  const _LocalLaunchSettings({super.key, required this.onSaved});

  /// 設定寫進 prefs 之後呼叫，回報端點那邊怎麼處理。
  final Future<LocalSttRestart> Function() onSaved;

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
    _program = TextEditingController(text: localSttService.customProgram);
    _arguments = TextEditingController(text: localSttService.customArguments);
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
    final result = await widget.onSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_restartMessage(result, what: '啟動設定已儲存')),
        duration: const Duration(seconds: 3),
      ),
    );
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
          '每個本機模型各有一份，這裡是「${kModelNames[localSttService.modelId] ?? localSttService.modelId}」的。'
          '換模型用上面的選單；只有第一次設定路徑時才需要填這裡。',
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
