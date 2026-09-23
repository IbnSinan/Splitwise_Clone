import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitwise_clone/debt_simplifier.dart';
import 'package:splitwise_clone/format.dart';
import 'package:splitwise_clone/models.dart';

/// Applies transfers and asserts every balance ends at zero.
void expectSettles(Map<int, int> net, List<Transfer> transfers) {
  final after = Map<int, int>.from(net);
  for (final t in transfers) {
    expect(t.amountCents, greaterThan(0));
    expect(t.from, isNot(t.to));
    after[t.from] = after[t.from]! + t.amountCents;
    after[t.to] = after[t.to]! - t.amountCents;
  }
  expect(after.values.every((v) => v == 0), isTrue, reason: '$after');
}

/// Minimal transfer count by brute force: n - (max zero-sum partition size).
int bruteForceMin(List<int> amounts) {
  final nz = amounts.where((a) => a != 0).toList();
  int best(List<int> rest) {
    if (rest.isEmpty) return 0;
    // Try every subset containing rest[0] that sums to zero.
    var result = 0;
    final n = rest.length;
    for (var mask = 0; mask < 1 << (n - 1); mask++) {
      var sum = rest[0];
      final others = <int>[];
      for (var i = 1; i < n; i++) {
        if (mask & (1 << (i - 1)) != 0) {
          sum += rest[i];
        } else {
          others.add(rest[i]);
        }
      }
      if (sum == 0) result = max(result, 1 + best(others));
    }
    return result;
  }

  return nz.length - best(nz);
}

void main() {
  test('equal split distributes leftover cents', () {
    final s = splitEqually(1000, [1, 2, 3]);
    expect(s, {1: 334, 2: 333, 3: 333});
    expect(s.values.reduce((a, b) => a + b), 1000);
  });

  test('net balances from expenses and settlements', () {
    final expenses = [
      Expense(
        groupId: 1,
        description: 'Dinner',
        amountCents: 3000,
        paidBy: 1,
        splitType: SplitType.equal,
        shares: {1: 1000, 2: 1000, 3: 1000},
      ),
    ];
    final settlements = [
      Settlement(groupId: 1, fromId: 2, toId: 1, amountCents: 1000),
    ];
    final net = computeNetBalances([1, 2, 3], expenses, settlements);
    expect(net, {1: 1000, 2: 0, 3: -1000});
    final t = simplifyDebts(net);
    expect(t.length, 1);
    expect((t.single.from, t.single.to, t.single.amountCents), (3, 1, 1000));
  });

  test('chain of debts collapses to a single payment', () {
    // A owes B 10, B owes C 10  =>  A pays C 10.
    final net = {1: -1000, 2: 0, 3: 1000};
    final t = simplifyDebts(net);
    expect(t.length, 1);
    expectSettles(net, t);
  });

  test('finds zero-sum subgroups that plain greedy misses', () {
    final net = {1: 600, 2: 400, 3: -500, 4: -500, 5: 0};
    final t = simplifyDebts(net);
    expectSettles(net, t);
    expect(t.length, bruteForceMin(net.values.toList()));

    final net2 = {1: 500, 2: 300, 3: -300, 4: -200, 5: -300};
    final t2 = simplifyDebts(net2);
    expectSettles(net2, t2);
    expect(t2.length, 3); // {1,4,5} and {2,3}
  });

  test('random balances are settled with the minimum number of transfers', () {
    final rng = Random(42);
    for (var round = 0; round < 300; round++) {
      final n = 2 + rng.nextInt(8);
      final amounts = List.generate(n - 1, (_) => (rng.nextInt(11) - 5) * 100);
      amounts.add(-amounts.fold<int>(0, (a, b) => a + b));
      final net = {for (var i = 0; i < n; i++) i: amounts[i]};
      final t = simplifyDebts(net);
      expectSettles(net, t);
      expect(t.length, bruteForceMin(amounts), reason: '$amounts');
    }
  });

  test('large groups fall back to greedy and still settle', () {
    final rng = Random(7);
    final amounts = List.generate(29, (_) => rng.nextInt(100000) - 50000);
    amounts.add(-amounts.fold<int>(0, (a, b) => a + b));
    final net = {for (var i = 0; i < amounts.length; i++) i: amounts[i]};
    final t = simplifyDebts(net);
    expectSettles(net, t);
    expect(t.length, lessThan(amounts.length));
  });

  test('money parsing and formatting', () {
    expect(parseMoney('12'), 1200);
    expect(parseMoney('12.5'), 1250);
    expect(parseMoney('1,234.56'), 123456);
    expect(parseMoney('.75'), 75);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('1.234'), isNull);
    expect(formatMoney(123456789, '\$'), '\$1,234,567.89');
    expect(formatMoney(-5, '€'), '-€0.05');
    expect(centsToInput(1250), '12.50');
  });
}
