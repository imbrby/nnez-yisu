import 'package:flutter/material.dart';
import 'package:nnez_yisu/core/expense_classifier.dart';

class ExpenseVisualStyle {
  const ExpenseVisualStyle({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
}

class ExpenseVisualStyles {
  static ExpenseVisualStyle resolve({
    required ColorScheme colorScheme,
    ExpenseCategory? category,
    bool isRecharge = false,
  }) {
    if (isRecharge) {
      return ExpenseVisualStyle(
        icon: Icons.add_circle_outline,
        backgroundColor: colorScheme.tertiaryContainer,
        iconColor: colorScheme.onTertiaryContainer,
      );
    }
    return switch (category) {
      ExpenseCategory.meal => ExpenseVisualStyle(
        icon: Icons.restaurant_menu_outlined,
        backgroundColor: colorScheme.primaryContainer,
        iconColor: colorScheme.onPrimaryContainer,
      ),
      ExpenseCategory.drink => ExpenseVisualStyle(
        icon: Icons.local_cafe_outlined,
        backgroundColor: colorScheme.tertiaryContainer,
        iconColor: colorScheme.onTertiaryContainer,
      ),
      ExpenseCategory.snack => ExpenseVisualStyle(
        icon: Icons.icecream_outlined,
        backgroundColor: colorScheme.secondaryContainer,
        iconColor: colorScheme.onSecondaryContainer,
      ),
      ExpenseCategory.unknown || null => ExpenseVisualStyle(
        icon: Icons.receipt_long_outlined,
        backgroundColor: colorScheme.surfaceContainerHighest,
        iconColor: colorScheme.onSurfaceVariant,
      ),
    };
  }
}
