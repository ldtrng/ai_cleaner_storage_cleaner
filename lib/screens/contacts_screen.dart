import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/contacts_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'success_screen.dart';

enum _Tab { duplicate, incomplete, all, backups }

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final repo = ContactsRepository.instance;
  _Tab tab = _Tab.duplicate;

  final _dupSel = <int>{}; // group indices
  final _incSel = <String>{};
  final _allSel = <String>{};
  bool _seeded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    repo.checkAccess().then((ok) {
      if (ok) repo.load();
    });
    repo.addListener(_seed);
  }

  @override
  void dispose() {
    repo.removeListener(_seed);
    super.dispose();
  }

  void _seed() {
    if (!repo.loaded || repo.loading) return;
    _dupSel
      ..clear()
      ..addAll(List.generate(repo.duplicates.length, (i) => i));
    final valid = repo.all.map((c) => c.id).toSet();
    _incSel.retainWhere(valid.contains);
    _allSel.retainWhere(valid.contains);
    if (!_seeded) {
      _incSel.addAll(repo.incomplete.map((c) => c.id!));
      _seeded = true;
    }
  }

  Future<void> _mergeSelected() async {
    final groups = [for (final i in _dupSel) repo.duplicates[i]];
    final n = groups.fold(0, (a, g) => a + g.contacts.length);
    final ok = await showConfirm(
      context,
      title: 'Allow merging $n contacts?',
      message:
          'A backup of your contacts is created first. You can restore it from the Backups tab.',
      confirm: 'Merge',
    );
    if (!ok || !mounted) return;
    final removed = await runWithProgress(
      context,
      (_) => repo.mergeGroups(groups),
    );
    if (!mounted) return;
    _done(
      '${plural(groups.length, 'contact')} merged',
      plural(removed, 'duplicate'),
    );
  }

  Future<void> _deleteSelected(Set<String> ids) async {
    final list = repo.all.where((c) => ids.contains(c.id)).toList();
    final ok = await showConfirm(
      context,
      title: 'Allow deleting ${plural(list.length, 'contact')}?',
      message:
          'A backup of your contacts is created first. You can restore it from the Backups tab.',
    );
    if (!ok || !mounted) return;
    await runWithProgress(context, (_) => repo.deleteContacts(list));
    ids.clear();
    if (!mounted) return;
    _done("You've cleaned your contacts", plural(list.length, 'contact'));
  }

  void _done(String title, String deleted) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: title,
          deleted: deleted,
          note: 'To recover contacts, open the Backups tab in Contacts.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (repo.hasAccess == false) {
          return GradientScaffold(
            title: 'Contacts',
            body: NoAccessView(
              icon: Icons.contacts_rounded,
              title: 'No access to Contacts',
              message:
                  'To get rid of duplicate and incomplete contacts, allow access.',
              onAllow: () async {
                if (!await repo.requestAccess()) repo.openSettings();
              },
            ),
          );
        }
        return GradientScaffold(
          title: 'Contacts',
          body: Column(
            children: [
              CategoryChips<_Tab>(
                items: _Tab.values,
                selected: tab,
                label: (t) => switch (t) {
                  _Tab.duplicate => 'Duplicate  ${repo.duplicates.length}',
                  _Tab.incomplete => 'Incomplete  ${repo.incomplete.length}',
                  _Tab.all => 'All  ${repo.all.length}',
                  _Tab.backups => 'Backups',
                },
                onSelected: (t) => setState(() => tab = t),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: repo.loading && !repo.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : switch (tab) {
                        _Tab.duplicate => _duplicates(),
                        _Tab.incomplete => _list(
                          repo.incomplete,
                          _incSel,
                          'Missing name, number, or email',
                        ),
                        _Tab.all => _list(
                          _filtered(),
                          _allSel,
                          null,
                          search: true,
                        ),
                        _Tab.backups => const _Backups(),
                      },
              ),
            ],
          ),
          bottom: switch (tab) {
            _Tab.duplicate when repo.duplicates.isNotEmpty => BottomAction(
              label: _dupSel.isEmpty
                  ? 'Merge'
                  : 'Merge ${_dupSel.length} groups',
              icon: Icons.merge_rounded,
              onPressed: _dupSel.isEmpty ? null : _mergeSelected,
            ),
            _Tab.incomplete when repo.incomplete.isNotEmpty => BottomAction(
              label: _incSel.isEmpty
                  ? 'Delete'
                  : 'Delete ${plural(_incSel.length, 'contact')}',
              icon: Icons.delete_outline_rounded,
              onPressed: _incSel.isEmpty
                  ? null
                  : () => _deleteSelected(_incSel),
            ),
            _Tab.all when _allSel.isNotEmpty => BottomAction(
              label: 'Delete ${plural(_allSel.length, 'contact')}',
              icon: Icons.delete_outline_rounded,
              onPressed: () => _deleteSelected(_allSel),
            ),
            _ => null,
          },
        );
      },
    );
  }

  List<Contact> _filtered() {
    if (_query.isEmpty) return repo.all;
    final q = _query.toLowerCase();
    return repo.all
        .where(
          (c) =>
              ContactsRepository.displayName(c).toLowerCase().contains(q) ||
              c.phones.any((p) => p.number.contains(q)) ||
              c.emails.any((e) => e.address.toLowerCase().contains(q)),
        )
        .toList();
  }

  Widget _duplicates() {
    if (repo.duplicates.isEmpty) {
      return const EmptyState(icon: Icons.people_alt_rounded);
    }
    final allOn = _dupSel.length == repo.duplicates.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: repo.duplicates.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'By name, number, or email',
                    style: context.text.bodySmall,
                  ),
                ),
              ),
              SelectAllButton(
                allSelected: allOn,
                onChanged: (v) => setState(() {
                  _dupSel.clear();
                  if (v) {
                    _dupSel.addAll(
                      List.generate(repo.duplicates.length, (i) => i),
                    );
                  }
                }),
              ),
            ],
          );
        }
        final gi = i - 1;
        final g = repo.duplicates[gi];
        final merged = g.merged;
        final on = _dupSel.contains(gi);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            onTap: () =>
                setState(() => on ? _dupSel.remove(gi) : _dupSel.add(gi)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Contacts to merge · same ${g.reason.toLowerCase()}',
                        style: context.text.bodySmall,
                      ),
                    ),
                    Checkbox(
                      value: on,
                      onChanged: (_) => setState(
                        () => on ? _dupSel.remove(gi) : _dupSel.add(gi),
                      ),
                    ),
                  ],
                ),
                for (final c in g.contacts) _ContactLine(contact: c, dim: true),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Icon(
                    Icons.south_rounded,
                    size: 20,
                    color: Palette.sage,
                  ),
                ),
                Text('Merged contact', style: context.text.bodySmall),
                _ContactLine(contact: merged),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(
    List<Contact> list,
    Set<String> sel,
    String? hint, {
    bool search = false,
  }) {
    final allOn = list.isNotEmpty && list.every((c) => sel.contains(c.id));
    return Column(
      children: [
        if (search)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
        if (list.isEmpty)
          const Expanded(child: EmptyState(icon: Icons.person_search_rounded))
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hint ?? plural(list.length, 'contact'),
                    style: context.text.bodySmall,
                  ),
                ),
                SelectAllButton(
                  allSelected: allOn,
                  onChanged: (v) => setState(() {
                    for (final c in list) {
                      v ? sel.add(c.id!) : sel.remove(c.id);
                    }
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                final on = sel.contains(c.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    radius: 22,
                    onTap: () =>
                        setState(() => on ? sel.remove(c.id) : sel.add(c.id!)),
                    child: Row(
                      children: [
                        Expanded(child: _ContactLine(contact: c)),
                        Checkbox(
                          value: on,
                          onChanged: (_) => setState(
                            () => on ? sel.remove(c.id) : sel.add(c.id!),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.contact, this.dim = false});
  final Contact contact;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final name = ContactsRepository.displayName(contact);
    final details = [
      ...contact.phones.map((p) => p.number),
      ...contact.emails.map((e) => e.address),
    ];
    final thumb = contact.photo?.thumbnail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: dim
                ? context.tokens.track
                : (context.isDark ? Palette.moss : Palette.mist),
            backgroundImage: thumb != null ? MemoryImage(thumb) : null,
            child: thumb == null
                ? Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: font(
                      16,
                      FontWeight.w600,
                      color: context.isDark ? Palette.cream : Palette.forest,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                Text(
                  details.isEmpty ? 'No number or email' : details.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Backups extends StatefulWidget {
  const _Backups();

  @override
  State<_Backups> createState() => _BackupsState();
}

class _BackupsState extends State<_Backups> {
  final repo = ContactsRepository.instance;
  late Future<List<ContactBackup>> _future = repo.backups();

  void _reload() => setState(() => _future = repo.backups());

  Future<void> _create() async {
    final b = await repo.createBackup();
    if (!mounted) return;
    showToast(
      context,
      b == null ? 'Sorry! Something went wrong.' : 'A new backup was created',
    );
    _reload();
  }

  Future<void> _restore(ContactBackup b) async {
    final ok = await showConfirm(
      context,
      title: 'Restore this backup?',
      message:
          'Contacts from this backup that are missing from your phonebook will be added back.',
      confirm: 'Restore',
      cancel: 'Cancel',
    );
    if (!ok || !mounted) return;
    final n = await runWithProgress(
      context,
      (_) async => repo.restore(await repo.backupContacts(b)),
      title: 'Restoring...',
      message: 'Adding contacts back to your phonebook',
    );
    if (!mounted) return;
    showToast(
      context,
      n == 0
          ? 'All contacts are already in your phonebook'
          : '${plural(n, 'contact')} restored',
    );
  }

  Future<void> _delete(ContactBackup b) async {
    final ok = await showConfirm(
      context,
      title: 'Delete this backup?',
      cancel: 'Cancel',
    );
    if (!ok) return;
    await repo.deleteBackups([b]);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        final list = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phone backups', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    list.isEmpty
                        ? 'No active backup'
                        : 'Last backup: ${formatDate(list.first.date)} · ${plural(list.first.count, 'contact')}',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _create,
                    child: const Text('Backup now'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final b in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  radius: 22,
                  child: Row(
                    children: [
                      const PillIcon(icon: Icons.backup_rounded, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatDate(b.date),
                              style: context.text.titleSmall,
                            ),
                            Text(
                              '${plural(b.count, 'contact')} · ${TimeOfDay.fromDateTime(b.date).format(context)}',
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _restore(b),
                        icon: const Icon(Icons.restore_rounded),
                        tooltip: 'Restore',
                      ),
                      IconButton(
                        onPressed: () => _delete(b),
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
