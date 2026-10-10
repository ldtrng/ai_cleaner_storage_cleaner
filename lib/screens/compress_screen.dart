import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/format.dart';
import '../core/native.dart';
import '../data/media_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'media_preview_screen.dart';
import 'success_screen.dart';

enum _Kind { photos, videos }

enum Quality {
  high(
    'High quality',
    'Compress up to 20% of the size',
    0.2,
    photoQuality: 80,
    photoShortSide: 100000,
    videoFactor: 0.7,
    videoShortSide: 1080,
  ),
  medium(
    'Medium quality',
    'Compress up to 50% of the size',
    0.5,
    photoQuality: 65,
    photoShortSide: 2048,
    videoFactor: 0.45,
    videoShortSide: 720,
  ),
  low(
    'Low quality',
    'Compress up to 80% of the size',
    0.8,
    photoQuality: 45,
    photoShortSide: 1440,
    videoFactor: 0.22,
    videoShortSide: 480,
  );

  const Quality(
    this.title,
    this.message,
    this.saving, {
    required this.photoQuality,
    required this.photoShortSide,
    required this.videoFactor,
    required this.videoShortSide,
  });

  final String title;
  final String message;
  final double saving;
  final int photoQuality;
  final int photoShortSide;
  final double videoFactor;
  final int videoShortSide;
}

class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key});

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  static const maxPhotos = 20;
  final repo = MediaRepository.instance;
  _Kind kind = _Kind.photos;
  final _photoSel = <int>{};
  int? _videoSel;

  @override
  void initState() {
    super.initState();
    repo.scan();
  }

  List<MediaItem> get _photos =>
      repo.photos.where((p) => p.isJpeg && p.size > 500 * 1000).toList()
        ..sort((a, b) => b.size.compareTo(a.size));

  List<MediaItem> get _videos =>
      repo.videos.where((v) => v.size > 5 * 1000 * 1000).toList()
        ..sort((a, b) => b.size.compareTo(a.size));

  List<MediaItem> get _selected => kind == _Kind.photos
      ? repo.photos.where((p) => _photoSel.contains(p.id)).toList()
      : repo.videos.where((v) => v.id == _videoSel).toList();

  void _togglePhoto(int id) {
    setState(() {
      if (_photoSel.contains(id)) {
        _photoSel.remove(id);
      } else if (_photoSel.length >= maxPhotos) {
        showToast(
          context,
          'You can only compress $maxPhotos photos at a time.',
        );
      } else {
        _photoSel.add(id);
      }
    });
  }

  Future<void> _start() async {
    final items = _selected;
    if (items.isEmpty) return;
    final q = await showModalBottomSheet<Quality>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QualitySheet(items: items, video: kind == _Kind.videos),
    );
    if (q == null || !mounted) return;

    final originals = <MediaItem>[];
    var before = 0;
    var after = 0;
    String? error;
    await runWithProgress(
      context,
      title: 'Compressing...',
      message: "We're freeing up space on your device.",
      (progress) async {
        if (kind == _Kind.photos) {
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            try {
              final file = await item.entity.originFile;
              if (file == null) continue;
              final bytes = await FlutterImageCompress.compressWithFile(
                file.absolute.path,
                minWidth: q.photoShortSide,
                minHeight: q.photoShortSide,
                quality: q.photoQuality,
                keepExif: true,
              );
              if (bytes != null && bytes.length < item.size * 0.95) {
                await PhotoManager.editor.saveImage(
                  bytes,
                  filename: item.name,
                  title: item.name,
                  relativePath: item.path.isNotEmpty
                      ? item.path
                      : 'Pictures/Compressed',
                  creationDate: item.dateTime,
                );
                originals.add(item);
                before += item.size;
                after += bytes.length;
              }
            } catch (e) {
              error = '$e';
            }
            progress.value = (i + 1) / items.length;
          }
        } else {
          final item = items.first;
          final timer = Timer.periodic(const Duration(milliseconds: 500), (
            _,
          ) async {
            final p = await Native.videoProgress();
            if (p >= 0) progress.value = p / 100;
          });
          try {
            final path = await Native.compressVideo(
              item.id,
              factor: q.videoFactor,
              maxShortSide: q.videoShortSide,
            );
            final out = File(path);
            final size = await out.length();
            if (size < item.size * 0.95) {
              await PhotoManager.editor.saveVideo(
                out,
                title: item.name,
                relativePath: item.path.isNotEmpty
                    ? item.path
                    : 'Movies/Compressed',
                creationDate: item.dateTime,
              );
              originals.add(item);
              before += item.size;
              after += size;
            }
            await out.delete();
          } catch (e) {
            error = '$e';
          } finally {
            timer.cancel();
          }
        }
      },
    );
    if (!mounted) return;

    if (originals.isEmpty) {
      showToast(
        context,
        error != null
            ? 'Sorry! Something went wrong.'
            : 'These files are already well optimized.',
      );
      return;
    }
    final deleteOriginals = await showConfirm(
      context,
      title:
          'Do you want to delete the original ${originals.length == 1 ? 'file' : 'files'} from Gallery?',
      message: 'The compressed copies have been saved next to the originals.',
      confirm: 'Yes, delete',
      cancel: 'No',
    );
    var freed = 0;
    if (deleteOriginals) {
      final removed = await repo.delete(originals);
      freed = removed.isEmpty ? 0 : before - after;
    }
    _photoSel.clear();
    _videoSel = null;
    repo.scan(force: true);
    if (!mounted) return;
    final pct = before > 0 ? ((before - after) * 100 / before).round() : 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: 'Your media was compressed',
          firstLabel: 'Compressed',
          deleted: plural(originals.length, 'item'),
          freedLabel: freed > 0 ? formatBytes(freed) : '$pct% smaller',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final list = kind == _Kind.photos ? _photos : _videos;
        final selected = _selected;
        final selBytes = repo.bytesOf(selected);
        return GradientScaffold(
          title: 'Compress',
          body: !repo.hasAccess && repo.permission != null
              ? NoAccessView(
                  icon: Icons.compress_rounded,
                  title: 'No access to Photos and Videos',
                  message: 'To compress media files, allow access.',
                  onAllow: () async {
                    if (!await repo.requestPermission()) repo.openSettings();
                  },
                )
              : Column(
                  children: [
                    CategoryChips<_Kind>(
                      items: _Kind.values,
                      selected: kind,
                      label: (k) => k == _Kind.photos ? 'Photos' : 'Videos',
                      onSelected: (k) => setState(() => kind = k),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: AppCard(
                        color: context.isDark ? Palette.moss : Palette.forest,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Compress your media files and save up to',
                                style: font(
                                  14,
                                  FontWeight.w500,
                                  color: Palette.mist,
                                ),
                              ),
                            ),
                            Text(
                              formatBytes(repo.bytesOf(list) * 0.5),
                              style: font(
                                22,
                                FontWeight.w700,
                                color: Palette.cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child:
                          repo.state == ScanState.loading ||
                              repo.state == ScanState.idle
                          ? const Center(child: CircularProgressIndicator())
                          : list.isEmpty
                          ? const EmptyState(title: 'Nothing to compress here.')
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                4,
                                16,
                                120,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                  ),
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final item = list[i];
                                final on = kind == _Kind.photos
                                    ? _photoSel.contains(item.id)
                                    : _videoSel == item.id;
                                return MediaThumb(
                                  item: item,
                                  selected: on,
                                  showSize: true,
                                  onTap: () => kind == _Kind.photos
                                      ? _togglePhoto(item.id)
                                      : setState(
                                          () => _videoSel = on ? null : item.id,
                                        ),
                                  onLongPress: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MediaPreviewScreen(
                                        items: list,
                                        initialIndex: i,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
          bottom: selected.isEmpty
              ? null
              : BottomAction(
                  label: kind == _Kind.photos
                      ? 'Compress ${plural(selected.length, 'photo')} · ${formatBytes(selBytes)}'
                      : 'Compress video · ${formatBytes(selBytes)}',
                  icon: Icons.compress_rounded,
                  onPressed: _start,
                ),
        );
      },
    );
  }
}

class _QualitySheet extends StatefulWidget {
  const _QualitySheet({required this.items, required this.video});
  final List<MediaItem> items;
  final bool video;

  @override
  State<_QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<_QualitySheet> {
  Quality q = Quality.medium;

  @override
  Widget build(BuildContext context) {
    final total = widget.items.fold(0, (a, i) => a + i.size);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select ${widget.video ? 'video' : 'photo'} quality after compression',
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            for (final option in Quality.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  radius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: option == q
                      ? (context.isDark ? Palette.moss : Palette.mist)
                      : null,
                  onTap: () => setState(() => q = option),
                  child: Row(
                    children: [
                      Icon(
                        option == q
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: context.isDark ? Palette.cream : Palette.moss,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.title, style: context.text.titleSmall),
                            Text(option.message, style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      Text(
                        '-${formatBytes(total * option.saving)}',
                        style: context.text.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () => Navigator.pop(context, q),
              child: Text('Compress ${formatBytes(total)}'),
            ),
          ],
        ),
      ),
    );
  }
}
