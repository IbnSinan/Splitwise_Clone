import 'package:flutter/material.dart';

import '../database_helper.dart';
import '../models.dart';
import '../widgets.dart';

/// Create a group and type in its members' names.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _currency = TextEditingController(text: '\$');
  final _memberInput = TextEditingController();
  final _memberFocus = FocusNode();
  final List<String> _members = [];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _memberInput.dispose();
    _memberFocus.dispose();
    super.dispose();
  }

  void _addMember() {
    final name = _memberInput.text.trim();
    if (name.isEmpty) return;
    if (_members.any((m) => m.toLowerCase() == name.toLowerCase())) {
      showSnack(context, '$name is already in the group');
      return;
    }
    setState(() => _members.add(name));
    _memberInput.clear();
    _memberFocus.requestFocus();
  }

  Future<void> _save() async {
    // Include a name left in the input box without pressing "add".
    if (_memberInput.text.trim().isNotEmpty) _addMember();
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Give the group a name');
      return;
    }
    if (_members.length < 2) {
      showSnack(context, 'Add at least two members');
      return;
    }
    setState(() => _saving = true);
    final currency = _currency.text.trim().isEmpty
        ? '\$'
        : _currency.text.trim();
    final id = await DatabaseHelper.instance.createGroup(
      Group(name: name, currency: currency),
      _members,
    );
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Goa trip, Flat 4B',
                    prefixIcon: Icon(Icons.groups),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _currency,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Members', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberInput,
                  focusNode: _memberFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addMember(),
                  decoration: const InputDecoration(
                    hintText: 'Type a name',
                    prefixIcon: Icon(Icons.person_add_alt),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _addMember,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _members.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(_members[i]),
              title: Text(_members[i]),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _members.removeAt(i)),
              ),
            ),
          if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Add everyone who shares expenses, including yourself.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
