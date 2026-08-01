import 'package:flutter/material.dart';
import 'package:zero_type/features/model_config/entities/ai_provider.dart';

class ProviderSection extends StatefulWidget {
  const ProviderSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isRequired,
    required this.providers,
    required this.selectedProviderId,
    required this.selectedModelId,
    required this.apiKey,
    required this.onProviderSelected,
    required this.onModelSelected,
    required this.onApiKeySaved,
    this.isEnabled = true,
    this.onToggleEnabled,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isRequired;
  final bool isEnabled;
  final List<AiProvider> providers;
  final String? selectedProviderId;
  final String? selectedModelId;
  final String apiKey;
  final ValueChanged<String> onProviderSelected;
  final ValueChanged<String> onModelSelected;
  final ValueChanged<String> onApiKeySaved;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  State<ProviderSection> createState() => _ProviderSectionState();
}

class _ProviderSectionState extends State<ProviderSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late TextEditingController _apiKeyController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isRequired;
    _apiKeyController = TextEditingController(text: widget.apiKey);
  }

  @override
  void didUpdateWidget(ProviderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey) {
      _apiKeyController.text = widget.apiKey;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.isRequired || widget.isEnabled;

    return AnimatedOpacity(
      opacity: isActive ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withAlpha(
              _isExpanded && isActive ? 80 : 30,
            ),
          ),
        ),
        child: Column(
          children: [
            _buildHeader(context, colorScheme, isActive),
            if (_isExpanded && isActive) ...[
              const Divider(height: 1),
              _buildContent(context, colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isActive,
  ) {
    return InkWell(
      onTap: isActive ? () => setState(() => _isExpanded = !_isExpanded) : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      if (widget.isRequired) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '必填',
                            style: TextStyle(
                              color: Colors.red[300],
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withAlpha(120),
                        ),
                  ),
                ],
              ),
            ),
            if (!widget.isRequired && widget.onToggleEnabled != null)
              Switch(
                value: widget.isEnabled,
                onChanged: widget.onToggleEnabled,
                activeColor: colorScheme.primary,
              )
            else
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: colorScheme.onSurface.withAlpha(150),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(context, 'Provider'),
          const SizedBox(height: 8),
          _buildProviderChips(context, colorScheme),
          if (widget.selectedProviderId != null) ...[
            const SizedBox(height: 16),
            _buildLabel(context, 'Model'),
            const SizedBox(height: 8),
            _buildModelDropdown(context, colorScheme),
            if (widget.selectedModelId?.endsWith(':free') == true) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange[300]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '免費模型可用性不穩，常因配額或壅塞而失敗，建議僅供測試',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[300],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _buildLabel(context, 'API Key'),
            const SizedBox(height: 8),
            _buildApiKeyField(context, colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
    );
  }

  Widget _buildProviderChips(BuildContext context, ColorScheme colorScheme) {
    return Wrap(
      spacing: 8,
      children: widget.providers.map((provider) {
        final isSelected = provider.id == widget.selectedProviderId;
        return ChoiceChip(
          label: Text(provider.name),
          selected: isSelected,
          onSelected: (_) => widget.onProviderSelected(provider.id),
          selectedColor: colorScheme.primary.withAlpha(50),
          labelStyle: TextStyle(
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withAlpha(50),
          ),
          backgroundColor: Colors.transparent,
        );
      }).toList(),
    );
  }

  Widget _buildModelDropdown(BuildContext context, ColorScheme colorScheme) {
    final selectedProvider = widget.providers
        .where((p) => p.id == widget.selectedProviderId)
        .firstOrNull;
    if (selectedProvider == null) return const SizedBox.shrink();

    return DropdownButtonFormField<String>(
      value: widget.selectedModelId?.isEmpty == true
          ? null
          : widget.selectedModelId,
      decoration: InputDecoration(
        filled: true,
        fillColor: colorScheme.surface.withAlpha(200),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha(50)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.onSurface.withAlpha(50)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintText: '選擇模型',
      ),
      items: selectedProvider.models
          .map(
            (m) => DropdownMenuItem(
              value: m.id,
              child: Text(
                m.id.endsWith(':free') ? '${m.name}（免費，可用性不穩）' : m.name,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) widget.onModelSelected(v);
      },
      dropdownColor: Colors.grey[900],
      borderRadius: BorderRadius.circular(10),
    );
  }

  Widget _buildApiKeyField(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surface.withAlpha(200),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: colorScheme.onSurface.withAlpha(50)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: colorScheme.onSurface.withAlpha(50)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.primary),
              ),
              hintText: 'sk-••••••••••••••••',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: colorScheme.onSurface.withAlpha(120),
                ),
                onPressed: () =>
                    setState(() => _obscureApiKey = !_obscureApiKey),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => widget.onApiKeySaved(_apiKeyController.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('儲存'),
        ),
      ],
    );
  }
}
