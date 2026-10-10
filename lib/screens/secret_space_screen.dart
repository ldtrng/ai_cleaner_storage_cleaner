import 'package:flutter/material.dart';

import '../core/firebase.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import '../core/format.dart';
import '../data/contacts_repository.dart';
import '../data/media_repository.dart';
import '../data/vault_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'media_preview_screen.dart';

/// Entry point: create PIN → unlock → vault.
class SecretSpaceScreen extends StatefulWidget {
  const SecretSpaceScreen({super.key});

  @override
  State<SecretSpaceScreen> createState() => _SecretSpaceScreenState();
}

class _SecretSpaceScreenState extends State<SecretSpaceScreen> {
  final vault = VaultRepository.instance;

  @override
  void initState() {
    super.initState();
    vault.load();
  }

  @override
  void dispose() {
    vault.lock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        if (!vault.hasPin) return const _PinScreen(mode: _PinMode.create);
        if (!vault.unlocked) return const _PinScreen(mode: _PinMode.enter);
        return const _VaultHome();
      },
    );
  }
}

// ------------------------------------------------------------------ PIN

enum _PinMode { create, enter }

class _PinScreen extends StatefulWidget {
  const _PinScreen({required this.mode});
  final _PinMode mode;

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen>
    with SingleTickerProviderStateMixin {
  static const length = 4;
  final vault = VaultRepository.instance;
  String _pin = '';
  String? _first; // create flow: first entry awaiting confirmation
  String? _error;
  bool _bio = false;
  bool _resetting = false;
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  bool get _creating => widget.mode == _PinMode.create || _resetting;

  @override
  void initState() {
    super.initState();
    if (widget.mode == _PinMode.enter) {
      vault.canUseBiometrics().then((ok) {
        if (!mounted) return;
        setState(() => _bio = ok);
        if (ok) vault.authenticate();
      });
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _tap(String d) {
    if (_pin.length >= length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == length) {
      Future.delayed(const Duration(milliseconds: 150), _submit);
    }
  }

  void _fail(String msg) {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _error = msg;
      _pin = '';
    });
  }

  void _submit() {
    if (_creating) {
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
        });
      } else if (_first == _pin) {
        vault.setPin(_pin);
      } else {
        _first = null;
        _fail('PINs did not match. Try again.');
      }
    } else if (!vault.verifyPin(_pin)) {
      _fail('Incorrect PIN');
    }
  }

  Future<void> _reset() async {
    final ok = await showConfirm(
      context,
      title: 'Reset your PIN',
      message:
          'Before resetting your PIN, we need to verify your identity using your device lock.',
      confirm: 'Verify identity',
      cancel: 'Cancel',
    );
    if (!ok) return;
    if (await vault.authenticate(
      biometricOnly: false,
      reason: 'Verify your identity to reset the PIN',
    )) {
      setState(() {
        _resetting = true;
        _first = null;
        _pin = '';
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _creating
        ? (_first == null ? 'Set a new PIN' : 'Confirm PIN')
        : 'Enter PIN';
    return GradientScaffold(
      title: 'Secret Space',
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            if (_creating && _first == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Protect sensitive files and contacts in Secret Space, locked by your PIN or biometrics.',
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.tokens.textMuted,
                  ),
                ),
              ),
            const Spacer(),
            const PillIcon(icon: Icons.lock_rounded, size: 72),
            const SizedBox(height: 20),
            Text(title, style: context.text.headlineSmall),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  12 *
                      (0.5 -
                          (Curves.elasticIn.transform(_shake.value) - 0.5)
                              .abs()) *
                      (_shake.isAnimating ? 1 : 0),
                  0,
                ),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length
                            ? context.tokens.accent
                            : Colors.transparent,
                        border: Border.all(
                          color: context.tokens.accent,
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: Text(
                  _error ?? '',
                  style: font(14, FontWeight.w500, color: Palette.danger),
                ),
              ),
            ),
            const Spacer(),
            _Keypad(
              onDigit: _tap,
              onBackspace: () => setState(
                () => _pin = _pin.isEmpty
                    ? ''
                    : _pin.substring(0, _pin.length - 1),
              ),
              onBiometric: !_creating && _bio
                  ? () => vault.authenticate()
                  : null,
            ),
            const SizedBox(height: 8),
            if (!_creating)
              TextButton(onPressed: _reset, child: const Text('Reset PIN'))
            else
              const SizedBox(height: 48),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 76,
        height: 76,
        child: onTap == null
            ? null
            : Material(
                color: context.tokens.card,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Center(child: child),
                ),
              ),
      ),
    );
    Widget digit(String d) => key(
      Text(
        d,
        style: font(28, FontWeight.w500, color: context.colors.onSurface),
      ),
      () => onDigit(d),
    );
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map(digit).toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(const Icon(Icons.fingerprint_rounded, size: 32), onBiometric),
            digit('0'),
            key(const Icon(Icons.backspace_outlined), onBackspace),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Vault

enum _VaultTab { media, contacts }

class _VaultHome extends StatefulWidget {
  const _VaultHome();

  @override
  State<_VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<_VaultHome> {
  final vault = VaultRepository.instance;
  _VaultTab tab = _VaultTab.media;
  final _selMedia = <VaultMedia>{};
  final _selContacts = <String>{};

  bool get _selecting =>
      tab == _VaultTab.media ? _selMedia.isNotEmpty : _selContacts.isNotEmpty;

  Future<void> _addMedia() async {
    final media = MediaRepository.instance;
    if (!media.hasAccess && !await media.requestPermission()) {
      media.openSettings();
      return;
    }
    if (media.state == ScanState.idle) await media.scan();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<MediaItem>>(
      MaterialPageRoute(builder: (_) => const _MediaPicker()),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final added = await runWithProgress(
      context,
      (_) => vault.addMedia(picked),
      title: 'Adding...',
      message: 'Moving files into your Secret Space',
    );
    if (!mounted || added.isEmpty) return;
    final del = await showConfirm(
      context,
      title:
          'Do you also want to delete the original ${added.length == 1 ? 'file' : 'files'} from Gallery?',
      message: 'You can restore it from your Secret Space later.',
      confirm: 'Yes, delete',
      cancel: 'No, keep both',
    );
    if (del) await media.delete(added, permanent: true);
    Analytics.event('secret_space_add', {
      'kind': 'media',
      'count': added.length,
    });
    if (mounted) showToast(context, 'Media files have been added.');
  }

  Future<void> _addContacts() async {
    final repo = ContactsRepository.instance;
    if (!await repo.checkAccess() && !await repo.requestAccess()) {
      repo.openSettings();
      return;
    }
    if (!repo.loaded) await repo.load();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<Contact>>(
      MaterialPageRoute(builder: (_) => const _ContactPicker()),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await vault.addContacts(picked);
    if (!mounted) return;
    final del = await showConfirm(
      context,
      title:
          'Do you also want to delete the original ${picked.length == 1 ? 'contact' : 'contacts'} from your device?',
      message: 'You can restore it from your Secret Space later.',
      confirm: 'Yes, delete',
      cancel: 'No, keep both',
    );
    if (del) {
      await fc.FlutterContacts.deleteAll(picked.map((c) => c.id!).toList());
      await repo.load();
    }
    Analytics.event('secret_space_add', {
      'kind': 'contacts',
      'count': picked.length,
    });
    if (mounted) showToast(context, 'Contacts have been added.');
  }

  Future<void> _restoreOrRemove() async {
    final media = tab == _VaultTab.media;
    final n = media ? _selMedia.length : _selContacts.length;
    final restore = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _RemoveSheet(count: n, media: media),
    );
    if (restore == null || !mounted) return;
    await runWithProgress(
      context,
      title: restore ? 'Restoring...' : 'Removing...',
      message: restore
          ? 'Putting items back where they came from'
          : 'Removing items from Secret Space',
      (_) async {
        if (media) {
          await vault.removeMedia(_selMedia.toList(), restore: restore);
          if (restore) MediaRepository.instance.scan(force: true);
        } else {
          await vault.removeContacts(
            vault.contacts.where((c) => _selContacts.contains(c.id)).toList(),
            restore: restore,
          );
          if (restore) ContactsRepository.instance.load();
        }
      },
    );
    setState(() {
      _selMedia.clear();
      _selContacts.clear();
    });
    if (mounted) {
      showToast(
        context,
        media
            ? 'Media files have been removed.'
            : 'Contacts have been removed.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) => GradientScaffold(
        appBar: AppBar(
          title: const Text('Secret Space'),
          actions: [
            if (_selecting)
              TextButton(
                onPressed: () => setState(() {
                  _selMedia.clear();
                  _selContacts.clear();
                }),
                child: const Text('Cancel'),
              ),
          ],
        ),
        body: Column(
          children: [
            CategoryChips<_VaultTab>(
              items: _VaultTab.values,
              selected: tab,
              label: (t) => t == _VaultTab.media
                  ? 'Media  ${vault.media.length}'
                  : 'Contacts  ${vault.contacts.length}',
              onSelected: (t) => setState(() => tab = t),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: tab == _VaultTab.media ? _mediaGrid() : _contactsList(),
            ),
          ],
        ),
        bottom: BottomAction(
          label: _selecting
              ? 'Restore / Remove'
              : (tab == _VaultTab.media ? 'Add media' : 'Add contacts'),
          icon: _selecting
              ? Icons.settings_backup_restore_rounded
              : Icons.add_rounded,
          onPressed: _selecting
              ? _restoreOrRemove
              : (tab == _VaultTab.media ? _addMedia : _addContacts),
        ),
      ),
    );
  }

  Widget _mediaGrid() {
    if (vault.media.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No secret media files added.',
        message: 'Add photos and videos to keep them private.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: vault.media.length,
      itemBuilder: (context, i) {
        final m = vault.media[i];
        final on = _selMedia.contains(m);
        return GestureDetector(
          onTap: () {
            if (_selecting) {
              setState(() => on ? _selMedia.remove(m) : _selMedia.add(m));
            } else {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => _VaultViewer(index: i)));
            }
          },
          onLongPress: () => setState(() => _selMedia.add(m)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: context.tokens.track),
                if (m.isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 40,
                      color: Palette.sage,
                    ),
                  )
                else
                  Image.file(
                    m.file,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    gaplessPlayback: true,
                  ),
                if (on)
                  ColoredBox(color: Palette.forest.withValues(alpha: 0.3)),
                if (_selecting)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Icon(
                      on ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: Palette.cream,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contactsList() {
    if (vault.contacts.isEmpty) {
      return const EmptyState(
        icon: Icons.person_outline_rounded,
        title: 'No secret contacts added.',
        message: 'Add contacts to keep them private.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      itemCount: vault.contacts.length,
      itemBuilder: (context, i) {
        final c = vault.contacts[i];
        final on = _selContacts.contains(c.id);
        final name = ContactsRepository.displayName(c.contact);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            onTap: () => setState(
              () => on ? _selContacts.remove(c.id) : _selContacts.add(c.id),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: context.isDark ? Palette.moss : Palette.mist,
                  child: Text(
                    name.characters.first.toUpperCase(),
                    style: font(
                      16,
                      FontWeight.w600,
                      color: context.isDark ? Palette.cream : Palette.forest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: context.text.titleSmall),
                      Text(
                        [
                          ...c.contact.phones.map((p) => p.number),
                          ...c.contact.emails.map((e) => e.address),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_selecting)
                  Checkbox(
                    value: on,
                    onChanged: (_) => setState(
                      () => on
                          ? _selContacts.remove(c.id)
                          : _selContacts.add(c.id),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RemoveSheet extends StatefulWidget {
  const _RemoveSheet({required this.count, required this.media});
  final int count;
  final bool media;

  @override
  State<_RemoveSheet> createState() => _RemoveSheetState();
}

class _RemoveSheetState extends State<_RemoveSheet> {
  bool restore = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.media
                  ? 'Remove files from Secret Space?'
                  : 'Remove contacts from Secret Space?',
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              restore
                  ? ''
                  : "This action cannot be undone, make sure you've restored what you need.",
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            CheckboxListTile(
              value: restore,
              onChanged: (v) => setState(() => restore = v!),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                widget.media
                    ? 'Restore files to original gallery'
                    : 'Restore contacts to original phonebook',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, restore),
              child: const Text('Yes, remove'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No, cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultViewer extends StatelessWidget {
  const _VaultViewer({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final items = VaultRepository.instance.media;
    return Scaffold(
      backgroundColor: Palette.forest,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: Palette.cream,
        title: Text(
          'Media preview',
          style: font(18, FontWeight.w600, color: Palette.cream),
        ),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: index),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final m = items[i];
          return m.isVideo
              ? FileVideoView(file: m.file, key: ValueKey(m.file.path))
              : InteractiveViewer(child: Center(child: Image.file(m.file)));
        },
      ),
    );
  }
}

class _MediaPicker extends StatefulWidget {
  const _MediaPicker();

  @override
  State<_MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<_MediaPicker> {
  static const max = 10;
  final _sel = <MediaItem>{};

  @override
  Widget build(BuildContext context) {
    final repo = MediaRepository.instance;
    final all = [...repo.photos, ...repo.videos]
      ..sort((a, b) => b.date.compareTo(a.date));
    return GradientScaffold(
      title: 'Add media',
      body: all.isEmpty
          ? const EmptyState(title: 'No media found.')
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: all.length,
              itemBuilder: (context, i) {
                final item = all[i];
                final on = _sel.contains(item);
                return MediaThumb(
                  item: item,
                  selected: on,
                  onTap: () => setState(() {
                    if (on) {
                      _sel.remove(item);
                    } else if (_sel.length >= max) {
                      showToast(
                        context,
                        'You can only upload $max media files at a time.',
                      );
                    } else {
                      _sel.add(item);
                    }
                  }),
                );
              },
            ),
      bottom: BottomAction(
        label: _sel.isEmpty ? 'Add' : 'Add ${_sel.length}',
        onPressed: _sel.isEmpty
            ? null
            : () => Navigator.pop(context, _sel.toList()),
      ),
    );
  }
}

class _ContactPicker extends StatefulWidget {
  const _ContactPicker();

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  final _sel = <String>{};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = ContactsRepository.instance.all
        .where(
          (c) =>
              _q.isEmpty ||
              ContactsRepository.displayName(c).toLowerCase().contains(_q),
        )
        .toList();
    return GradientScaffold(
      title: 'Add contacts',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? const EmptyState(title: 'No contacts found.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 120),
                    itemCount: all.length,
                    itemBuilder: (context, i) {
                      final c = all[i];
                      return CheckboxListTile(
                        value: _sel.contains(c.id),
                        onChanged: (v) => setState(
                          () => v! ? _sel.add(c.id!) : _sel.remove(c.id),
                        ),
                        title: Text(ContactsRepository.displayName(c)),
                        subtitle: Text(
                          c.phones.map((p) => p.number).join(' · '),
                          maxLines: 1,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottom: BottomAction(
        label: _sel.isEmpty ? 'Add' : 'Add ${plural(_sel.length, 'contact')}',
        onPressed: _sel.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                ContactsRepository.instance.all
                    .where((c) => _sel.contains(c.id))
                    .toList(),
              ),
      ),
    );
  }
}
