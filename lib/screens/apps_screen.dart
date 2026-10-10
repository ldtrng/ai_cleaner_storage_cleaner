import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/native.dart';
import '../data/apps_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'success_screen.dart';

enum _Sort { size, usage }

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> with WidgetsBindingObserver {
  final repo = AppsRepository.instance;
  final _sel = <String>{};
  _Sort sort = _Sort.size;
  Completer<void>? _resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_resumed != null && !_resumed!.isCompleted) {
      _resumed!.complete();
    } else {
      Native.hasUsageAccess().then((ok) {
        if (ok != repo.usageAccess) repo.load();
      });
    }
  }

  List<InstalledApp> get _sorted {
    final list = List.of(repo.apps);
    if (sort == _Sort.size) {
      list.sort((a, b) => b.size.compareTo(a.size));
    } else {
      list.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    }
    return list;
  }

  Future<void> _uninstall() async {
    final targets = repo.apps.where((a) => _sel.contains(a.package)).toList();
    final ok = await showConfirm(
      context,
      title: targets.length == 1
          ? 'Remove 1 app?'
          : 'Remove ${targets.length} apps?',
      message:
          'Android will ask you to confirm each app. You won’t be able to use them unless you reinstall them.',
      confirm: 'Remove',
      cancel: 'Cancel',
    );
    if (!ok) return;
    final removed = <InstalledApp>[];
    for (final app in targets) {
      _resumed = Completer();
      await Native.uninstallApp(app.package);
      // Wait until the system uninstall dialog returns to us.
      await _resumed!.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {},
      );
      await Future.delayed(const Duration(milliseconds: 400));
      if (!await Native.isInstalled(app.package)) removed.add(app);
    }
    _resumed = null;
    repo.removeLocal(removed.map((a) => a.package).toSet());
    _sel.removeAll(removed.map((a) => a.package));
    if (!mounted || removed.isEmpty) return;
    final freed = removed.fold(0, (a, e) => a + (e.size > 0 ? e.size : 0));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: 'Your unused apps are deleted!',
          deleted: plural(removed.length, 'app'),
          freedBytes: freed > 0 ? freed : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final apps = _sorted;
        final selBytes = apps
            .where((a) => _sel.contains(a.package))
            .fold(0, (s, a) => s + (a.size > 0 ? a.size : 0));
        return GradientScaffold(
          title: 'App Manager',
          body: !repo.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  children: [
                    if (!repo.usageAccess)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          color: context.isDark ? Palette.moss : Palette.forest,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'See app sizes & last use',
                                style: font(
                                  17,
                                  FontWeight.w600,
                                  color: Palette.cream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Allow usage access to find the apps you don’t use and how much space they take.',
                                style: font(
                                  13,
                                  FontWeight.w400,
                                  color: Palette.mist,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tip: find AI Cleaner in the list and turn it on.',
                                style: font(
                                  12,
                                  FontWeight.w400,
                                  color: Palette.mist,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Palette.cream,
                                  foregroundColor: Palette.forest,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: Native.openUsageAccessSettings,
                                child: const Text('Allow access'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            repo.usageAccess
                                ? '${plural(apps.length, 'app')} · ${formatBytes(repo.totalSize)}'
                                : plural(apps.length, 'app'),
                            style: context.text.bodySmall,
                          ),
                        ),
                        if (repo.usageAccess)
                          SegmentedButton<_Sort>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              selectedBackgroundColor: context.isDark
                                  ? Palette.cream
                                  : Palette.moss,
                              selectedForegroundColor: context.isDark
                                  ? Palette.forest
                                  : Palette.cream,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: _Sort.size,
                                label: Text('Size'),
                              ),
                              ButtonSegment(
                                value: _Sort.usage,
                                label: Text('Usage'),
                              ),
                            ],
                            selected: {sort},
                            onSelectionChanged: (s) =>
                                setState(() => sort = s.first),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (apps.isEmpty) const EmptyState(),
                    for (final a in apps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          radius: 22,
                          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                          onTap: () => setState(
                            () => _sel.contains(a.package)
                                ? _sel.remove(a.package)
                                : _sel.add(a.package),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: a.icon != null
                                    ? Image.memory(
                                        a.icon!,
                                        width: 44,
                                        height: 44,
                                        gaplessPlayback: true,
                                      )
                                    : const PillIcon(
                                        icon: Icons.android_rounded,
                                        size: 44,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.titleSmall,
                                    ),
                                    Text(
                                      [
                                        if (a.size > 0) formatBytes(a.size),
                                        if (repo.usageAccess)
                                          'Last used: ${timeAgo(a.lastUsed)}',
                                        if (!repo.usageAccess)
                                          'Installed ${formatDate(DateTime.fromMillisecondsSinceEpoch(a.installTime))}',
                                      ].join(' · '),
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: _sel.contains(a.package),
                                onChanged: (v) => setState(
                                  () => v!
                                      ? _sel.add(a.package)
                                      : _sel.remove(a.package),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          bottom: _sel.isEmpty
              ? null
              : BottomAction(
                  label:
                      'Delete ${plural(_sel.length, 'app')}${selBytes > 0 ? ' · ${formatBytes(selBytes)}' : ''}',
                  icon: Icons.delete_outline_rounded,
                  onPressed: _uninstall,
                ),
        );
      },
    );
  }
}
