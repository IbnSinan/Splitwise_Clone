import 'package:flutter/material.dart';

import '../database_helper.dart';
import '../format.dart';
import '../main.dart';
import '../models.dart';
import 'create_group_screen.dart';
import 'group_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<GroupSummary>? _groups;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await DatabaseHelper.instance.getGroupSummaries();
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _createGroup() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    await _load();
    if (id != null && mounted) _openGroup(id);
  }

  Future<void> _openGroup(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupScreen(groupId: id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: brandGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.call_split,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Groups', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.group_add),
        label: const Text('New group'),
      ),
      body: _groups == null
          ? const Center(child: CircularProgressIndicator())
          : _groups!.isEmpty
          ? _EmptyState(onCreate: _createGroup)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: _groups!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = _groups![i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: brandGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.groups, color: brandGreen),
                      ),
                      title: Text(
                        s.group.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                      subtitle: Text(
                        '${s.memberCount} members · '
                        '${formatMoney(s.totalSpentCents, s.group.currency)} spent',
                      ),
                      trailing: s.settled
                          ? Text(
                              'settled up',
                              style: TextStyle(
                                color: theme.colorScheme.outline,
                              ),
                            )
                          : const Text(
                              'unsettled',
                              style: TextStyle(
                                color: oweOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                      onTap: () => _openGroup(s.group.id!),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No groups yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a group for a trip, your flat, or anything you share. '
              'Everything stays on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.group_add),
              label: const Text('Create a group'),
            ),
          ],
        ),
      ),
    );
  }
}
