/// Local SQLite persistence. Everything lives in a single file on the device;
/// there is no network code anywhere in the app.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'splitwise_offline.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            currency TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            name TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            description TEXT NOT NULL,
            amount_cents INTEGER NOT NULL,
            paid_by INTEGER NOT NULL REFERENCES members(id),
            split_type TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE expense_shares (
            expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
            member_id INTEGER NOT NULL REFERENCES members(id),
            share_cents INTEGER NOT NULL,
            PRIMARY KEY (expense_id, member_id)
          )''');
        await db.execute('''
          CREATE TABLE settlements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            from_id INTEGER NOT NULL REFERENCES members(id),
            to_id INTEGER NOT NULL REFERENCES members(id),
            amount_cents INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_members_group ON members(group_id)');
        await db.execute(
          'CREATE INDEX idx_expenses_group ON expenses(group_id)',
        );
        await db.execute(
          'CREATE INDEX idx_settlements_group ON settlements(group_id)',
        );
      },
    );
  }

  // ---------------------------------------------------------------- groups

  Future<int> createGroup(Group group, List<String> memberNames) async {
    final db = await database;
    return db.transaction((txn) async {
      final groupId = await txn.insert('groups', group.toMap()..remove('id'));
      for (final name in memberNames) {
        await txn.insert('members', {'group_id': groupId, 'name': name});
      }
      return groupId;
    });
  }

  Future<void> renameGroup(int id, String name, String currency) async {
    final db = await database;
    await db.update(
      'groups',
      {'name': name, 'currency': currency},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteGroup(int id) async {
    final db = await database;
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<Group?> getGroup(int id) async {
    final db = await database;
    final rows = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Group.fromMap(rows.first);
  }

  Future<List<Group>> getGroups() async {
    final db = await database;
    final rows = await db.query('groups', orderBy: 'created_at DESC');
    return rows.map(Group.fromMap).toList();
  }

  // --------------------------------------------------------------- members

  Future<List<Member>> getMembers(int groupId) async {
    final db = await database;
    final rows = await db.query(
      'members',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'id',
    );
    return rows.map(Member.fromMap).toList();
  }

  Future<int> addMember(int groupId, String name) async {
    final db = await database;
    return db.insert('members', {'group_id': groupId, 'name': name});
  }

  Future<void> renameMember(int id, String name) async {
    final db = await database;
    await db.update(
      'members',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// True if the member appears in any expense or settlement.
  Future<bool> memberHasActivity(int memberId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
      SELECT (SELECT COUNT(*) FROM expenses WHERE paid_by = ?1)
           + (SELECT COUNT(*) FROM expense_shares WHERE member_id = ?1)
           + (SELECT COUNT(*) FROM settlements WHERE from_id = ?1 OR to_id = ?1)
    ''',
        [memberId],
      ),
    );
    return (count ?? 0) > 0;
  }

  Future<void> deleteMember(int id) async {
    final db = await database;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------- expenses

  Future<List<Expense>> getExpenses(int groupId) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
    final shareRows = await db.rawQuery(
      '''
      SELECT s.expense_id, s.member_id, s.share_cents
      FROM expense_shares s JOIN expenses e ON e.id = s.expense_id
      WHERE e.group_id = ?''',
      [groupId],
    );

    final sharesByExpense = <int, Map<int, int>>{};
    for (final r in shareRows) {
      sharesByExpense.putIfAbsent(
        r['expense_id'] as int,
        () => {},
      )[r['member_id'] as int] = r['share_cents'] as int;
    }
    return rows
        .map((r) => Expense.fromMap(r, sharesByExpense[r['id'] as int] ?? {}))
        .toList();
  }

  /// Inserts a new expense, or replaces an existing one when [Expense.id] is set.
  Future<void> saveExpense(Expense expense) async {
    final db = await database;
    await db.transaction((txn) async {
      int id;
      if (expense.id == null) {
        id = await txn.insert('expenses', expense.toMap()..remove('id'));
      } else {
        id = expense.id!;
        await txn.update(
          'expenses',
          expense.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'expense_shares',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
      }
      for (final entry in expense.shares.entries) {
        if (entry.value == 0) continue;
        await txn.insert('expense_shares', {
          'expense_id': id,
          'member_id': entry.key,
          'share_cents': entry.value,
        });
      }
    });
  }

  Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // ----------------------------------------------------------- settlements

  Future<List<Settlement>> getSettlements(int groupId) async {
    final db = await database;
    final rows = await db.query(
      'settlements',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Settlement.fromMap).toList();
  }

  Future<void> addSettlement(Settlement s) async {
    final db = await database;
    await db.insert('settlements', s.toMap()..remove('id'));
  }

  Future<void> deleteSettlement(int id) async {
    final db = await database;
    await db.delete('settlements', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------------- summary

  Future<List<GroupSummary>> getGroupSummaries() async {
    final db = await database;
    final groups = await getGroups();
    final result = <GroupSummary>[];
    for (final g in groups) {
      final memberCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM members WHERE group_id = ?',
              [g.id],
            ),
          ) ??
          0;
      final total =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COALESCE(SUM(amount_cents), 0) FROM expenses WHERE group_id = ?',
              [g.id],
            ),
          ) ??
          0;
      // A group is settled when every member's net balance is zero.
      final nonZero =
          Sqflite.firstIntValue(
            await db.rawQuery(
              '''
        SELECT COUNT(*) FROM (
          SELECT m.id,
            COALESCE((SELECT SUM(amount_cents) FROM expenses WHERE paid_by = m.id), 0)
          - COALESCE((SELECT SUM(share_cents) FROM expense_shares WHERE member_id = m.id), 0)
          + COALESCE((SELECT SUM(amount_cents) FROM settlements WHERE from_id = m.id), 0)
          - COALESCE((SELECT SUM(amount_cents) FROM settlements WHERE to_id = m.id), 0) AS net
          FROM members m WHERE m.group_id = ?
        ) WHERE net != 0''',
              [g.id],
            ),
          ) ??
          0;
      result.add(GroupSummary(g, memberCount, total, nonZero == 0));
    }
    return result;
  }
}
