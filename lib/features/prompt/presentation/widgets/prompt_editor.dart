import 'package:flutter/material.dart';

class PromptEditor extends StatefulWidget {
  const PromptEditor({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onSave,
    required this.onReset,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String value;
  final bool isLoading;
  final Future<String> Function(String) onSave;
  final Future<String> Function() onReset;

  @override
  State<PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<PromptEditor> {
  late TextEditingController _controller;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(PromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value;
      _isDirty = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header ---
          Padding(
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
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 22,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withAlpha(120),
                              fontSize: 16,
                            ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('還原預設'),
                  onPressed: () async {
                    final newVal = await widget.onReset();
                    setState(() {
                      _isDirty = false;
                      _controller.text = newVal;
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // --- Editor body ---
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        onChanged: (_) => setState(() => _isDirty = true),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colorScheme.surface.withAlpha(100),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.onSurface.withAlpha(40),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: colorScheme.onSurface.withAlpha(40),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colorScheme.primary),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.6,
                              fontSize: 18,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isDirty
                            ? () async {
                                final newVal = await widget.onSave(_controller.text);
                                setState(() {
                                  _isDirty = false;
                                  _controller.text = newVal;
                                });
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('儲存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
