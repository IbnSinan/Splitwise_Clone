/// Balance computation and the debt-simplification algorithm.
///
/// Pure Dart with no Flutter or database imports so it can be unit-tested.
library;

import 'models.dart';

/// A single suggested payment: [from] pays [to] [amountCents].
class Transfer {
  final int from;
  final int to;
  final int amountCents;

  const Transfer(this.from, this.to, this.amountCents);

  @override
  String toString() => 'Transfer($from -> $to: $amountCents)';
}

/// Net balance per member in cents.
/// Positive = the group owes them money, negative = they owe the group.
Map<int, int> computeNetBalances(
  Iterable<int> memberIds,
  Iterable<Expense> expenses,
  Iterable<Settlement> settlements,
) {
  final net = {for (final id in memberIds) id: 0};
  for (final e in expenses) {
    net[e.paidBy] = (net[e.paidBy] ?? 0) + e.amountCents;
    e.shares.forEach((memberId, share) {
      net[memberId] = (net[memberId] ?? 0) - share;
    });
  }
  for (final s in settlements) {
    // The payer reduced their debt; the receiver is owed less.
    net[s.fromId] = (net[s.fromId] ?? 0) + s.amountCents;
    net[s.toId] = (net[s.toId] ?? 0) - s.amountCents;
  }
  return net;
}

/// Minimises the number of transfers needed to settle [netBalances].
///
/// Strategy:
///  1. Drop everyone already at zero.
///  2. For up to [exactLimit] people, find the partition of people into the
///     largest number of groups whose balances each sum to zero (bitmask DP).
///     Each zero-sum group of size k settles in k-1 transfers, so maximising
///     the number of groups gives the provably minimal total (n - groups).
///  3. Inside each group (or for everyone, if there are too many people for
///     the exact search) use the classic greedy: the biggest debtor pays the
///     biggest creditor as much as possible, repeat.
List<Transfer> simplifyDebts(Map<int, int> netBalances, {int exactLimit = 16}) {
  final ids = <int>[];
  final amounts = <int>[];
  netBalances.forEach((id, amount) {
    if (amount != 0) {
      ids.add(id);
      amounts.add(amount);
    }
  });
  if (ids.isEmpty) return const [];

  if (ids.length > exactLimit) {
    return _greedy({for (var i = 0; i < ids.length; i++) ids[i]: amounts[i]});
  }

  final n = ids.length;
  final full = (1 << n) - 1;
  final sum = List<int>.filled(1 << n, 0);
  for (var mask = 1; mask <= full; mask++) {
    final low = mask & -mask;
    sum[mask] = sum[mask ^ low] + amounts[low.bitLength - 1];
  }

  // dp[mask] = max number of zero-sum groups the members of [mask] can be
  // split into, following a "remove one member at a time" ordering.
  final dp = List<int>.filled(1 << n, 0);
  for (var mask = 1; mask <= full; mask++) {
    var best = 0;
    for (var i = 0; i < n; i++) {
      if (mask & (1 << i) != 0) {
        final v = dp[mask ^ (1 << i)];
        if (v > best) best = v;
      }
    }
    dp[mask] = best + (sum[mask] == 0 ? 1 : 0);
  }

  // Walk an optimal path back down; every zero-sum mask on the path marks a
  // group boundary.
  final groups = <int>[];
  var mask = full;
  var groupStart = full;
  while (mask != 0) {
    if (sum[mask] == 0 && mask != groupStart) {
      groups.add(groupStart ^ mask);
      groupStart = mask;
    }
    final target = dp[mask] - (sum[mask] == 0 ? 1 : 0);
    for (var i = 0; i < n; i++) {
      if (mask & (1 << i) != 0 && dp[mask ^ (1 << i)] == target) {
        mask ^= 1 << i;
        break;
      }
    }
  }
  groups.add(groupStart);

  final result = <Transfer>[];
  for (final g in groups) {
    final part = <int, int>{};
    for (var i = 0; i < n; i++) {
      if (g & (1 << i) != 0) part[ids[i]] = amounts[i];
    }
    result.addAll(_greedy(part));
  }
  result.sort((a, b) => b.amountCents.compareTo(a.amountCents));
  return result;
}

/// Greedy settlement: largest debtor pays largest creditor.
/// Produces at most (people - 1) transfers.
List<Transfer> _greedy(Map<int, int> balances) {
  final creditors = <MapEntry<int, int>>[];
  final debtors = <MapEntry<int, int>>[];
  balances.forEach((id, amount) {
    if (amount > 0) creditors.add(MapEntry(id, amount));
    if (amount < 0) debtors.add(MapEntry(id, -amount));
  });

  final result = <Transfer>[];
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));
    final c = creditors.first;
    final d = debtors.first;
    final pay = c.value < d.value ? c.value : d.value;
    result.add(Transfer(d.key, c.key, pay));

    creditors.removeAt(0);
    debtors.removeAt(0);
    if (c.value > pay) creditors.add(MapEntry(c.key, c.value - pay));
    if (d.value > pay) debtors.add(MapEntry(d.key, d.value - pay));
  }
  return result;
}

/// Splits [totalCents] equally among [memberIds]; leftover cents go to the
/// first members so the shares always add up exactly.
Map<int, int> splitEqually(int totalCents, List<int> memberIds) {
  if (memberIds.isEmpty) return {};
  final base = totalCents ~/ memberIds.length;
  final remainder = totalCents % memberIds.length;
  return {
    for (var i = 0; i < memberIds.length; i++)
      memberIds[i]: base + (i < remainder ? 1 : 0),
  };
}
