/// Plain data classes. All money is stored as integer cents to avoid
/// floating-point rounding errors.
library;

class Group {
  final int? id;
  final String name;
  final String currency;
  final DateTime createdAt;

  Group({
    this.id,
    required this.name,
    this.currency = '\$',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'currency': currency,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Group.fromMap(Map<String, Object?> m) => Group(
    id: m['id'] as int,
    name: m['name'] as String,
    currency: m['currency'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

class Member {
  final int? id;
  final int groupId;
  final String name;

  Member({this.id, required this.groupId, required this.name});

  Map<String, Object?> toMap() => {'id': id, 'group_id': groupId, 'name': name};

  factory Member.fromMap(Map<String, Object?> m) => Member(
    id: m['id'] as int,
    groupId: m['group_id'] as int,
    name: m['name'] as String,
  );
}

enum SplitType { equal, exact }

class Expense {
  final int? id;
  final int groupId;
  final String description;
  final int amountCents;
  final int paidBy;
  final SplitType splitType;
  final DateTime createdAt;

  /// memberId -> share in cents. Always sums to [amountCents].
  final Map<int, int> shares;

  Expense({
    this.id,
    required this.groupId,
    required this.description,
    required this.amountCents,
    required this.paidBy,
    required this.splitType,
    required this.shares,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
    'id': id,
    'group_id': groupId,
    'description': description,
    'amount_cents': amountCents,
    'paid_by': paidBy,
    'split_type': splitType.name,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Expense.fromMap(Map<String, Object?> m, Map<int, int> shares) =>
      Expense(
        id: m['id'] as int,
        groupId: m['group_id'] as int,
        description: m['description'] as String,
        amountCents: m['amount_cents'] as int,
        paidBy: m['paid_by'] as int,
        splitType: SplitType.values.byName(m['split_type'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        shares: shares,
      );
}

/// A recorded repayment: [fromId] paid [toId] back.
class Settlement {
  final int? id;
  final int groupId;
  final int fromId;
  final int toId;
  final int amountCents;
  final DateTime createdAt;

  Settlement({
    this.id,
    required this.groupId,
    required this.fromId,
    required this.toId,
    required this.amountCents,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
    'id': id,
    'group_id': groupId,
    'from_id': fromId,
    'to_id': toId,
    'amount_cents': amountCents,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Settlement.fromMap(Map<String, Object?> m) => Settlement(
    id: m['id'] as int,
    groupId: m['group_id'] as int,
    fromId: m['from_id'] as int,
    toId: m['to_id'] as int,
    amountCents: m['amount_cents'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );
}

/// Summary row for the home screen.
class GroupSummary {
  final Group group;
  final int memberCount;
  final int totalSpentCents;
  final bool settled;

  GroupSummary(
    this.group,
    this.memberCount,
    this.totalSpentCents,
    this.settled,
  );
}
