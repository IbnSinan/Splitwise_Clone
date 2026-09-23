import 'package:flutter/material.dart';

import '../database_helper.dart';
import '../debt_simplifier.dart';
import '../format.dart';
import '../main.dart';
import '../models.dart';
import '../widgets.dart';

/// Add a new expense or edit an existing one.
/// Pops with `true` when something was saved or deleted.
class AddExpenseScreen extends StatefulWidget {
  final Group group;
  final List<Member> members;
  final Expense? existing;

  const AddExpenseScreen({
    super.key,
    required this.group,
    required this.members,
    this.existing,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late int _paidBy;
  SplitType _splitType = SplitType.equal;
  late DateTime _date;

  /// Members included in an equal split.
  late Set<int> _included;

  /// Per-member text fields for an exact split.
  late Map<int, TextEditingController> _exact;

  bool get _editing => widget.existing != null;
  String get _cur => widget.group.currency;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _paidBy = e?.paidBy ?? widget.members.first.id!;
    _date = e?.createdAt ?? DateTime.now();
    _included = {for (final m in widget.members) m.id!};
    _exact = {for (final m in widget.members) m.id!: TextEditingController()};
    if (e != null) {
      _description.text = e.description;
      _amount.text = centsToInput(e.amountCents);
      _splitType = e.splitType;
      if (e.splitType == SplitType.equal) {
        _included = e.shares.keys.toSet();
      }
      e.shares.forEach((id, cents) => _exact[id]?.text = centsToInput(cents));
    }
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in _exact.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalCents => parseMoney(_amount.text) ?? 0;

  int get _exactSum =>
      _exact.values.fold<int>(0, (sum, c) => sum + (parseMoney(c.text) ?? 0));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
          _date.second,
        ),
      );
    }
  }

  Future<void> _save() async {
    final description = _description.text.trim();
    final total = parseMoney(_amount.text);
    if (description.isEmpty) {
      showSnack(context, 'Enter a description');
      return;
    }
    if (total == null || total <= 0) {
      showSnack(context, 'Enter a valid amount');
      return;
    }

    Map<int, int> shares;
    if (_splitType == SplitType.equal) {
      final ids = widget.members
          .map((m) => m.id!)
          .where(_included.contains)
          .toList();
      if (ids.isEmpty) {
        showSnack(context, 'Select at least one person to split with');
        return;
      }
      shares = splitEqually(total, ids);
    } else {
      shares = {};
      for (final entry in _exact.entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) continue;
        final cents = parseMoney(text);
        if (cents == null) {
          showSnack(context, 'One of the amounts is not a valid number');
          return;
        }
        if (cents > 0) shares[entry.key] = cents;
      }
      final sum = shares.values.fold<int>(0, (a, b) => a + b);
      if (sum != total) {
        final diff = total - sum;
        showSnack(
          context,
          diff > 0
              ? '${formatMoney(diff, _cur)} still left to assign'
              : 'Amounts are ${formatMoney(-diff, _cur)} over the total',
        );
        return;
      }
    }

    await DatabaseHelper.instance.saveExpense(
      Expense(
        id: widget.existing?.id,
        groupId: widget.group.id!,
        description: description,
        amountCents: total,
        paidBy: _paidBy,
        splitType: _splitType,
        shares: shares,
        createdAt: _date,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      'Delete expense?',
      '"${widget.existing!.description}" will be removed permanently.',
    );
    if (!ok) return;
    await DatabaseHelper.instance.deleteExpense(widget.existing!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit expense' : 'Add expense'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: brandGreen,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _description,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'e.g. Dinner, Taxi, Groceries',
              prefixIcon: Icon(Icons.edit_note),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '$_cur ',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _paidBy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid by'),
            items: [
              for (final m in widget.members)
                DropdownMenuItem(
                  value: m.id,
                  child: Row(
                    children: [
                      MemberAvatar(m.name, radius: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(m.name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _paidBy = v!),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(formatDate(_date)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Split', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<SplitType>(
            segments: const [
              ButtonSegment(
                value: SplitType.equal,
                icon: Icon(Icons.drag_handle),
                label: Text('Equally'),
              ),
              ButtonSegment(
                value: SplitType.exact,
                icon: Icon(Icons.pin_outlined),
                label: Text('Exact amounts'),
              ),
            ],
            selected: {_splitType},
            onSelectionChanged: (s) => setState(() => _splitType = s.first),
          ),
          const SizedBox(height: 8),
          if (_splitType == SplitType.equal)
            ..._equalSection()
          else
            ..._exactSection(),
        ],
      ),
    );
  }

  List<Widget> _equalSection() {
    final ids = widget.members
        .map((m) => m.id!)
        .where(_included.contains)
        .toList();
    final shares = splitEqually(_totalCents, ids);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              ids.isEmpty
                  ? 'Select who shares this expense'
                  : '${formatMoney(_totalCents ~/ ids.length, _cur)}/person '
                        '(${ids.length} people)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              if (_included.length == widget.members.length) {
                _included.clear();
              } else {
                _included = {for (final m in widget.members) m.id!};
              }
            }),
            child: Text(
              _included.length == widget.members.length
                  ? 'Select none'
                  : 'Select all',
            ),
          ),
        ],
      ),
      for (final m in widget.members)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _included.contains(m.id),
          onChanged: (v) => setState(
            () => v! ? _included.add(m.id!) : _included.remove(m.id),
          ),
          secondary: MemberAvatar(m.name),
          title: Text(m.name),
          subtitle: _included.contains(m.id)
              ? Text(formatMoney(shares[m.id] ?? 0, _cur))
              : null,
        ),
    ];
  }

  List<Widget> _exactSection() {
    final remaining = _totalCents - _exactSum;
    final ok = remaining == 0;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          ok
              ? 'All ${formatMoney(_totalCents, _cur)} assigned'
              : remaining > 0
              ? '${formatMoney(remaining, _cur)} left of ${formatMoney(_totalCents, _cur)}'
              : '${formatMoney(-remaining, _cur)} over the total',
          style: TextStyle(
            color: ok ? getGreen : oweOrange,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      for (final m in widget.members)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              MemberAvatar(m.name),
              const SizedBox(width: 12),
              Expanded(child: Text(m.name)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _exact[m.id],
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '$_cur ',
                    hintText: '0.00',
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
