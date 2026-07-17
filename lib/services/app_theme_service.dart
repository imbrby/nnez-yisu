import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreset { pine, grain, lake, ink }

class AppThemeService extends ChangeNotifier {
  AppThemeService._();

  static final AppThemeService instance = AppThemeService._();
  static const _preferenceKey = 'app_theme_preset';

  AppThemePreset _preset = AppThemePreset.pine;
  AppThemePreset get preset => _preset;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_preferenceKey);
      _preset = AppThemePreset.values.firstWhere(
        (preset) => preset.name == saved,
        orElse: () => AppThemePreset.pine,
      );
    } catch (_) {
      _preset = AppThemePreset.pine;
    }
  }

  Future<void> setPreset(AppThemePreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, preset.name);
    } catch (_) {}
  }

  ThemeData buildTheme() {
    final config = AppThemeConfig.of(_preset);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: config.seedColor,
      brightness: config.brightness,
    );
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    const windowsFontFamily = 'Microsoft YaHei';
    const windowsFontFallback = <String>[
      'Microsoft YaHei UI',
      'Segoe UI',
      'PingFang SC',
      'Noto Sans CJK SC',
      'sans-serif',
    ];
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: config.scaffoldColor,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      fontFamily: isWindowsDesktop ? windowsFontFamily : null,
      fontFamilyFallback: isWindowsDesktop ? windowsFontFallback : null,
    );
  }
}

class AppThemeConfig {
  const AppThemeConfig({
    required this.label,
    required this.description,
    required this.seedColor,
    required this.scaffoldColor,
    required this.brightness,
  });

  final String label;
  final String description;
  final Color seedColor;
  final Color scaffoldColor;
  final Brightness brightness;

  static AppThemeConfig of(AppThemePreset preset) {
    return switch (preset) {
      AppThemePreset.pine => const AppThemeConfig(
        label: '松针',
        description: '米纸与校园绿，经典默认',
        seedColor: Color(0xFF1F6F5B),
        scaffoldColor: Color(0xFFF5F0E6),
        brightness: Brightness.light,
      ),
      AppThemePreset.grain => const AppThemeConfig(
        label: '稻穗',
        description: '暖金与麦芽色，柔和温暖',
        seedColor: Color(0xFF8A651A),
        scaffoldColor: Color(0xFFFBF3DF),
        brightness: Brightness.light,
      ),
      AppThemePreset.lake => const AppThemeConfig(
        label: '湖水',
        description: '青蓝与雾白，清爽安静',
        seedColor: Color(0xFF276477),
        scaffoldColor: Color(0xFFEEF5F4),
        brightness: Brightness.light,
      ),
      AppThemePreset.ink => const AppThemeConfig(
        label: '墨色',
        description: '深墨底色，适合夜间使用',
        seedColor: Color(0xFF79B89D),
        scaffoldColor: Color(0xFF1D2320),
        brightness: Brightness.dark,
      ),
    };
  }
}
