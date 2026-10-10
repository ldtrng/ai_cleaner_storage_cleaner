import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../ads/ads_service.dart';
import '../core/firebase.dart';
import '../core/native.dart';
import '../core/settings.dart';

class MediaItem {
  MediaItem.fromMap(Map<dynamic, dynamic> m, {required this.isVideo})
    : id = (m['id'] as num).toInt(),
      size = (m['size'] as num).toInt(),
      width = (m['width'] as num).toInt(),
      height = (m['height'] as num).toInt(),
      date = (m['date'] as num).toInt(),
      modified = (m['modified'] as num).toInt(),
      durationMs = (m['duration'] as num).toInt(),
      orientation = (m['orientation'] as num).toInt(),
      path = m['path'] as String,
      name = m['name'] as String,
      mime = m['mime'] as String;

  final int id;
  final int size;
  final int width;
  final int height;

  /// Seconds since epoch.
  final int date;
  final int modified;
  final int durationMs;
  final int orientation;
  final String path;
  final String name;
  final String mime;
  final bool isVideo;

  // Filled by image analysis.
  int? hash;
  double sharpness = 0;
  double contrast = 0;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date * 1000);

  late final AssetEntity entity = AssetEntity(
    id: '$id',
    typeInt: isVideo ? 2 : 1,
    width: width,
    height: height,
    duration: durationMs ~/ 1000,
    orientation: orientation,
    title: name,
    relativePath: path,
    mimeType: mime,
    createDateSecond: date,
    modifiedDateSecond: modified,
  );

  bool get isScreenshot {
    final p = '$path/$name'.toLowerCase();
    return p.contains('screenshot');
  }

  bool get isScreenRecording {
    final p = '$path/$name'.toLowerCase();
    return isVideo && (p.contains('screen') || p.contains('record_'));
  }

  bool get isJpeg => mime == 'image/jpeg' || mime == 'image/jpg';
}

enum MediaCategory {
  similar('Similar', grouped: true),
  duplicatePhotos('Duplicate', grouped: true),
  screenshots('Screenshots'),
  blurry('Blurry'),
  duplicateVideos('Duplicate', grouped: true, video: true),
  screenRecordings('Screen Recordings', video: true),
  shortRecordings('Short Recordings', video: true);

  const MediaCategory(this.title, {this.grouped = false, this.video = false});

  final String title;
  final bool grouped;
  final bool video;

  /// Whether the category needs pixel analysis before it can be shown.
  bool get needsAnalysis =>
      this == similar || this == duplicatePhotos || this == blurry;

  static const photoCategories = [
    similar,
    duplicatePhotos,
    screenshots,
    blurry,
  ];
  static const videoCategories = [
    duplicateVideos,
    screenRecordings,
    shortRecordings,
  ];
}

class MediaGroup {
  MediaGroup(this.items, this.best);
  final List<MediaItem> items;

  /// Item kept by default (null for flat categories).
  final MediaItem? best;
}

class CategoryResult {
  CategoryResult(this.category, this.groups);
  final MediaCategory category;
  final List<MediaGroup> groups;

  late final List<MediaItem> all = [for (final g in groups) ...g.items];

  /// Everything except each group's best shot.
  late final Set<int> defaultSelection = {
    for (final g in groups)
      for (final i in g.items)
        if (i != g.best) i.id,
  };

  late final int cleanableBytes = all
      .where((i) => defaultSelection.contains(i.id))
      .fold(0, (a, i) => a + i.size);

  int get cleanableCount => defaultSelection.length;
  bool get isEmpty => groups.isEmpty;
}

enum ScanState { idle, loading, analyzing, done }

class MediaRepository extends ChangeNotifier {
  MediaRepository._();
  static final instance = MediaRepository._();

  static const _permOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  PermissionState? permission;
  bool get hasAccess => permission?.hasAccess ?? false;

  ScanState state = ScanState.idle;
  double analysisProgress = 0;

  List<MediaItem> photos = [];
  List<MediaItem> videos = [];
  final Map<MediaCategory, CategoryResult> _results = {};

  int storageTotal = 0;
  int storageFree = 0;

  int get mediaBytes =>
      photos.fold(0, (a, i) => a + i.size) +
      videos.fold(0, (a, i) => a + i.size);
  int get photoBytes => photos.fold(0, (a, i) => a + i.size);
  int get videoBytes => videos.fold(0, (a, i) => a + i.size);

  CategoryResult? result(MediaCategory c) => _results[c];

  bool isReady(MediaCategory c) => _results.containsKey(c);

  /// Unique items selected by default across the given categories.
  List<MediaItem> defaultCleanup(Iterable<MediaCategory> cats) {
    final byId = <int, MediaItem>{};
    for (final c in cats) {
      final r = _results[c];
      if (r == null) continue;
      for (final i in r.all) {
        if (r.defaultSelection.contains(i.id)) byId[i.id] = i;
      }
    }
    return byId.values.toList();
  }

  int bytesOf(Iterable<MediaItem> items) => items.fold(0, (a, i) => a + i.size);

  int get photosToCleanBytes =>
      bytesOf(defaultCleanup(MediaCategory.photoCategories));
  int get videosToCleanBytes =>
      bytesOf(defaultCleanup(MediaCategory.videoCategories));

  Future<void> refreshStorage() async {
    try {
      final s = await Native.storageInfo();
      storageTotal = s.total;
      storageFree = s.free;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> checkPermission() async {
    permission = await PhotoManager.getPermissionState(
      requestOption: _permOption,
    );
    notifyListeners();
  }

  Future<bool> requestPermission() async {
    permission = await PhotoManager.requestPermissionExtend(
      requestOption: _permOption,
    );
    notifyListeners();
    if (hasAccess && state == ScanState.idle) scan();
    return hasAccess;
  }

  Future<void> openSettings() {
    AdsService.instance.suppressNextAppOpen();
    return PhotoManager.openSetting();
  }

  Future<void>? _scanning;

  /// Lists media and runs analysis. Safe to call repeatedly.
  Future<void> scan({bool force = false}) {
    if (_scanning != null) return _scanning!;
    if (!force && state == ScanState.done) return Future.value();
    return _scanning = _scan().whenComplete(() => _scanning = null);
  }

  Future<void> _scan() async {
    await refreshStorage();
    await checkPermission();
    if (!hasAccess) return;

    state = ScanState.loading;
    _results.clear();
    notifyListeners();

    final rawPhotos = await Native.queryMedia('image');
    final rawVideos = await Native.queryMedia('video');
    photos = rawPhotos
        .map((m) => MediaItem.fromMap(m, isVideo: false))
        .toList();
    videos = rawVideos.map((m) => MediaItem.fromMap(m, isVideo: true)).toList();

    _computeVideoCategories();
    _results[MediaCategory.screenshots] =
        CategoryResult(MediaCategory.screenshots, [
          if (photos.any((p) => p.isScreenshot))
            MediaGroup(photos.where((p) => p.isScreenshot).toList(), null),
        ]);
    state = ScanState.analyzing;
    analysisProgress = 0;
    notifyListeners();

    final started = DateTime.now();
    await _analyzePhotos();
    _computePhotoCategories();
    Analytics.event('scan_complete', {
      'photos': photos.length,
      'videos': videos.length,
      'analysis_ms': DateTime.now().difference(started).inMilliseconds,
      'cleanable_bytes': photosToCleanBytes + videosToCleanBytes,
    });
    state = ScanState.done;
    notifyListeners();
  }

  Future<File> _cacheFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/analysis_v1.json');

  Future<void> _analyzePhotos() async {
    final file = await _cacheFile();
    Map<String, dynamic> cache = {};
    try {
      if (await file.exists()) {
        cache = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}

    final pending = <MediaItem>[];
    for (final p in photos) {
      final c = cache['${p.id}'] as List?;
      if (c != null && c[0] == p.modified) {
        p.hash = (c[1] as num).toInt();
        p.sharpness = (c[2] as num).toDouble();
        p.contrast = (c[3] as num).toDouble();
      } else {
        pending.add(p);
      }
    }

    const batch = 48;
    for (var i = 0; i < pending.length; i += batch) {
      final chunk = pending.sublist(i, math.min(i + batch, pending.length));
      try {
        final res = await Native.analyzeImages(chunk.map((e) => e.id).toList());
        final byId = {for (final p in chunk) p.id: p};
        for (final r in res) {
          final p = byId[(r['id'] as num).toInt()];
          if (p == null) continue;
          p.hash = (r['hash'] as num).toInt();
          p.sharpness = (r['sharpness'] as num).toDouble();
          p.contrast = (r['contrast'] as num).toDouble();
        }
      } catch (e) {
        debugPrint('analyze failed: $e');
      }
      analysisProgress = (i + chunk.length) / pending.length;
      notifyListeners();
    }

    final out = <String, dynamic>{
      for (final p in photos)
        if (p.hash != null)
          '${p.id}': [p.modified, p.hash, p.sharpness, p.contrast],
    };
    try {
      await file.writeAsString(jsonEncode(out));
    } catch (_) {}
  }

  static int _hamming(int a, int b) {
    var x = a ^ b;
    var n = 0;
    while (x != 0) {
      x &= x - 1;
      n++;
    }
    return n;
  }

  static double _quality(MediaItem i) =>
      i.sharpness * math.sqrt(i.width * i.height + 1);

  void _computePhotoCategories() {
    final analyzed = photos.where((p) => p.hash != null).toList();

    // Exact duplicates: identical perceptual hash and dimensions.
    final dupBuckets = <String, List<MediaItem>>{};
    for (final p in analyzed) {
      dupBuckets
          .putIfAbsent('${p.hash}_${p.width}x${p.height}', () => [])
          .add(p);
    }
    final dupGroups = <MediaGroup>[];
    final inDup = <int>{};
    for (final items in dupBuckets.values.where((l) => l.length > 1)) {
      items.sort((a, b) => a.date.compareTo(b.date));
      dupGroups.add(MediaGroup(items, items.first));
      inDup.addAll(items.map((e) => e.id));
    }
    dupGroups.sort((a, b) => b.items.first.date.compareTo(a.items.first.date));

    // Similar: shots taken close together that look alike.
    final candidates =
        analyzed.where((p) => !p.isScreenshot && !inDup.contains(p.id)).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final simGroups = <MediaGroup>[];
    var current = <MediaItem>[];
    void flush() {
      if (current.length > 1) {
        final best = current.reduce(
          (a, b) => _quality(a) >= _quality(b) ? a : b,
        );
        simGroups.add(MediaGroup(List.of(current), best));
      }
      current = [];
    }

    for (final p in candidates) {
      if (current.isEmpty) {
        current.add(p);
        continue;
      }
      final last = current.last;
      final close = (p.date - last.date).abs() <= 30 * 60;
      final alike =
          _hamming(p.hash!, last.hash!) <= 10 &&
          _hamming(p.hash!, current.first.hash!) <= 14;
      if (close && alike) {
        current.add(p);
      } else {
        flush();
        current.add(p);
      }
    }
    flush();
    simGroups.sort((a, b) => b.items.first.date.compareTo(a.items.first.date));

    final blurry =
        analyzed
            .where(
              (p) =>
                  !p.isScreenshot &&
                  p.sharpness < Config.decimal('blurry_sharpness_threshold') &&
                  p.contrast > 12,
            )
            .toList()
          ..sort((a, b) => a.sharpness.compareTo(b.sharpness));

    _results[MediaCategory.duplicatePhotos] = CategoryResult(
      MediaCategory.duplicatePhotos,
      dupGroups,
    );
    _results[MediaCategory.similar] = CategoryResult(
      MediaCategory.similar,
      simGroups,
    );
    _results[MediaCategory.blurry] = CategoryResult(MediaCategory.blurry, [
      if (blurry.isNotEmpty) MediaGroup(blurry, null),
    ]);
    _results[MediaCategory.screenshots] =
        CategoryResult(MediaCategory.screenshots, [
          if (photos.any((p) => p.isScreenshot))
            MediaGroup(photos.where((p) => p.isScreenshot).toList(), null),
        ]);
  }

  void _computeVideoCategories() {
    final buckets = <String, List<MediaItem>>{};
    for (final v in videos) {
      buckets.putIfAbsent('${v.size}_${v.durationMs ~/ 500}', () => []).add(v);
    }
    final dup = <MediaGroup>[];
    for (final items in buckets.values.where((l) => l.length > 1)) {
      items.sort((a, b) => a.date.compareTo(b.date));
      dup.add(MediaGroup(items, items.first));
    }
    final screen = videos.where((v) => v.isScreenRecording).toList();
    final short = videos
        .where(
          (v) =>
              !v.isScreenRecording && v.durationMs > 0 && v.durationMs < 5000,
        )
        .toList();
    _results[MediaCategory.duplicateVideos] = CategoryResult(
      MediaCategory.duplicateVideos,
      dup,
    );
    _results[MediaCategory.screenRecordings] = CategoryResult(
      MediaCategory.screenRecordings,
      [if (screen.isNotEmpty) MediaGroup(screen, null)],
    );
    _results[MediaCategory.shortRecordings] = CategoryResult(
      MediaCategory.shortRecordings,
      [if (short.isNotEmpty) MediaGroup(short, null)],
    );
  }

  /// Deletes (or trashes, per settings) the items. Android shows its own confirmation.
  /// Returns the items that were actually removed.
  Future<List<MediaItem>> delete(
    List<MediaItem> items, {
    bool permanent = false,
  }) async {
    if (items.isEmpty) return [];
    final useTrash =
        !permanent &&
        AppSettings.instance.mediaRecovery == MediaRecovery.trash &&
        await Native.sdkInt() >= 30;
    final removed = <String>{};
    const chunk = 400;
    for (var i = 0; i < items.length; i += chunk) {
      final part = items.sublist(i, math.min(i + chunk, items.length));
      try {
        final r = useTrash
            ? await PhotoManager.editor.android.moveToTrash(
                part.map((e) => e.entity).toList(),
              )
            : await PhotoManager.editor.deleteWithIds(
                part.map((e) => '${e.id}').toList(),
              );
        removed.addAll(r);
      } catch (e) {
        debugPrint('delete failed: $e');
      }
      if (removed.isEmpty) break; // user declined the system dialog
    }
    final done = items.where((i) => removed.contains('${i.id}')).toList();
    if (done.isNotEmpty) {
      if (!permanent) AppSettings.instance.addCleanedBytes(bytesOf(done));
      removeLocal(done.map((e) => e.id).toSet());
      refreshStorage();
    }
    return done;
  }

  /// Drops items from memory and recomputes categories without re-analysing.
  void removeLocal(Set<int> ids) {
    photos.removeWhere((p) => ids.contains(p.id));
    videos.removeWhere((v) => ids.contains(v.id));
    _computeVideoCategories();
    if (state == ScanState.done) _computePhotoCategories();
    notifyListeners();
  }
}
