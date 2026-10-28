import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/firebase.dart';
import 'ads_service.dart';

/// The one native ad of the whole app. Every native slot (see `NativeAdCard`) shows this same [NativeAd],
/// but only one slot may own it at a time: a native ad's platform view has a single parent, so two
/// [AdWidget]s on the same ad would clash. Slots that don't own it render nothing.
///
/// A new ad is requested only when the current one has been displayed [maxDisplays] times or is [maxAge] old,
/// and only at the moment a slot takes ownership, so an ad that is on screen is never swapped under the user.
class NativeAdPool extends ChangeNotifier {
  NativeAdPool._() {
    AdsService.instance.canRequestAds.addListener(_onAdsChanged);
  }
  static final NativeAdPool instance = NativeAdPool._();

  static const maxDisplays = 10;
  static const maxAge = Duration(minutes: 7);

  /// Time the previous owner's platform view gets to detach before the next slot attaches the same ad.
  static const _handover = Duration(milliseconds: 300);

  NativeAd? _ad; // requested: loading or loaded
  bool _loaded = false;
  DateTime? _loadedAt;
  int _displays = 0;
  bool _counted = false;
  Object? _loadedStyleKey;

  Object? _owner;
  DateTime? _releasedAt;
  bool Function()? _onScreen;
  NativeTemplateStyle? _style;
  Object? _styleKey;
  Timer? _countTimer;
  Timer? _retry;
  int _failures = 0;

  /// The ad for [slot]: only its owner gets one, and only once it has loaded.
  NativeAd? adFor(Object slot) =>
      (_loaded && identical(_owner, slot)) ? _ad : null;

  bool get _enabled =>
      AdsService.instance.canRequestAds.value &&
      Config.adsEnabled &&
      Config.flag('native_success_enabled');

  bool get _stale =>
      _loaded &&
      (_displays >= maxDisplays ||
          DateTime.now().difference(_loadedAt!) >= maxAge);

  /// Asks to show the ad in [slot]. [onScreen] tells whether the slot is really in view. [styleKey] identifies
  /// the look of [style] (template size, theme): an ad loaded with another key is renewed. Idempotent; does
  /// nothing while another slot owns the ad.
  void claim(
    Object slot,
    NativeTemplateStyle style,
    Object styleKey,
    bool Function() onScreen,
  ) {
    if (!_enabled) return;
    if (_owner != null && !identical(_owner, slot)) return;
    // Let the previous owner's view detach first; release() notifies when due.
    if (_owner == null &&
        _releasedAt != null &&
        DateTime.now().difference(_releasedAt!) < _handover) {
      return;
    }
    _style = style;
    _styleKey = styleKey;
    _onScreen = onScreen;
    if (!identical(_owner, slot)) {
      _owner = slot;
      _counted = false;
      // The new owner is not attached yet, so this is the safe moment to renew.
      if (_loaded && (_stale || _loadedStyleKey != styleKey)) _discard();
      _armCount();
    }
    _load();
  }

  void release(Object slot) {
    if (!identical(_owner, slot)) return;
    _owner = null;
    _releasedAt = DateTime.now();
    _countTimer?.cancel();
    // Not synchronously: release runs while the tree is being torn down.
    Timer(_handover, notifyListeners);
  }

  void _load() {
    final style = _style;
    if (_ad != null || style == null || (_retry?.isActive ?? false)) return;
    _loadedStyleKey = _styleKey;
    final ad = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (a) {
          if (!identical(a, _ad)) return;
          _loaded = true;
          _loadedAt = DateTime.now();
          _displays = 0;
          _failures = 0;
          _armCount();
          notifyListeners();
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          debugPrint('native failed: ${e.message}');
          if (!identical(a, _ad)) return;
          _ad = null;
          _loaded = false;
          // 30 s, 1 m, 2 m, 4 m, then every 5 m while some slot wants the ad.
          final wait = min(30 * (1 << min(_failures++, 4)), 300);
          _retry = Timer(Duration(seconds: wait), () {
            if (_owner != null) _load();
          });
        },
        onAdOpened: (_) => AdsService.instance.suppressNextAppOpen(),
      ),
      nativeTemplateStyle: style,
    );
    _ad = ad;
    ad.load();
  }

  void _discard() {
    _countTimer?.cancel();
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    _displays = 0;
  }

  /// Counts one display once the owner has really been in view (and the app in the foreground) for a second.
  void _armCount() {
    _countTimer?.cancel();
    final owner = _owner;
    if (owner == null || !_loaded || _counted) return;
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!identical(_owner, owner) || !_loaded) return t.cancel();
      final state = WidgetsBinding.instance.lifecycleState;
      if ((state == null || state == AppLifecycleState.resumed) &&
          (_onScreen?.call() ?? false)) {
        _displays++;
        _counted = true;
        t.cancel();
      }
    });
  }

  void _onAdsChanged() {
    if (!AdsService.instance.canRequestAds.value) {
      _retry?.cancel();
      _discard();
    }
    notifyListeners();
  }
}
