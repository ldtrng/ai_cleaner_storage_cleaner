import 'package:flutter/material.dart';

import '../core/firebase.dart';

import '../core/format.dart';
import '../core/settings.dart';
import '../data/media_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'media_preview_screen.dart';
import 'success_screen.dart';

/// Photos or Videos cleaner with category tabs.
class MediaCleanerScreen extends StatefulWidget {
  const MediaCleanerScreen({super.key, required this.video, this.initial});
  final bool video;
  final MediaCategory? initial;

  @override
  State<MediaCleanerScreen> createState() => _MediaCleanerScreenState();
}

class _MediaCleanerScreenState extends State<MediaCleanerScreen> {
  final repo = MediaRepository.instance;
  late List<MediaCategory> cats = widget.video
      ? MediaCategory.videoCategories
      : MediaCategory.photoCategories;
  late MediaCategory current = widget.initial ?? cats.first;

  // Selection per category, re-seeded whenever the repository produces a new result.
  final _selection = <MediaCategory, Set<int>>{};
  final _seededFrom = <MediaCategory, CategoryResult>{};

  String get _noun => widget.video ? 'video' : 'photo';

  Set<int> _sel(CategoryResult r) {
    if (!identical(_seededFrom[r.category], r)) {
      final prev = _selection[r.category];
      final valid = r.all.map((e) => e.id).toSet();
      _selection[r.category] = prev == null
          ? Set.of(r.defaultSelection)
          : prev.intersection(valid);
      _seededFrom[r.category] = r;
    }
    return _selection[r.category]!;
  }

  void _toggle(CategoryResult r, int id) => setState(() {
    final s = _sel(r);
    s.contains(id) ? s.remove(id) : s.add(id);
  });

  Future<void> _clean(CategoryResult r) async {
    final s = _sel(r);
    final items = r.all.where((i) => s.contains(i.id)).toList();
    if (items.isEmpty) return;
    final done = await repo.delete(items);
    if (!mounted || done.isEmpty) return;
    _selection[r.category]!.removeAll(done.map((e) => e.id));
    Analytics.event('clean_complete', {
      'source': widget.video ? 'videos' : 'photos',
      'category': r.category.name,
      'items': done.length,
      'bytes': repo.bytesOf(done),
    });
    final trash = AppSettings.instance.mediaRecovery == MediaRecovery.trash;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: "You've cleaned your ${widget.video ? 'videos' : 'photos'}",
          deleted: plural(done.length, _noun),
          freedBytes: repo.bytesOf(done),
          note: trash
              ? 'To clean up storage permanently or recover media, go to the "Trash" album on your device.'
              : null,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    repo.scan();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final r = repo.result(current);
        final sel = r == null ? <int>{} : _sel(r);
        final bytes = r == null
            ? 0
            : r.all
                  .where((i) => sel.contains(i.id))
                  .fold(0, (a, i) => a + i.size);
        return GradientScaffold(
          title: widget.video ? 'Videos' : 'Photos',
          body: !repo.hasAccess && repo.permission != null
              ? NoAccessView(
                  icon: widget.video
                      ? Icons.video_library_rounded
                      : Icons.photo_library_rounded,
                  title: widget.video
                      ? 'No access to Videos'
                      : 'No access to Photos',
                  message:
                      'To clean up storage, go to Settings and allow access.',
                  onAllow: () async {
                    if (!await repo.requestPermission()) repo.openSettings();
                  },
                )
              : Column(
                  children: [
                    CategoryChips<MediaCategory>(
                      items: cats,
                      selected: current,
                      label: (c) {
                        final cr = repo.result(c);
                        return cr == null
                            ? c.title
                            : '${c.title}  ${cr.all.length}';
                      },
                      onSelected: (c) => setState(() => current = c),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _body(r, sel)),
                  ],
                ),
          bottom: r == null || r.isEmpty
              ? null
              : BottomAction(
                  label: sel.isEmpty
                      ? 'Clean'
                      : 'Clean ${plural(sel.length, _noun)} · ${formatBytes(bytes)}',
                  icon: Icons.cleaning_services_rounded,
                  onPressed: sel.isEmpty ? null : () => _clean(r),
                ),
        );
      },
    );
  }

  Widget _body(CategoryResult? r, Set<int> sel) {
    if (r == null) {
      return _Analyzing(
        title:
            'Analyzing ${current.title}${widget.video ? ' Videos' : ' Photos'}...',
        progress: repo.state == ScanState.analyzing
            ? repo.analysisProgress
            : null,
      );
    }
    if (r.isEmpty) return const EmptyState();

    final allSelected = sel.length == r.all.length;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${plural(r.all.length, _noun)} · ${formatBytes(repo.bytesOf(r.all))}',
              style: context.text.bodyMedium?.copyWith(
                color: context.tokens.textMuted,
              ),
            ),
          ),
          SelectAllButton(
            allSelected: allSelected,
            onChanged: (v) => setState(() {
              sel.clear();
              if (v) sel.addAll(r.all.map((e) => e.id));
            }),
          ),
        ],
      ),
    );

    if (!current.grouped) {
      final items = r.all;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => MediaThumb(
                item: items[i],
                selected: sel.contains(items[i].id),
                showSize: widget.video,
                onTap: () => _toggle(r, items[i].id),
                onLongPress: () => _preview(r, items, i),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
      itemCount: r.groups.length + 1,
      itemBuilder: (context, gi) {
        if (gi == 0) return header;
        final g = r.groups[gi - 1];
        final groupAll = g.items.every((i) => sel.contains(i.id));
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${plural(g.items.length, _noun)}  ·  ${formatDate(g.items.first.dateTime)}',
                        style: context.text.titleSmall,
                      ),
                    ),
                    SelectAllButton(
                      allSelected: groupAll,
                      onChanged: (v) => setState(() {
                        for (final i in g.items) {
                          v ? sel.add(i.id) : sel.remove(i.id);
                        }
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (var i = 0; i < g.items.length; i++)
                        MediaThumb(
                          item: g.items[i],
                          best: g.items[i] == g.best,
                          selected: sel.contains(g.items[i].id),
                          onTap: () => _toggle(r, g.items[i].id),
                          onLongPress: () => _preview(r, g.items, i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _preview(CategoryResult r, List<MediaItem> items, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewScreen(
          items: items,
          initialIndex: index,
          isSelected: (id) => _sel(r).contains(id),
          onToggle: (id) => _toggle(r, id),
        ),
      ),
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing({required this.title, this.progress});
  final String title;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 7,
                strokeCap: StrokeCap.round,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (progress != null) ...[
              const SizedBox(height: 6),
              Text(
                '${(progress! * 100).round()}%',
                style: context.text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
