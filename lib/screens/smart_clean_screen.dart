import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/native.dart';
import '../core/settings.dart';
import '../data/contacts_repository.dart';
import '../data/events_repository.dart';
import '../data/media_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'success_screen.dart';

enum _Extra { duplicateContacts, incompleteContacts, pastEvents }

class SmartCleanScreen extends StatefulWidget {
  const SmartCleanScreen({super.key});

  @override
  State<SmartCleanScreen> createState() => _SmartCleanScreenState();
}

class _SmartCleanScreenState extends State<SmartCleanScreen> {
  final media = MediaRepository.instance;
  final contacts = ContactsRepository.instance;
  final events = EventsRepository.instance;

  final Set<Object> _on = {
    ...MediaCategory.values.where((c) => c != MediaCategory.blurry),
    _Extra.duplicateContacts,
    _Extra.pastEvents,
  };

  @override
  void initState() {
    super.initState();
    media.scan();
    contacts.checkAccess().then(
      (ok) => ok && !contacts.loaded ? contacts.load() : null,
    );
    events.checkAccess().then(
      (ok) => ok && !events.loaded ? events.load() : null,
    );
  }

  List<MediaCategory> _enabled(List<MediaCategory> cats) =>
      cats.where(_on.contains).toList();

  List<MediaItem> get _mediaItems => media.defaultCleanup(
    _enabled([
      ...MediaCategory.photoCategories,
      ...MediaCategory.videoCategories,
    ]),
  );

  int get _contactCount =>
      (_on.contains(_Extra.duplicateContacts)
          ? contacts.duplicateCleanCount
          : 0) +
      (_on.contains(_Extra.incompleteContacts)
          ? contacts.incomplete.length
          : 0);

  int get _eventCount =>
      _on.contains(_Extra.pastEvents) && events.hasAccess == true
      ? events.past.length
      : 0;

  Future<void> _start() async {
    final items = _mediaItems;
    final photos = items.where((i) => !i.isVideo).length;
    final videos = items.length - photos;
    final dupGroups = _on.contains(_Extra.duplicateContacts)
        ? contacts.duplicates
        : <DuplicateContactGroup>[];
    final incomplete = _on.contains(_Extra.incompleteContacts)
        ? contacts.incomplete
        : <Contact>[];
    final pastEvents = _eventCount > 0
        ? List.of(events.past)
        : <CalendarEvent>[];

    final lines = [
      if (photos > 0) 'Clean ${plural(photos, 'photo')}',
      if (videos > 0) 'Clean ${plural(videos, 'video')}',
      if (dupGroups.isNotEmpty)
        'Merge ${plural(contacts.duplicateCleanCount, 'duplicate contact')}',
      if (incomplete.isNotEmpty)
        'Delete ${plural(incomplete.length, 'incomplete contact')}',
      if (pastEvents.isNotEmpty)
        'Delete ${plural(pastEvents.length, 'past event')}',
    ];
    if (lines.isEmpty) return;
    final ok = await showConfirm(
      context,
      title: 'Allow cleaning?',
      message: lines.map((l) => '•  $l').join('\n'),
      confirm: 'Clean',
    );
    if (!ok || !mounted) return;

    // Media first: Android shows its own confirmation dialog.
    final removed = await media.delete(items);
    if (!mounted) return;

    var contactsDone = 0;
    var eventsDone = 0;
    await runWithProgress(context, (progress) async {
      if (dupGroups.isNotEmpty || incomplete.isNotEmpty) {
        await contacts.createBackup();
      }
      progress.value = 0.2;
      if (dupGroups.isNotEmpty) {
        contactsDone += await contacts.mergeGroups(dupGroups, backup: false);
      }
      progress.value = 0.5;
      if (incomplete.isNotEmpty) {
        await contacts.deleteContacts(incomplete, backup: false);
        contactsDone += incomplete.length;
      }
      progress.value = 0.75;
      if (pastEvents.isNotEmpty) eventsDone = await events.delete(pastEvents);
      progress.value = 1;
      await Future.delayed(const Duration(milliseconds: 600));
    });
    if (!mounted) return;
    final total = removed.length + contactsDone + eventsDone;
    if (total == 0) return;
    final freed = media.bytesOf(removed);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: "You've cleaned your phone",
          deleted: [
            if (removed.isNotEmpty) plural(removed.length, 'file'),
            if (contactsDone > 0) plural(contactsDone, 'contact'),
            if (eventsDone > 0) plural(eventsDone, 'event'),
          ].join('\n'),
          freedBytes: freed > 0 ? freed : null,
          note:
              removed.isNotEmpty &&
                  AppSettings.instance.mediaRecovery == MediaRecovery.trash
              ? 'Media stays in your device "Trash" for 30 days. Contacts were backed up before cleaning.'
              : 'Contacts were backed up before cleaning.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([media, contacts, events]),
      builder: (context, _) {
        final items = _mediaItems;
        final bytes = media.bytesOf(items);
        final count = items.length + _contactCount + _eventCount;
        final analyzing = media.state != ScanState.done && media.hasAccess;
        return GradientScaffold(
          title: 'Smart Cleaning',
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
            children: [
              _SummaryBox(
                bytes: bytes,
                analyzing: analyzing,
                progress: media.analysisProgress,
              ),
              const SizedBox(height: 24),
              Text('Optimize your storage', style: context.text.titleLarge),
              const SizedBox(height: 12),
              _mediaSection(
                title: 'Photos',
                icon: Icons.photo_library_rounded,
                cats: MediaCategory.photoCategories,
                note: 'Photos stay in "Trash" for 30 days',
              ),
              const SizedBox(height: 12),
              _mediaSection(
                title: 'Videos',
                icon: Icons.video_library_rounded,
                cats: MediaCategory.videoCategories,
                note: 'Videos stay in "Trash" for 30 days',
              ),
              const SizedBox(height: 12),
              _Section(
                icon: Icons.contacts_rounded,
                title: contacts.loaded
                    ? plural(_contactCount, 'Contact')
                    : 'Contacts',
                subtitle: 'Backup created with each cleaning',
                noAccess: contacts.hasAccess == false,
                onAllow: () async {
                  if (!await contacts.requestAccess()) contacts.openSettings();
                },
                rows: [
                  _row(
                    _Extra.duplicateContacts,
                    'Duplicate',
                    contacts.loaded ? '${contacts.duplicateCleanCount}' : null,
                  ),
                  _row(
                    _Extra.incompleteContacts,
                    'Incomplete',
                    contacts.loaded ? '${contacts.incomplete.length}' : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                icon: Icons.event_rounded,
                title: events.loaded ? plural(_eventCount, 'Event') : 'Events',
                subtitle: 'Past events are permanently deleted',
                noAccess: events.hasAccess == false,
                onAllow: () async {
                  if (!await events.requestAccess()) Native.openAppSettings();
                },
                rows: [
                  _row(
                    _Extra.pastEvents,
                    'Past',
                    events.loaded ? '${events.past.length}' : null,
                  ),
                ],
              ),
            ],
          ),
          bottom: BottomAction(
            label: count == 0
                ? 'Start Cleaning'
                : 'Start Cleaning · ${formatBytes(bytes)}',
            icon: Icons.auto_awesome_rounded,
            onPressed: count == 0 ? null : _start,
          ),
        );
      },
    );
  }

  Widget _mediaSection({
    required String title,
    required IconData icon,
    required List<MediaCategory> cats,
    required String note,
  }) {
    final items = media.defaultCleanup(_enabled(cats));
    return _Section(
      icon: icon,
      title: media.hasAccess
          ? '${plural(items.length, title.substring(0, title.length - 1))} · ${formatBytes(media.bytesOf(items))}'
          : title,
      subtitle: AppSettings.instance.mediaRecovery == MediaRecovery.trash
          ? note
          : 'Deleted permanently',
      noAccess: media.permission != null && !media.hasAccess,
      onAllow: () async {
        if (!await media.requestPermission()) media.openSettings();
      },
      rows: [
        for (final c in cats)
          _row(
            c,
            c.title,
            media.isReady(c) ? '${media.result(c)!.cleanableCount}' : null,
          ),
      ],
    );
  }

  Widget _row(Object key, String label, String? value) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: _on.contains(key),
      onChanged: (v) => setState(() => v ? _on.add(key) : _on.remove(key)),
      title: Text(label, style: context.text.bodyLarge),
      secondary: SizedBox(
        width: 48,
        child: value == null
            ? const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Text(
                value,
                textAlign: TextAlign.right,
                style: context.text.titleMedium,
              ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.bytes,
    required this.analyzing,
    required this.progress,
  });
  final int bytes;
  final bool analyzing;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Palette.forest,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Give your phone a boost',
                  style: font(13, FontWeight.w500, color: Palette.mist),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Clean up to '),
                      TextSpan(
                        text: formatBytes(bytes),
                        style: font(22, FontWeight.w700, color: Palette.cream),
                      ),
                      const TextSpan(text: ' for a lag-free phone!'),
                    ],
                  ),
                  style: font(
                    18,
                    FontWeight.w500,
                    color: Palette.cream,
                    height: 1.3,
                  ),
                ),
                if (analyzing) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    color: Palette.cream,
                    backgroundColor: const Color(0x33E3EED4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const PillIcon(
            icon: Icons.rocket_launch_rounded,
            size: 60,
            background: Palette.cream,
            foreground: Palette.forest,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.noAccess,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> rows;
  final bool noAccess;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        children: [
          Row(
            children: [
              PillIcon(icon: icon, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.text.titleMedium),
                    Text(subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (noAccess)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: OutlinedButton(
                onPressed: onAllow,
                child: const Text('Allow access'),
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}
