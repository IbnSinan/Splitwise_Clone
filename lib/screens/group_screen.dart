import 'package:flutter/material.dart';

import '../database_helper.dart';
import '../debt_simplifier.dart';
import '../format.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';
import 'add_expense_screen.dart';

class GroupScreen extends StatefulWidget {
  final int groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _db = DatabaseHelper.instance;

  Group? _group;
  List<Member> _members = [];
  List<Expense> _expenses = [];
  List<Settlement> _settlements = [];
  Map<int, int> _net = {};
  List<Transfer> _transfers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final group = await _db.getGroup(widget.groupId);
    if (group == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final members = await _db.getMembers(widget.groupId);
    final expenses = await _db.getExpenses(widget.groupId);
    final settlements = await _db.getSettlements(widget.groupId);
    final net = computeNetBalances(
      members.map((m) => m.id!),
      expenses,
      settlements,
    );
    if (!mounted) return;
    setState(() {
      _group = group;
      _members = members;
      _expenses = expenses;
      _settlements = settlements;
      _net = net;
      _transfers = simplifyDebts(net);
    });
  }

  String _name(int id) => _members
      .firstWhere(
        (m) => m.id == id,
        orElse: () => Member(groupId: 0, name: '?'),
      )
      .name;

  String _money(int cents) => formatMoney(cents, _group!.currency);

  // ---------------------------------------------------------------- actions

  Future<void> _openExpense([Expense? existing]) async {
    if (_members.length < 2) {
      showSnack(context, 'Add at least two members first');
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddExpenseScreen(
          group: _group!,
          members: _members,
          existing: existing,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _recordPayment({Transfer? suggestion}) async {
    final result = await showDialog<Settlement>(
      context: context,
      builder: (_) => _SettleDialog(
        group: _group!,
        members: _members,
        suggestion: suggestion,
      ),
    );
    if (result == null) return;
    await _db.addSettlement(result);
    await _load();
    if (mounted) showSnack(context, 'Payment recorded');
  }

  Future<void> _addMember() async {
    final name = await promptText(
      context,
      title: 'Add member',
      hint: 'Name',
      action: 'Add',
    );
    if (name == null || name.isEmpty) return;
    if (_members.any((m) => m.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) showSnack(context, '$name is already in the group');
      return;
    }
    await _db.addMember(widget.groupId, name);
    _load();
  }

  Future<void> _memberMenu(Member m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text('Remove from group'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await promptText(
        context,
        title: 'Rename member',
        initial: m.name,
      );
      if (name == null || name.isEmpty) return;
      await _db.renameMember(m.id!, name);
      _load();
    } else if (action == 'remove') {
      if (await _db.memberHasActivity(m.id!)) {
        if (mounted) {
          showSnack(
            context,
            '${m.name} is part of expenses or payments and can\'t be removed',
          );
        }
        return;
      }
      await _db.deleteMember(m.id!);
      _load();
    }
  }

  Future<void> _groupMenu(String action) async {
    if (action == 'edit') {
      final result = await showDialog<(String, String)>(
        context: context,
        builder: (_) => _EditGroupDialog(group: _group!),
      );
      if (result == null) return;
      await _db.renameGroup(widget.groupId, result.$1, result.$2);
      _load();
    } else if (action == 'delete') {
      final ok = await confirm(
        context,
        'Delete group?',
        'This permanently deletes "${_group!.name}" and all its expenses.',
      );
      if (!ok) return;
      await _db.deleteGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    }
  }

  // --------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (_group == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _group!.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: _groupMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit group')),
                PopupMenuItem(value: 'delete', child: Text('Delete group')),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Balances'),
              Tab(text: 'Expenses'),
              Tab(text: 'Members'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openExpense(),
          icon: const Icon(Icons.add),
          label: const Text('Add expense'),
        ),
        body: TabBarView(
          children: [_balancesTab(), _activityTab(), _membersTab()],
        ),
      ),
    );
  }

  Widget _balancesTab() {
    final theme = Theme.of(context);
    final settled = _transfers.isEmpty;
    final sortedMembers = [..._members]
      ..sort((a, b) => (_net[b.id] ?? 0).compareTo(_net[a.id] ?? 0));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            color: settled
                ? brandGreen.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        settled ? Icons.check_circle : Icons.swap_horiz,
                        color: settled ? brandGreen : oweOrange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          settled ? 'Everyone is settled up' : 'Who owes who',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!settled) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Simplified to ${_transfers.length} '
                      'payment${_transfers.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final t in _transfers) _transferTile(t),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Balances', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _members.length < 2 ? null : () => _recordPayment(),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
            ],
          ),
          for (final m in sortedMembers) _balanceTile(m),
        ],
      ),
    );
  }

  Widget _transferTile(Transfer t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          MemberAvatar(_name(t.from), radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _name(t.from),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' owes '),
                  TextSpan(
                    text: _name(t.to),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: '\n'),
                  TextSpan(
                    text: _money(t.amountCents),
                    style: const TextStyle(
                      color: oweOrange,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => _recordPayment(suggestion: t),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }

  Widget _balanceTile(Member m) {
    final net = _net[m.id] ?? 0;
    final theme = Theme.of(context);
    final String label;
    final Color color;
    if (net > 0) {
      label = 'gets back ${_money(net)}';
      color = getGreen;
    } else if (net < 0) {
      label = 'owes ${_money(-net)}';
      color = oweOrange;
    } else {
      label = 'settled up';
      color = theme.colorScheme.outline;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: MemberAvatar(m.name),
      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _activityTab() {
    final items = <Object>[..._expenses, ..._settlements]
      ..sort((a, b) {
        final da = a is Expense ? a.createdAt : (a as Settlement).createdAt;
        final db = b is Expense ? b.createdAt : (b as Settlement).createdAt;
        return db.compareTo(da);
      });
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No expenses yet.\nTap "Add expense" to record the first one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final total = _expenses.fold<int>(0, (s, e) => s + e.amountCents);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Total group spending: ${_money(total)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        final item = items[i - 1];
        return item is Expense
            ? _expenseTile(item)
            : _settlementTile(item as Settlement);
      },
    );
  }

  Widget _dateBox(DateTime d) => SizedBox(
    width: 36,
    child: Text(
      formatShortDate(d),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        height: 1.2,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _expenseTile(Expense e) {
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dateBox(e.createdAt),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long, size: 22),
          ),
        ],
      ),
      title: Text(
        e.description,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_name(e.paidBy)} paid · split ${e.splitType == SplitType.equal ? 'equally' : 'by amounts'} '
        '(${e.shares.length})',
      ),
      trailing: Text(
        _money(e.amountCents),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      onTap: () => _openExpense(e),
    );
  }

  Widget _settlementTile(Settlement s) {
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dateBox(s.createdAt),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: brandGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payments, size: 22, color: brandGreen),
          ),
        ],
      ),
      title: Text('${_name(s.fromId)} paid ${_name(s.toId)}'),
      trailing: Text(
        _money(s.amountCents),
        style: const TextStyle(
          color: brandGreen,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      onTap: () async {
        final ok = await confirm(
          context,
          'Delete payment?',
          '${_name(s.fromId)} paid ${_name(s.toId)} ${_money(s.amountCents)}',
        );
        if (!ok) return;
        await _db.deleteSettlement(s.id!);
        _load();
      },
    );
  }

  Widget _membersTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final m in _members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(m.name),
            title: Text(m.name),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _memberMenu(m),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addMember,
          icon: const Icon(Icons.person_add),
          label: const Text('Add member'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- dialogs

class _SettleDialog extends StatefulWidget {
  final Group group;
  final List<Member> members;
  final Transfer? suggestion;

  const _SettleDialog({
    required this.group,
    required this.members,
    this.suggestion,
  });

  @override
  State<_SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends State<_SettleDialog> {
  late int _from;
  late int _to;
  late final TextEditingController _amount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _from = widget.suggestion?.from ?? widget.members[0].id!;
    _to = widget.suggestion?.to ?? widget.members[1].id!;
    _amount = TextEditingController(
      text: widget.suggestion == null
          ? ''
          : centsToInput(widget.suggestion!.amountCents),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseMoney(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (_from == _to) {
      setState(() => _error = 'Choose two different people');
      return;
    }
    Navigator.pop(
      context,
      Settlement(
        groupId: widget.group.id!,
        fromId: _from,
        toId: _to,
        amountCents: cents,
      ),
    );
  }

  DropdownButtonFormField<int> _picker(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final m in widget.members)
        DropdownMenuItem(value: m.id, child: Text(m.name)),
    ],
    onChanged: (v) => setState(() => onChanged(v!)),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record a payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _picker('Who paid', _from, (v) => _from = v),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward),
            ),
            _picker('Paid to', _to, (v) => _to = v),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: widget.group.currency,
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _EditGroupDialog extends StatefulWidget {
  final Group group;
  const _EditGroupDialog({required this.group});

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final _name = TextEditingController(text: widget.group.name);
  late final _currency = TextEditingController(text: widget.group.currency);

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currency,
            maxLength: 4,
            decoration: const InputDecoration(labelText: 'Currency symbol'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final cur = _currency.text.trim();
            Navigator.pop(context, (name, cur.isEmpty ? '\$' : cur));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
