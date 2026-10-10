import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/format.dart';
import '../data/media_repository.dart';
import '../theme/app_theme.dart';

class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.isSelected,
    this.onToggle,
  });

  final List<MediaItem> items;
  final int initialIndex;
  final bool Function(int id)? isSelected;
  final void Function(int id)? onToggle;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late final _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    final selected = widget.isSelected?.call(item.id) ?? false;
    return Scaffold(
      backgroundColor: Palette.forest,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: Palette.cream,
        title: Text(
          'Preview',
          style: font(18, FontWeight.w600, color: Palette.cream),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final it = widget.items[i];
                return it.isVideo
                    ? _VideoView(item: it, key: ValueKey(it.id))
                    : InteractiveViewer(
                        child: Center(
                          child: Image(
                            image: AssetEntityImageProvider(
                              it.entity,
                              isOriginal: true,
                            ),
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, p) => p == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(
                                      color: Palette.cream,
                                    ),
                                  ),
                          ),
                        ),
                      );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: font(
                            15,
                            FontWeight.w600,
                            color: Palette.cream,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatBytes(item.size)} · ${item.width}×${item.height} · ${formatDate(item.dateTime)}',
                          style: font(12, FontWeight.w400, color: Palette.mist),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onToggle != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: selected
                            ? Palette.cream
                            : Palette.moss,
                        foregroundColor: selected
                            ? Palette.forest
                            : Palette.cream,
                      ),
                      onPressed: () =>
                          setState(() => widget.onToggle!(item.id)),
                      icon: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                      ),
                      label: Text(selected ? 'Selected' : 'Select'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({super.key, required this.item});
  final MediaItem item;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final File? f = await widget.item.entity.file;
    if (f == null || !mounted) return;
    final c = VideoPlayerController.file(f);
    await c.initialize();
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(
      () => _c = c
        ..setLooping(true)
        ..play(),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return const Center(
        child: CircularProgressIndicator(color: Palette.cream),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              if (!c.value.isPlaying)
                const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 72,
                  color: Palette.cream,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays a local file (used by Secret Space).
class FileVideoView extends StatefulWidget {
  const FileVideoView({super.key, required this.file});
  final File file;

  @override
  State<FileVideoView> createState() => _FileVideoViewState();
}

class _FileVideoViewState extends State<FileVideoView> {
  late final _c = VideoPlayerController.file(widget.file);

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(
          () => _c
            ..setLooping(true)
            ..play(),
        );
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Palette.cream),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
      child: Center(
        child: AspectRatio(
          aspectRatio: _c.value.aspectRatio,
          child: VideoPlayer(_c),
        ),
      ),
    );
  }
}
