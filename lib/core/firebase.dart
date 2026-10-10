import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Firebase bootstrap. Everything degrades to no-ops / defaults when Firebase isn't configured
/// (no android/app/google-services.json) or the network is unavailable.
abstract final class AppFirebase {
  static bool ready = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
    } catch (e) {
      debugPrint('Firebase not configured: $e');
      return;
    }
    await Config.init();
  }
}

/// Remote Config keys with in-app defaults. Keep these in sync with the Firebase console
/// (see docs/remote-config.json).
abstract final class Config {
  static const defaults = <String, Object>{
    'ads_enabled': true,
    'banner_home_enabled': true,
    'native_success_enabled': true,
    'interstitial_enabled': true,
    'interstitial_cooldown_sec': 180,
    'interstitial_min_success': 2,
    'app_open_enabled': true,
    'app_open_cold_start_wait_ms': 3000,
    'app_open_background_min': 4,
    'blurry_sharpness_threshold': 15.0,
  };

  static FirebaseRemoteConfig? get _rc =>
      AppFirebase.ready ? FirebaseRemoteConfig.instance : null;

  static Future<void> init() async {
    final rc = _rc;
    if (rc == null) return;
    try {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          minimumFetchInterval: kReleaseMode
              ? const Duration(hours: 1)
              : const Duration(minutes: 1),
        ),
      );
      await rc.setDefaults(defaults);
      // Activate whatever was fetched last session immediately, refresh in the background.
      await rc.activate();
      rc.fetchAndActivate().catchError((Object e) {
        debugPrint('remote config fetch failed: $e');
        return false;
      });
    } catch (e) {
      debugPrint('remote config init failed: $e');
    }
  }

  static bool flag(String key) => _rc?.getBool(key) ?? defaults[key] as bool;
  static int integer(String key) => _rc?.getInt(key) ?? defaults[key] as int;
  static double decimal(String key) =>
      _rc?.getDouble(key) ?? (defaults[key] as num).toDouble();

  static bool get adsEnabled => flag('ads_enabled');
}

/// Thin analytics wrapper: event names/params follow GA4 rules (snake_case, ≤40 chars).
abstract final class Analytics {
  static FirebaseAnalytics? get _a =>
      AppFirebase.ready ? FirebaseAnalytics.instance : null;

  static void event(String name, [Map<String, Object>? params]) {
    _a
        ?.logEvent(name: name, parameters: params)
        .catchError((Object e) => debugPrint('analytics: $e'));
  }

  static void screen(String name) {
    _a
        ?.logScreenView(screenName: name, screenClass: name)
        .catchError((Object e) => debugPrint('analytics: $e'));
  }

  static void cleaned(String source, {required int items, int bytes = 0}) =>
      event('clean_complete', {
        'source': source,
        'items': items,
        'bytes': bytes,
      });
}

/// Logs a screen_view for every pushed page, named after the `*Screen` widget it shows.
class ScreenViewObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _log(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _log(previousRoute);
  }

  void _log(Route<dynamic> route) {
    if (route is! PageRoute) return;
    final named = route.settings.name;
    if (named != null && named != '/') return Analytics.screen(named);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = route.subtreeContext;
      if (ctx == null) return;
      final name = _findScreen(ctx);
      if (name != null) Analytics.screen(name);
    });
  }

  static String? _findScreen(BuildContext ctx) {
    String? found;
    void visit(Element e, int depth) {
      if (found != null || depth > 40) return;
      final type = e.widget.runtimeType.toString();
      if (type.endsWith('Screen') && !type.startsWith('_')) {
        found = type.replaceAll('Screen', '');
        return;
      }
      e.visitChildElements((c) => visit(c, depth + 1));
    }

    (ctx as Element).visitChildElements((c) => visit(c, 0));
    return found;
  }
}
