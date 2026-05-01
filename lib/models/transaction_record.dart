class TransactionRecord {
  const TransactionRecord({
    required this.sid,
    required this.txnId,
    required this.amount,
    required this.balance,
    required this.occurredAt,
    required this.occurredDay,
    required this.itemName,
    required this.rawPayload,
  });

  final String sid;
  final String txnId;
  final double amount;
  final double? balance;
  final String occurredAt;
  final String occurredDay;
  final String itemName;
  final String rawPayload;

  TransactionRecord withSid(String newSid) {
    return TransactionRecord(
      sid: newSid,
      txnId: txnId,
      amount: amount,
      balance: balance,
      occurredAt: occurredAt,
      occurredDay: occurredDay,
      itemName: itemName,
      rawPayload: rawPayload,
    );
  }

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'sid': sid,
      'txn_id': txnId,
      'amount': amount,
      'balance': balance,
      'occurred_at': occurredAt,
      'occurred_day': occurredDay,
      'item_name': itemName,
      'raw_payload': rawPayload,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory TransactionRecord.fromDbMap(Map<String, Object?> map) {
    return TransactionRecord(
      sid: (map['sid'] ?? '').toString(),
      txnId: (map['txn_id'] ?? '').toString(),
      amount: ((map['amount'] ?? 0) as num).toDouble(),
      balance: map['balance'] == null
          ? null
          : ((map['balance'] ?? 0) as num).toDouble(),
      occurredAt: (map['occurred_at'] ?? '').toString(),
      occurredDay: (map['occurred_day'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      rawPayload: (map['raw_payload'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sid': sid,
      'txnId': txnId,
      'amount': amount,
      'balance': balance,
      'occurredAt': occurredAt,
      'occurredDay': occurredDay,
      'itemName': itemName,
      'rawPayload': rawPayload,
    };
  }

  factory TransactionRecord.fromJsonMap(Map<String, dynamic> map) {
    final amountRaw = map['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    final balanceRaw = map['balance'];
    final parsedBalance = balanceRaw == null
        ? null
        : (balanceRaw is num
              ? balanceRaw.toDouble()
              : double.tryParse(balanceRaw.toString()));
    return TransactionRecord(
      sid: (map['sid'] ?? '').toString(),
      txnId: (map['txnId'] ?? '').toString(),
      amount: amount,
      balance: parsedBalance,
      occurredAt: (map['occurredAt'] ?? '').toString(),
      occurredDay: (map['occurredDay'] ?? '').toString(),
      itemName: (map['itemName'] ?? '').toString(),
      rawPayload: (map['rawPayload'] ?? '').toString(),
    );
  }

  factory TransactionRecord.fromRemote(Map<String, dynamic> remote) {
    // Parse amount (消费金额)
    final amountStr = (remote['Money'] ?? '0').toString();
    final amount = (double.tryParse(amountStr) ?? 0.0).abs();

    // Parse balance (余额)
    final balanceStr = (remote['Balance'] ?? '').toString();
    final balance = balanceStr.isEmpty || balanceStr == '-1'
        ? null
        : double.tryParse(balanceStr);

    // Parse datetime (交易时间格式: "2026/2/2 17:17:32")
    final timeStr = (remote['Time'] ?? '').toString();
    String occurredAt = '';
    String occurredDay = '';
    final match = RegExp(
      r'^(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})$',
    ).firstMatch(timeStr);
    if (match != null) {
      String pad(String v) => v.padLeft(2, '0');
      occurredDay =
          '${match.group(1)!}-${pad(match.group(2)!)}-${pad(match.group(3)!)}';
      occurredAt =
          '$occurredDay ${pad(match.group(4)!)}:${pad(match.group(5)!)}:${pad(match.group(6)!)}';
    }

    return TransactionRecord(
      sid: '',
      txnId: (remote['Id'] ?? '').toString(),
      amount: amount,
      balance: balance,
      occurredAt: occurredAt,
      occurredDay: occurredDay,
      itemName: (remote['ItemName'] ?? '未知消费点').toString().trim().isEmpty
          ? '未知消费点'
          : (remote['ItemName'] ?? '').toString().trim(),
      rawPayload: remote.toString(),
    );
  }
}
