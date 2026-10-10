import 'package:flutter/services.dart';

import '../ads/ads_service.dart';

/// Thin wrapper over the Kotlin side (see android/.../NativeBridge.kt).
abstract final class Native {
  static const _ch = MethodChannel('io.ld2t.ai_cleaner/native');

  static int? _sdkInt;
  static Future<int> sdkInt() async =>
      _sdkInt ??= (await _ch.invokeMethod<int>('sdkInt')) ?? 29;

  static Future<({int total, int free})> storageInfo() async {
    final m = await _ch.invokeMapMethod<String, dynamic>('storageInfo') ?? {};
    return (
      total: (m['total'] as num?)?.toInt() ?? 0,
      free: (m['free'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<Map<dynamic, dynamic>>> queryMedia(String type) async =>
      (await _ch.invokeListMethod<Map<dynamic, dynamic>>('queryMedia', {
        'type': type,
      })) ??
      [];

  static Future<List<Map<dynamic, dynamic>>> analyzeImages(
    List<int> ids,
  ) async =>
      (await _ch.invokeListMethod<Map<dynamic, dynamic>>('analyzeImages', {
        'ids': ids,
      })) ??
      [];

  static Future<List<Map<dynamic, dynamic>>> queryPastEvents() async =>
      (await _ch.invokeListMethod<Map<dynamic, dynamic>>('queryPastEvents')) ??
      [];

  static Future<int> deleteEvents(List<int> ids) async =>
      (await _ch.invokeMethod<int>('deleteEvents', {'ids': ids})) ?? 0;

  static Future<bool> hasUsageAccess() async =>
      (await _ch.invokeMethod<bool>('hasUsageAccess')) ?? false;

  static Future<void> openUsageAccessSettings() {
    AdsService.instance.suppressNextAppOpen();
    return _ch.invokeMethod('openUsageAccessSettings');
  }

  static Future<List<Map<dynamic, dynamic>>> listApps() async =>
      (await _ch.invokeListMethod<Map<dynamic, dynamic>>('listApps')) ?? [];

  static Future<void> uninstallApp(String pkg) {
    AdsService.instance.suppressNextAppOpen();
    return _ch.invokeMethod('uninstallApp', {'package': pkg});
  }

  static Future<bool> isInstalled(String pkg) async =>
      (await _ch.invokeMethod<bool>('isInstalled', {'package': pkg})) ?? false;

  static Future<void> openAppSettings() {
    AdsService.instance.suppressNextAppOpen();
    return _ch.invokeMethod('openAppSettings');
  }

  /// Returns the path of the re-encoded file in the app cache.
  static Future<String> compressVideo(
    int id, {
    required double factor,
    required int maxShortSide,
  }) async => (await _ch.invokeMethod<String>('compressVideo', {
    'id': id,
    'factor': factor,
    'maxShortSide': maxShortSide,
  }))!;

  static Future<int> videoProgress() async =>
      (await _ch.invokeMethod<int>('videoProgress')) ?? -1;

  static Future<void> cancelVideoCompress() =>
      _ch.invokeMethod('cancelVideoCompress');
}
