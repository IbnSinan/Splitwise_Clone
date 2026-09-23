import 'package:flutter_test/flutter_test.dart';
import 'package:splitwise_clone/database_helper.dart';
import 'package:splitwise_clone/debt_simplifier.dart';
import 'package:splitwise_clone/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  test('full group lifecycle persists and balances correctly', () async {
    final db = DatabaseHelper.instance;
    final groupId = await db.createGroup(Group(name: 'Trip', currency: '৳'), [
      'A',
      'B',
      'C',
    ]);
    final members = await db.getMembers(groupId);
    final [a, b, c] = members.map((m) => m.id!).toList();

    await db.saveExpense(
      Expense(
        groupId: groupId,
        description: 'Hotel',
        amountCents: 9000,
        paidBy: a,
        splitType: SplitType.equal,
        shares: splitEqually(9000, [a, b, c]),
      ),
    );
    await db.saveExpense(
      Expense(
        groupId: groupId,
        description: 'Taxi',
        amountCents: 1000,
        paidBy: b,
        splitType: SplitType.exact,
        shares: {b: 200, c: 800},
      ),
    );

    var expenses = await db.getExpenses(groupId);
    expect(expenses.length, 2);
    final net = computeNetBalances(
      [a, b, c],
      expenses,
      await db.getSettlements(groupId),
    );
    expect(net, {a: 6000, b: -2200, c: -3800});
    expect(simplifyDebts(net).length, 2);

    var summary = (await db.getGroupSummaries()).firstWhere(
      (s) => s.group.id == groupId,
    );
    expect(summary.totalSpentCents, 10000);
    expect(summary.settled, isFalse);

    // Edit an expense: shares are replaced, not duplicated.
    final taxi = expenses.firstWhere((e) => e.description == 'Taxi');
    await db.saveExpense(
      Expense(
        id: taxi.id,
        groupId: groupId,
        description: 'Taxi',
        amountCents: 1000,
        paidBy: b,
        splitType: SplitType.equal,
        shares: splitEqually(1000, [b, c]),
      ),
    );
    expenses = await db.getExpenses(groupId);
    expect(expenses.firstWhere((e) => e.id == taxi.id).shares, {
      b: 500,
      c: 500,
    });

    expect(await db.memberHasActivity(a), isTrue);
    final d = await db.addMember(groupId, 'D');
    expect(await db.memberHasActivity(d), isFalse);
    await db.deleteMember(d);

    // Settle everything as suggested -> group is settled.
    final netNow = computeNetBalances(
      [a, b, c],
      expenses,
      await db.getSettlements(groupId),
    );
    for (final t in simplifyDebts(netNow)) {
      await db.addSettlement(
        Settlement(
          groupId: groupId,
          fromId: t.from,
          toId: t.to,
          amountCents: t.amountCents,
        ),
      );
    }
    summary = (await db.getGroupSummaries()).firstWhere(
      (s) => s.group.id == groupId,
    );
    expect(summary.settled, isTrue);

    await db.deleteGroup(groupId);
    expect(await db.getGroup(groupId), isNull);
    expect(await db.getMembers(groupId), isEmpty);
  });
}
