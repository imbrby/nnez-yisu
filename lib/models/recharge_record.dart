class RechargeRecord {
  const RechargeRecord({
    required this.sid,
    required this.orderId,
    required this.amount,
    required this.occurredAt,
    required this.occurredDay,
    required this.status,
    required this.channel,
    required this.rawPayload,
  });

  final String sid;
  final String orderId;
  final double amount;
  final String occurredAt;
  final String occurredDay;
  final String status;
  final String channel;
  final String rawPayload;

  RechargeRecord withSid(String newSid) {
    return RechargeRecord(
      sid: newSid,
      orderId: orderId,
      amount: amount,
      occurredAt: occurredAt,
      occurredDay: occurredDay,
      status: status,
      channel: channel,
      rawPayload: rawPayload,
    );
  }

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'sid': sid,
      'order_id': orderId,
      'amount': amount,
      'occurred_at': occurredAt,
      'occurred_day': occurredDay,
      'status': status,
      'channel': channel,
      'raw_payload': rawPayload,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  factory RechargeRecord.fromDbMap(Map<String, Object?> map) {
    return RechargeRecord(
      sid: (map['sid'] ?? '').toString(),
      orderId: (map['order_id'] ?? '').toString(),
      amount: ((map['amount'] ?? 0) as num).toDouble(),
      occurredAt: (map['occurred_at'] ?? '').toString(),
      occurredDay: (map['occurred_day'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      channel: (map['channel'] ?? '').toString(),
      rawPayload: (map['raw_payload'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sid': sid,
      'orderId': orderId,
      'amount': amount,
      'occurredAt': occurredAt,
      'occurredDay': occurredDay,
      'status': status,
      'channel': channel,
      'rawPayload': rawPayload,
    };
  }

  factory RechargeRecord.fromJsonMap(Map<String, dynamic> map) {
    final amountRaw = map['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    return RechargeRecord(
      sid: (map['sid'] ?? '').toString(),
      orderId: (map['orderId'] ?? '').toString(),
      amount: amount,
      occurredAt: (map['occurredAt'] ?? '').toString(),
      occurredDay: (map['occurredDay'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      channel: (map['channel'] ?? '').toString(),
      rawPayload: (map['rawPayload'] ?? '').toString(),
    );
  }

  factory RechargeRecord.fromRemote(Map<String, dynamic> remote) {
    final amountStr = (remote['jiner'] ?? '0').toString();
    final amount = (double.tryParse(amountStr) ?? 0.0).abs();

    final timeStr = (remote['riqi'] ?? '').toString();
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

    return RechargeRecord(
      sid: '',
      orderId: (remote['dingdanhao'] ?? '').toString(),
      amount: amount,
      occurredAt: occurredAt,
      occurredDay: occurredDay,
      status: (remote['zhuangtai'] ?? '').toString().trim(),
      channel: (remote['yinhang'] ?? '').toString().trim(),
      rawPayload: remote.toString(),
    );
  }
}
