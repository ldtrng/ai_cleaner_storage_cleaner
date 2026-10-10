import 'package:flutter/material.dart';

import '../ads/ad_widgets.dart';
import '../core/format.dart';
import '../data/contacts_repository.dart';
import '../data/events_repository.dart';
import '../data/media_repository.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'apps_screen.dart';
import 'compress_screen.dart';
import 'contacts_screen.dart';
import 'events_screen.dart';
import 'media_cleaner_screen.dart';
import 'secret_space_screen.dart';
import 'settings_screen.dart';
import 'smart_clean_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final media = MediaRepository.instance;
  final contacts = ContactsRepository.instance;
  final events = EventsRepository.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    media.scan();
    if (await contacts.checkAccess() && !contacts.loaded) contacts.load();
    if (await events.checkAccess() && !events.loaded) events.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Permissions may have been granted from system settings.
    final hadAccess = media.hasAccess;
    media.checkPermission().then((_) {
      if (!hadAccess && media.hasAccess) media.scan(force: true);
    });
    media.refreshStorage();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      bottom: const BannerAdBar(),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([media, contacts, events]),
          builder: (context, _) => RefreshIndicator(
            onRefresh: () async {
              await media.scan(force: true);
              await _load();
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            appName,
                            style: context.text.headlineMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _open(const SettingsScreen()),
                          icon: const Icon(Icons.settings_outlined),
                          iconSize: 26,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: _StorageCard(
                      onSmartClean: () => _open(const SmartCleanScreen()),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.08,
                    children: [
                      _FeatureCard(
                        icon: Icons.photo_library_rounded,
                        title: 'Photos',
                        value: _mediaValue(MediaCategory.photoCategories),
                        onTap: () =>
                            _open(const MediaCleanerScreen(video: false)),
                      ),
                      _FeatureCard(
                        icon: Icons.video_library_rounded,
                        title: 'Videos',
                        value: _mediaValue(MediaCategory.videoCategories),
                        onTap: () =>
                            _open(const MediaCleanerScreen(video: true)),
                      ),
                      _FeatureCard(
                        icon: Icons.contacts_rounded,
                        title: 'Contacts',
                        value: _contactsValue(),
                        onTap: () => _open(const ContactsScreen()),
                      ),
                      _FeatureCard(
                        icon: Icons.event_rounded,
                        title: 'Events',
                        value: _eventsValue(),
                        onTap: () => _open(const EventsScreen()),
                      ),
                      _FeatureCard(
                        icon: Icons.compress_rounded,
                        title: 'Compress',
                        value: _compressValue(),
                        onTap: () => _open(const CompressScreen()),
                      ),
                      _FeatureCard(
                        icon: Icons.apps_rounded,
                        title: 'App Manager',
                        value: 'Remove unused apps',
                        onTap: () => _open(const AppsScreen()),
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AppCard(
                      onTap: () => _open(const SecretSpaceScreen()),
                      color: context.isDark ? Palette.moss : Palette.forest,
                      child: Row(
                        children: [
                          const PillIcon(
                            icon: Icons.lock_rounded,
                            size: 52,
                            background: Palette.cream,
                            foreground: Palette.forest,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Secret Space',
                                  style: font(
                                    18,
                                    FontWeight.w600,
                                    color: Palette.cream,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Hide private photos & contacts',
                                  style: font(
                                    13,
                                    FontWeight.w400,
                                    color: Palette.mist,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Palette.cream,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _mediaValue(List<MediaCategory> cats) {
    if (media.permission != null && !media.hasAccess) return 'Allow access';
    if (!cats.every(media.isReady)) return 'Analyzing...';
    final bytes = media.bytesOf(media.defaultCleanup(cats));
    return bytes == 0 ? 'All clean' : '${formatBytes(bytes)} to clean';
  }

  String _contactsValue() {
    if (contacts.hasAccess == false) return 'Allow access';
    if (!contacts.loaded) return 'Analyzing...';
    final n = contacts.duplicateCleanCount + contacts.incomplete.length;
    return n == 0 ? 'All clean' : '$n to clean';
  }

  String _eventsValue() {
    if (events.hasAccess == false) return 'Allow access';
    if (!events.loaded) return 'Analyzing...';
    return events.past.isEmpty ? 'All clean' : '${events.past.length} to clean';
  }

  String _compressValue() {
    if (!media.hasAccess) return 'Save space';
    final bytes =
        media.photos
                .where((p) => p.isJpeg && p.size > 1500000)
                .fold(0, (a, p) => a + p.size) ~/
            2 +
        media.videos
                .where((v) => v.size > 20000000)
                .fold(0, (a, v) => a + v.size) ~/
            2;
    return bytes > 0 ? 'Save up to ${formatBytes(bytes)}' : 'Save space';
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.onSmartClean});
  final VoidCallback onSmartClean;

  @override
  Widget build(BuildContext context) {
    final media = MediaRepository.instance;
    final total = media.storageTotal;
    final free = media.storageFree;
    final used = (total - free).clamp(0, total);
    final mediaBytes = media.mediaBytes.clamp(0, used);
    final toClean = media.photosToCleanBytes + media.videosToCleanBytes;
    final other = (used - mediaBytes).clamp(0, used);
    final pct = total > 0 ? used / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.moss, Palette.forest],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Palette.forest.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(pct * 100).round()}%',
                style: font(
                  44,
                  FontWeight.w700,
                  color: Palette.cream,
                  height: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    total > 0
                        ? '${formatBytes(used)} of ${formatBytes(total)} used'
                        : 'Checking storage...',
                    style: font(14, FontWeight.w500, color: Palette.mist),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 16,
              child: total == 0
                  ? const ColoredBox(color: Color(0x33E3EED4))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _seg(
                          mediaBytes - toClean.clamp(0, mediaBytes),
                          total,
                          Palette.cream,
                        ),
                        _seg(toClean.clamp(0, mediaBytes), total, Palette.mist),
                        _seg(other, total, Palette.sage),
                        _seg(free, total, const Color(0x33E3EED4)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend('Media', mediaBytes, Palette.cream),
              _legend('To clean', toClean, Palette.mist),
              _legend('Other', other, Palette.sage),
              _legend('Available', free, const Color(0x55E3EED4)),
            ],
          ),
          if (media.state == ScanState.loading ||
              media.state == ScanState.analyzing) ...[
            const SizedBox(height: 16),
            Text(
              'Analyzing files on your device...',
              style: font(13, FontWeight.w500, color: Palette.mist),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: media.state == ScanState.analyzing
                    ? media.analysisProgress
                    : null,
                minHeight: 6,
                color: Palette.cream,
                backgroundColor: const Color(0x33E3EED4),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.cream,
              foregroundColor: Palette.forest,
            ),
            onPressed: onSmartClean,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 20),
                SizedBox(width: 8),
                Text('Smart Clean Now'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(int value, int total, Color color) {
    if (value <= 0 || total <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: (value * 1000 ~/ total).clamp(1, 1000),
      child: ColoredBox(color: color),
    );
  }

  Widget _legend(String label, int bytes, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$label ', style: font(12, FontWeight.w400, color: Palette.mist)),
      Text(
        formatBytes(bytes),
        style: font(12, FontWeight.w600, color: Palette.cream),
      ),
    ],
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final attention = value.endsWith('to clean');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PillIcon(icon: icon),
          const Spacer(),
          Text(title, style: context.text.titleMedium),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: font(
              13,
              attention ? FontWeight.w600 : FontWeight.w400,
              color: attention
                  ? (context.isDark ? Palette.cream : Palette.moss)
                  : context.tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
