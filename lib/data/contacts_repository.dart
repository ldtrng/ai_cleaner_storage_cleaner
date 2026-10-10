import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:path_provider/path_provider.dart';

import '../ads/ads_service.dart';

typedef Contact = fc.Contact;

class ContactBackup {
  ContactBackup(this.file, this.date, this.count);
  final File file;
  final DateTime date;
  final int count;
}

class DuplicateContactGroup {
  DuplicateContactGroup(this.contacts, this.reason);
  final List<Contact> contacts;
  final String reason;

  /// Preview of the merged result (first contact keeps its id).
  Contact get merged => ContactsRepository.merge(contacts);
}

class ContactsRepository extends ChangeNotifier {
  ContactsRepository._();
  static final instance = ContactsRepository._();

  static const _props = {
    fc.ContactProperty.name,
    fc.ContactProperty.phone,
    fc.ContactProperty.email,
    fc.ContactProperty.organization,
    fc.ContactProperty.address,
    fc.ContactProperty.note,
    fc.ContactProperty.photoThumbnail,
  };

  bool? hasAccess;
  bool loading = false;
  bool loaded = false;
  List<Contact> all = [];
  List<DuplicateContactGroup> duplicates = [];
  List<Contact> incomplete = [];

  int get duplicateCleanCount =>
      duplicates.fold(0, (a, g) => a + g.contacts.length - 1);

  Future<bool> checkAccess() async {
    hasAccess = await fc.FlutterContacts.permissions.has(
      fc.PermissionType.readWrite,
    );
    notifyListeners();
    return hasAccess!;
  }

  Future<bool> requestAccess() async {
    final s = await fc.FlutterContacts.permissions.request(
      fc.PermissionType.readWrite,
    );
    hasAccess =
        s == fc.PermissionStatus.granted || s == fc.PermissionStatus.limited;
    notifyListeners();
    if (hasAccess!) await load();
    return hasAccess!;
  }

  Future<void> openSettings() {
    AdsService.instance.suppressNextAppOpen();
    return fc.FlutterContacts.permissions.openSettings();
  }

  Future<void> load() async {
    if (!await checkAccess()) return;
    loading = true;
    notifyListeners();
    try {
      all = await fc.FlutterContacts.getAll(properties: _props);
      all.sort(
        (a, b) => displayName(
          a,
        ).toLowerCase().compareTo(displayName(b).toLowerCase()),
      );
      _analyze();
      loaded = true;
    } catch (e) {
      debugPrint('contacts load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  static String displayName(Contact c) {
    final d = c.displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    final n = c.name;
    final s = [
      n?.first,
      n?.middle,
      n?.last,
    ].whereType<String>().where((e) => e.trim().isNotEmpty).join(' ');
    if (s.isNotEmpty) return s;
    if (c.phones.isNotEmpty) return c.phones.first.number;
    if (c.emails.isNotEmpty) return c.emails.first.address;
    return 'No name';
  }

  static bool hasName(Contact c) {
    final n = c.name;
    final parts = [
      n?.first,
      n?.middle,
      n?.last,
      n?.nickname,
    ].whereType<String>().where((e) => e.trim().isNotEmpty);
    if (parts.isNotEmpty) return true;
    final d = c.displayName?.trim() ?? '';
    // Android falls back to the number/email as display name when there is no name.
    return d.isNotEmpty &&
        !c.phones.any((p) => p.number.trim() == d) &&
        !c.emails.any((e) => e.address.trim() == d);
  }

  static String _normPhone(String n) {
    final digits = n.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  void _analyze() {
    incomplete = all
        .where((c) => !hasName(c) || (c.phones.isEmpty && c.emails.isEmpty))
        .toList();

    // Union-find over shared name / phone / email.
    final parent = List<int>.generate(all.length, (i) => i);
    int find(int i) => parent[i] == i ? i : (parent[i] = find(parent[i]));
    final reasons = <int, String>{};
    void union(int a, int b, String why) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
      reasons[find(a)] ??= why;
    }

    final byKey = <String, int>{};
    for (var i = 0; i < all.length; i++) {
      final c = all[i];
      final keys = <(String, String)>[
        if (hasName(c))
          (
            'n:${displayName(c).toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}',
            'Name',
          ),
        for (final p in c.phones)
          if (_normPhone(p.number).length >= 6)
            ('p:${_normPhone(p.number)}', 'Number'),
        for (final e in c.emails)
          if (e.address.trim().isNotEmpty)
            ('e:${e.address.trim().toLowerCase()}', 'Email'),
      ];
      for (final (k, why) in keys) {
        final j = byKey[k];
        if (j == null) {
          byKey[k] = i;
        } else {
          union(j, i, why);
        }
      }
    }
    final groups = <int, List<int>>{};
    for (var i = 0; i < all.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }
    duplicates = [
      for (final e in groups.entries)
        if (e.value.length > 1)
          DuplicateContactGroup([
            for (final i in e.value) all[i],
          ], reasons[e.key] ?? 'Name'),
    ];
  }

  /// Combines all fields into the most complete contact (keeps the first id).
  static Contact merge(List<Contact> contacts) {
    final sorted = List.of(contacts)
      ..sort((a, b) => _richness(b).compareTo(_richness(a)));
    final base = sorted.first;
    final phones = <fc.Phone>[];
    final seenPhones = <String>{};
    final emails = <fc.Email>[];
    final seenEmails = <String>{};
    for (final c in sorted) {
      for (final p in c.phones) {
        if (seenPhones.add(_normPhone(p.number))) {
          phones.add(fc.Phone(number: p.number, label: p.label));
        }
      }
      for (final e in c.emails) {
        if (seenEmails.add(e.address.trim().toLowerCase())) {
          emails.add(fc.Email(address: e.address, label: e.label));
        }
      }
    }
    return base.copyWith(phones: phones, emails: emails);
  }

  static int _richness(Contact c) =>
      (hasName(c) ? 4 : 0) +
      c.phones.length * 2 +
      c.emails.length +
      c.organizations.length +
      c.addresses.length;

  // ---------------------------------------------------------------- actions

  Future<void> deleteContacts(
    List<Contact> contacts, {
    bool backup = true,
  }) async {
    if (contacts.isEmpty) return;
    if (backup) await createBackup();
    await fc.FlutterContacts.deleteAll(contacts.map((c) => c.id!).toList());
    await load();
  }

  Future<int> mergeGroups(
    List<DuplicateContactGroup> groups, {
    bool backup = true,
  }) async {
    if (groups.isEmpty) return 0;
    if (backup) await createBackup();
    var removed = 0;
    for (final g in groups) {
      try {
        final merged = merge(g.contacts);
        await fc.FlutterContacts.update(merged);
        final others = g.contacts
            .where((c) => c.id != merged.id)
            .map((c) => c.id!)
            .toList();
        await fc.FlutterContacts.deleteAll(others);
        removed += others.length;
      } catch (e) {
        debugPrint('merge failed: $e');
      }
    }
    await load();
    return removed;
  }

  // ---------------------------------------------------------------- backups

  Future<Directory> _backupDir() async {
    final d = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/contact_backups',
    );
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Map<String, dynamic> toPortable(Contact c) {
    final json = c.toJson()
      ..remove('id')
      ..remove('android')
      ..remove('metadata')
      ..remove('photo');
    return json;
  }

  static Contact fromPortable(Map json) {
    final c = Contact.fromJson(json);
    return Contact(
      name: c.name,
      phones: [
        for (final p in c.phones) fc.Phone(number: p.number, label: p.label),
      ],
      emails: [
        for (final e in c.emails) fc.Email(address: e.address, label: e.label),
      ],
      addresses: c.addresses,
      organizations: c.organizations,
      websites: c.websites,
      notes: c.notes,
      events: c.events,
    );
  }

  Future<ContactBackup?> createBackup() async {
    try {
      final contacts = all.isNotEmpty
          ? all
          : await fc.FlutterContacts.getAll(properties: _props);
      if (contacts.isEmpty) return null;
      final dir = await _backupDir();
      final now = DateTime.now();
      final file = File(
        '${dir.path}/backup_${now.millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(
        jsonEncode({
          'date': now.millisecondsSinceEpoch,
          'contacts': contacts.map(toPortable).toList(),
        }),
      );
      notifyListeners();
      return ContactBackup(file, now, contacts.length);
    } catch (e) {
      debugPrint('backup failed: $e');
      return null;
    }
  }

  Future<List<ContactBackup>> backups() async {
    final dir = await _backupDir();
    final out = <ContactBackup>[];
    for (final f in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    )) {
      try {
        final m = jsonDecode(await f.readAsString()) as Map;
        out.add(
          ContactBackup(
            f,
            DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
            (m['contacts'] as List).length,
          ),
        );
      } catch (_) {}
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<List<Contact>> backupContacts(ContactBackup b) async {
    final m = jsonDecode(await b.file.readAsString()) as Map;
    return [for (final c in m['contacts'] as List) fromPortable(c as Map)];
  }

  /// Re-creates contacts from a backup that are missing from the phonebook.
  Future<int> restore(List<Contact> contacts) async {
    final existingPhones = {
      for (final c in all)
        for (final p in c.phones) _normPhone(p.number),
    };
    final existingNames = {for (final c in all) displayName(c).toLowerCase()};
    final missing = contacts.where((c) {
      final samePhone = c.phones.any(
        (p) => existingPhones.contains(_normPhone(p.number)),
      );
      final sameName = existingNames.contains(displayName(c).toLowerCase());
      return !(samePhone && sameName);
    }).toList();
    if (missing.isNotEmpty) await fc.FlutterContacts.createAll(missing);
    await load();
    return missing.length;
  }

  Future<void> deleteBackups(List<ContactBackup> list) async {
    for (final b in list) {
      try {
        await b.file.delete();
      } catch (_) {}
    }
    notifyListeners();
  }
}
