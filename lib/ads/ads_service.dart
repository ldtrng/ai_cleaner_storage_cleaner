import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit IDs. Debug/profile builds always use Google's test units so real ads are never clicked during development.
abstract final class AdIds {
  static const _real = kReleaseMode;

  static const banner = _real
      ? 'ca-app-pub-2822978318382771/7345516786'
      : 'ca-app-pub-3940256099942544/9214589741';
  static const interstitial = _real
      ? 'ca-app-pub-2822978318382771/7961603610'
      : 'ca-app-pub-3940256099942544/1033173712';
  static const native = _real
      ? 'ca-app-pub-2822978318382771/1567585650'
      : 'ca-app-pub-3940256099942544/2247696110';
  static const appOpen = _real
      ? 'ca-app-pub-2822978318382771/1901618416'
      : 'ca-app-pub-3940256099942544/9257395921';
}

/// Owns consent, SDK init and the full-screen ad formats.
///
/// Frequency rules:
/// - Interstitial: only after a finished clean (Success screen → "Great!"), at most once per 3 minutes,
///   never on the user's first successful clean.
/// - App open: on cold start (not the first launch) and when returning after ≥4 min in background;
///   suppressed when the app was left for a system dialog/settings, and never within 60 s of another full-screen ad.
class AdsService with WidgetsBindingObserver {
  AdsService._();
  static final instance = AdsService._();

  static const _interstitialCooldown = Duration(minutes: 3);
  static const _appOpenBackgroundThreshold = Duration(minutes: 4);
  static const _fullScreenGap = Duration(seconds: 60);
  static const _appOpenMaxAge = Duration(hours: 4);

  final canRequestAds = ValueNotifier<bool>(false);
  bool _initialized = false;
  bool privacyOptionsRequired = false;

  InterstitialAd? _interstitial;
  AppOpenAd? _appOpen;
  DateTime? _appOpenLoadedAt;
  bool _loadingInterstitial = false;
  bool _loadingAppOpen = false;
  bool _showingFullScreen = false;
  DateTime _lastFullScreen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _backgroundedAt;
  bool _suppressNextResume = false;

  /// Gathers consent (UMP), then initializes the SDK. Never throws.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('consent form: ${error.message}');
        });
        await _afterConsent();
        if (!done.isCompleted) done.complete();
      },
      (error) async {
        debugPrint('consent update failed: ${error.message}');
        await _afterConsent();
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  Future<void> _afterConsent() async {
    try {
      privacyOptionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!await ConsentInformation.instance.canRequestAds()) return;
      if (!_initialized) {
        _initialized = true;
        await MobileAds.instance.initialize();
      }
      canRequestAds.value = true;
      _loadInterstitial();
      _loadAppOpen();
    } catch (e) {
      debugPrint('ads init failed: $e');
    }
  }

  /// Re-opens the consent form from Settings (required for EEA/UK users).
  Future<void> showPrivacyOptions() async {
    suppressNextAppOpen();
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('privacy options: ${error.message}');
    });
    await _afterConsent();
  }

  /// Call before sending the user out of the app (system dialogs, settings, share sheet, uninstall…)
  /// so coming back doesn't trigger an app-open ad.
  void suppressNextAppOpen() => _suppressNextResume = true;

  // ---------------------------------------------------------------- interstitial

  void _loadInterstitial() {
    if (!canRequestAds.value || _interstitial != null || _loadingInterstitial) {
      return;
    }
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingInterstitial = false;
          debugPrint('interstitial failed: ${e.message}');
        },
      ),
    );
  }

  /// Shows an interstitial at a natural break if the frequency rules allow. Resolves when it's dismissed.
  Future<void> maybeShowInterstitial({required int successCount}) async {
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    if (successCount < 2 || _showingFullScreen) return;
    if (DateTime.now().difference(_lastFullScreen) < _interstitialCooldown) {
      return;
    }
    _interstitial = null;
    await _show(ad, onDone: _loadInterstitial);
  }

  // ---------------------------------------------------------------- app open

  void _loadAppOpen() {
    if (!canRequestAds.value || _loadingAppOpen) return;
    if (_appOpen != null &&
        DateTime.now().difference(_appOpenLoadedAt!) < _appOpenMaxAge) {
      return;
    }
    _appOpen?.dispose();
    _appOpen = null;
    _loadingAppOpen = true;
    AppOpenAd.load(
      adUnitId: AdIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingAppOpen = false;
          _appOpen = ad;
          _appOpenLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (e) {
          _loadingAppOpen = false;
          debugPrint('app open failed: ${e.message}');
        },
      ),
    );
  }

  /// Cold-start app open ad, waits up to [wait] for it to load.
  Future<void> showAppOpenOnLaunch({
    Duration wait = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(wait);
    while (_appOpen == null &&
        canRequestAds.value &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
    await _showAppOpen();
  }

  Future<void> _showAppOpen() async {
    final ad = _appOpen;
    if (ad == null || _showingFullScreen) {
      _loadAppOpen();
      return;
    }
    if (DateTime.now().difference(_appOpenLoadedAt!) > _appOpenMaxAge) {
      _loadAppOpen();
      return;
    }
    if (DateTime.now().difference(_lastFullScreen) < _fullScreenGap) return;
    _appOpen = null;
    await _show(ad, onDone: _loadAppOpen);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      final suppressed = _suppressNextResume || _showingFullScreen;
      _suppressNextResume = false;
      if (!suppressed && away >= _appOpenBackgroundThreshold) _showAppOpen();
    }
  }

  // ---------------------------------------------------------------- shared

  Future<void> _show(AdWithoutView ad, {required VoidCallback onDone}) {
    final done = Completer<void>();
    void finish(Ad a) {
      _showingFullScreen = false;
      _lastFullScreen = DateTime.now();
      a.dispose();
      onDone();
      if (!done.isCompleted) done.complete();
    }

    final callback = FullScreenContentCallback<Ad>(
      onAdShowedFullScreenContent: (_) => _showingFullScreen = true,
      onAdDismissedFullScreenContent: finish,
      onAdFailedToShowFullScreenContent: (a, e) => finish(a),
    );
    _showingFullScreen = true;
    if (ad is InterstitialAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdShowedFullScreenContent: callback.onAdShowedFullScreenContent,
        onAdDismissedFullScreenContent: callback.onAdDismissedFullScreenContent,
        onAdFailedToShowFullScreenContent:
            callback.onAdFailedToShowFullScreenContent,
      );
      ad.show();
    } else if (ad is AppOpenAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
        onAdShowedFullScreenContent: callback.onAdShowedFullScreenContent,
        onAdDismissedFullScreenContent: callback.onAdDismissedFullScreenContent,
        onAdFailedToShowFullScreenContent:
            callback.onAdFailedToShowFullScreenContent,
      );
      ad.show();
    }
    return done.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => _showingFullScreen = false,
    );
  }
}
