import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/settings.dart';
import 'contacts_repository.dart';
import 'media_repository.dart';

class VaultMedia {
  VaultMedia({
    required this.file,
    required this.isVideo,
    required this.originalName,
    required this.originalPath,
    required this.addedAt,
    required this.takenAt,
  });

  final File file;
  final bool isVideo;
  final String originalName;
  final String originalPath;
  final DateTime addedAt;
  final DateTime takenAt;

  Map<String, dynamic> toJson() => {
    'file': p.basename(file.path),
    'video': isVideo,
    'name': originalName,
    'path': originalPath,
    'added': addedAt.millisecondsSinceEpoch,
    'taken': takenAt.millisecondsSinceEpoch,
  };
}

class VaultContact {
  VaultContact(this.id, this.contact);
  final String id;
  final Contact contact;
}

/// Secret Space: PIN-protected private copies of media and contacts stored in the app sandbox.
class VaultRepository extends ChangeNotifier {
  VaultRepository._();
  static final instance = VaultRepository._();

  final _auth = LocalAuthentication();
  final _prefs = AppSettings.instance.prefs;

  bool unlocked = false;
  List<VaultMedia> media = [];
  List<VaultContact> contacts = [];

  bool get hasPin => _prefs.getString('vaultPinHash') != null;

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  void setPin(String pin) {
    final salt = base64Url.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    _prefs.setString('vaultPinSalt', salt);
    _prefs.setString('vaultPinHash', _hash(pin, salt));
    unlocked = true;
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final salt = _prefs.getString('vaultPinSalt') ?? '';
    final ok = _prefs.getString('vaultPinHash') == _hash(pin, salt);
    if (ok) unlocked = true;
    notifyListeners();
    return ok;
  }

  void lock() {
    unlocked = false;
    notifyListeners();
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({
    bool biometricOnly = true,
    String reason = 'Unlock Secret Space',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
      if (ok && biometricOnly) {
        unlocked = true;
        notifyListeners();
      }
      return ok;
    } catch (e) {
      debugPrint('auth failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------- storage

  Future<Directory> _dir(String name) async {
    final d = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/vault/$name',
    );
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _index(String name) async =>
      File('${(await _dir('')).path}/$name.json');

  Future<void> load() async {
    try {
      final mediaDir = await _dir('media');
      final mi = await _index('media');
      if (await mi.exists()) {
        final list = jsonDecode(await mi.readAsString()) as List;
        media = [
          for (final m in list.cast<Map>())
            VaultMedia(
              file: File('${mediaDir.path}/${m['file']}'),
              isVideo: m['video'] as bool,
              originalName: m['name'] as String,
              originalPath: m['path'] as String,
              addedAt: DateTime.fromMillisecondsSinceEpoch(m['added'] as int),
              takenAt: DateTime.fromMillisecondsSinceEpoch(m['taken'] as int),
            ),
        ]..removeWhere((m) => !m.file.existsSync());
      }
      final ci = await _index('contacts');
      if (await ci.exists()) {
        final map = jsonDecode(await ci.readAsString()) as Map;
        contacts = [
          for (final e in map.entries)
            VaultContact(
              e.key as String,
              ContactsRepository.fromPortable(e.value as Map),
            ),
        ];
      }
    } catch (e) {
      debugPrint('vault load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _saveMedia() async => (await _index(
    'media',
  )).writeAsString(jsonEncode(media.map((m) => m.toJson()).toList()));

  Future<void> _saveContacts() async =>
      (await _index('contacts')).writeAsString(
        jsonEncode({
          for (final c in contacts)
            c.id: ContactsRepository.toPortable(c.contact),
        }),
      );

  /// Copies gallery items into the vault. Returns the items that were copied.
  Future<List<MediaItem>> addMedia(List<MediaItem> items) async {
    final dir = await _dir('media');
    final added = <MediaItem>[];
    for (final item in items) {
      try {
        final src = await item.entity.originFile;
        if (src == null) continue;
        final ext = p.extension(item.name).isNotEmpty
            ? p.extension(item.name)
            : (item.isVideo ? '.mp4' : '.jpg');
        final dest = File(
          '${dir.path}/${DateTime.now().microsecondsSinceEpoch}$ext',
        );
        await src.copy(dest.path);
        media.insert(
          0,
          VaultMedia(
            file: dest,
            isVideo: item.isVideo,
            originalName: item.name,
            originalPath: item.path,
            addedAt: DateTime.now(),
            takenAt: item.dateTime,
          ),
        );
        added.add(item);
      } catch (e) {
        debugPrint('vault add failed: $e');
      }
    }
    await _saveMedia();
    notifyListeners();
    return added;
  }

  Future<void> removeMedia(
    List<VaultMedia> items, {
    required bool restore,
  }) async {
    for (final m in items) {
      try {
        if (restore) {
          final rel = m.originalPath.isNotEmpty
              ? m.originalPath
              : (m.isVideo ? 'Movies/' : 'Pictures/');
          if (m.isVideo) {
            await PhotoManager.editor.saveVideo(
              m.file,
              title: m.originalName,
              relativePath: rel,
              creationDate: m.takenAt,
            );
          } else {
            await PhotoManager.editor.saveImageWithPath(
              m.file.path,
              title: m.originalName,
              relativePath: rel,
              creationDate: m.takenAt,
            );
          }
        }
        await m.file.delete();
      } catch (e) {
        debugPrint('vault remove failed: $e');
      }
      media.remove(m);
    }
    await _saveMedia();
    notifyListeners();
  }

  Future<void> addContacts(List<Contact> list) async {
    for (final c in list) {
      contacts.add(
        VaultContact(
          '${DateTime.now().microsecondsSinceEpoch}_${contacts.length}',
          ContactsRepository.fromPortable(ContactsRepository.toPortable(c)),
        ),
      );
    }
    await _saveContacts();
    notifyListeners();
  }

  Future<void> removeContacts(
    List<VaultContact> list, {
    required bool restore,
  }) async {
    if (restore) {
      await fc.FlutterContacts.createAll(list.map((c) => c.contact).toList());
    }
    final ids = list.map((e) => e.id).toSet();
    contacts.removeWhere((c) => ids.contains(c.id));
    await _saveContacts();
    notifyListeners();
  }
}
