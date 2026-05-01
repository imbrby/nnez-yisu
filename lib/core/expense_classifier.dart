enum ExpenseCategory { meal, drink, snack, unknown }

class ExpenseClassification {
  const ExpenseClassification({
    required this.category,
    required this.locationName,
    required this.machineNumber,
  });

  final ExpenseCategory category;
  final String? locationName;
  final String? machineNumber;
}

class ExpenseClassifier {
  static const Map<String, ExpenseCategory> _knownLocations =
      <String, ExpenseCategory>{
        '学生食堂': ExpenseCategory.meal,
        '凉茶店': ExpenseCategory.drink,
        '凤岭小卖部': ExpenseCategory.snack,
        '凤岭小卖铺': ExpenseCategory.snack,
      };

  static ExpenseClassification classify(String itemName) {
    final normalized = itemName.replaceAll(RegExp(r'\s+'), '');

    String? matchedLocation;
    ExpenseCategory category = ExpenseCategory.unknown;

    for (final entry in _knownLocations.entries) {
      if (normalized.contains(entry.key)) {
        matchedLocation = entry.key;
        category = entry.value;
        break;
      }
    }

    String? machineNumber;
    if (matchedLocation != null) {
      final locationIndex = normalized.indexOf(matchedLocation);
      final suffix = normalized.substring(
        locationIndex + matchedLocation.length,
      );
      final afterLocationDigits = RegExp(r'(\d{1,4})').firstMatch(suffix);
      machineNumber = afterLocationDigits?.group(1);
    }
    machineNumber ??= RegExp(
      r'(\d{1,4})(?=号机|机)',
    ).firstMatch(normalized)?.group(1);

    return ExpenseClassification(
      category: category,
      locationName: matchedLocation,
      machineNumber: machineNumber,
    );
  }
}
