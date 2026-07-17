import 'package:flutter/material.dart';
import 'package:nnez_yisu/services/app_theme_service.dart';

class AppThemeSettingsPage extends StatelessWidget {
  const AppThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppThemeService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('应用主题')),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '选择应用配色',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '只改变应用界面，不影响桌面小组件的独立主题。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            for (final preset in AppThemePreset.values) ...[
              _ThemePresetTile(
                preset: preset,
                selected: service.preset == preset,
                onTap: () => service.setPreset(preset),
              ),
              if (preset != AppThemePreset.values.last)
                const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = AppThemeConfig.of(preset);
    final previewScheme = ColorScheme.fromSeed(
      seedColor: config.seedColor,
      brightness: config.brightness,
    );
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 52,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: config.scaffoldColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: previewScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: previewScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: previewScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      config.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
