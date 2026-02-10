import 'package:nnez_yisu/models/campus_profile.dart';
import 'package:nnez_yisu/models/recharge_record.dart';
import 'package:nnez_yisu/models/transaction_record.dart';

class CampusSyncPayload {
  const CampusSyncPayload({
    required this.profile,
    required this.transactions,
    required this.recharges,
    required this.balance,
    required this.balanceUpdatedAt,
  });

  final CampusProfile profile;
  final List<TransactionRecord> transactions;
  final List<RechargeRecord> recharges;
  final double balance;
  final DateTime balanceUpdatedAt;
}
