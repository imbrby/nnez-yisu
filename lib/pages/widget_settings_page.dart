import 'package:flutter/material.dart';
import 'package:nnez_yisu/services/widget_service.dart';

class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  CanteenWidgetPreferences? _preferences;
  CanteenWidgetSnapshot? _snapshot;
  bool _canPin = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      WidgetService.loadPreferences(),
      WidgetService.loadSnapshot(),
      WidgetService.canPinWidgets(),
    ]);
    if (!mounted) return;
    setState(() {
      _preferences = results[0] as CanteenWidgetPreferences;
      _snapshot = results[1] as CanteenWidgetSnapshot;
      _canPin = results[2] as bool;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: preferences == null || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _OverviewPreview(preferences: preferences, snapshot: snapshot),
                const SizedBox(height: 28),
                Text('纸张色调', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  children: CanteenWidgetTheme.values
                      .map(
                        (theme) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: theme == CanteenWidgetTheme.ink ? 0 : 8,
                            ),
                            child: _ThemeChoice(
                              theme: theme,
                              selected: preferences.theme == theme,
                              onTap: _saving
                                  ? null
                                  : () => _update(
                                      preferences.copyWith(theme: theme),
                                    ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 28),
                Text('展示内容', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.hideBalance,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            _update(preferences.copyWith(hideBalance: value)),
                  title: const Text('隐藏余额'),
                  subtitle: const Text('在桌面上用圆点遮住金额'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showStudentName,
                  onChanged: _saving
                      ? null
                      : (value) => _update(
                          preferences.copyWith(showStudentName: value),
                        ),
                  title: const Text('显示姓名'),
                  subtitle: const Text('适合只有自己使用的设备'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showTodaySpend,
                  onChanged: _saving
                      ? null
                      : (value) => _update(
                          preferences.copyWith(showTodaySpend: value),
                        ),
                  title: const Text('显示今日消费'),
                  subtitle: const Text('影响常用的余额简卡'),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择组件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (!_canPin)
                      Text(
                        '请在桌面组件列表中添加',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _WidgetKindRow(
                  title: '余额简卡',
                  description: '2 × 1 · 姓名、余额、今日消费与更新时间',
                  icon: Icons.account_balance_wallet_outlined,
                  onAdd: () => _pin(CanteenWidgetKind.balance),
                ),
                const Divider(height: 1),
                _WidgetKindRow(
                  title: '消费概览',
                  description: '4 × 2 · 本月充值、消费与记录数',
                  icon: Icons.receipt_long_outlined,
                  onAdd: () => _pin(CanteenWidgetKind.overview),
                ),
                const Divider(height: 1),
                _WidgetKindRow(
                  title: '余额续航',
                  description: '2 × 2 · 预计可用天数与当前余额',
                  icon: Icons.energy_savings_leaf_outlined,
                  onAdd: () => _pin(CanteenWidgetKind.endurance),
                ),
              ],
            ),
    );
  }

  Future<void> _update(CanteenWidgetPreferences preferences) async {
    setState(() {
      _preferences = preferences;
      _saving = true;
    });
    try {
      await WidgetService.savePreferences(preferences);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存小组件设置失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pin(CanteenWidgetKind kind) async {
    if (!_canPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前桌面不支持一键添加，请长按桌面后从组件列表添加。')),
      );
      return;
    }
    await WidgetService.requestPin(kind);
  }
}

class _OverviewPreview extends StatelessWidget {
  const _OverviewPreview({required this.preferences, required this.snapshot});

  final CanteenWidgetPreferences preferences;
  final CanteenWidgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = _WidgetPalette.of(preferences.theme);
    final balance = preferences.hideBalance ? '••••' : '¥ ${snapshot.balance}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preferences.showStudentName && snapshot.studentName.isNotEmpty
                      ? '${snapshot.studentName}的校园卡'
                      : '一粟 · 校园卡',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                snapshot.updatedAt,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            balance,
            style: TextStyle(
              color: palette.foreground,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          if (preferences.showTodaySpend) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('今日消费', style: TextStyle(color: palette.muted)),
                const SizedBox(width: 8),
                Text(
                  '¥ ${snapshot.todaySpend}',
                  style: TextStyle(
                    color: palette.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final CanteenWidgetTheme theme;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _WidgetPalette.of(theme);
    final name = switch (theme) {
      CanteenWidgetTheme.pine => '松针',
      CanteenWidgetTheme.grain => '稻穗',
      CanteenWidgetTheme.ink => '墨色',
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetKindRow extends StatelessWidget {
  const _WidgetKindRow({
    required this.title,
    required this.description,
    required this.icon,
    required this.onAdd,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onAdd, child: const Text('添加')),
        ],
      ),
    );
  }
}

class _WidgetPalette {
  const _WidgetPalette({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color border;

  static _WidgetPalette of(CanteenWidgetTheme theme) {
    return switch (theme) {
      CanteenWidgetTheme.pine => const _WidgetPalette(
        background: Color(0xFFF4F8F3),
        foreground: Color(0xFF174F43),
        muted: Color(0xFF557069),
        accent: Color(0xFFC99B3C),
        border: Color(0xFFD7E5DC),
      ),
      CanteenWidgetTheme.grain => const _WidgetPalette(
        background: Color(0xFFFBF3DF),
        foreground: Color(0xFF6B4D16),
        muted: Color(0xFF806F4E),
        accent: Color(0xFF2D735D),
        border: Color(0xFFEAD9AE),
      ),
      CanteenWidgetTheme.ink => const _WidgetPalette(
        background: Color(0xFF252A28),
        foreground: Color(0xFFF4EEDC),
        muted: Color(0xFFB8C0BA),
        accent: Color(0xFFD7AD54),
        border: Color(0xFF46504B),
      ),
    };
  }
}
