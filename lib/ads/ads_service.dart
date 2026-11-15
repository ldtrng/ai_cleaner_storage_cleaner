import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/firebase.dart';
import '../core/settings.dart';

/// Ad unit IDs. Debug/profile builds always use Google's test units so real ads are never clicked during development.
abstract final class AdIds {
  static const _real = kReleaseMode;

  static const banner = _real
      ? 'ca-app-pub-5764729052591112/5663317725'
      : 'ca-app-pub-3940256099942544/9214589741';
  static const interstitial = _real
      ? 'ca-app-pub-5764729052591112/7559028339'
      : 'ca-app-pub-3940256099942544/1033173712';
  static const native = _real
      ? 'ca-app-pub-5764729052591112/3619783328'
      : 'ca-app-pub-3940256099942544/2247696110';
  static const appOpen = _real
      ? 'ca-app-pub-5764729052591112/1017670719'
      : 'ca-app-pub-3940256099942544/9257395921';
}

/// Owns consent, SDK init and the full-screen ad formats.
///
/// Frequency rules:
/// - Interstitial: only after a finished clean (Success screen → "Great!"), on the 1st successful clean and then
///   every 3rd one (`interstitial_every`: 1st, 4th, 7th…), no time-based gap.
/// - App open: on cold start and on every return from the background, but never during the first session after
///   install; suppressed when the app was left for a system dialog/settings. Closing a full-screen ad of ours
///   (interstitial or app open) is not a return from the background.
class AdsService with WidgetsBindingObserver {
  AdsService._();
  static final instance = AdsService._();

  // Tunable from Firebase Remote Config (defaults in Config.defaults).
  static bool get _interstitialOn =>
      Config.adsEnabled && Config.flag('interstitial_enabled');
  static bool get _appOpenOn =>
      Config.adsEnabled && Config.flag('app_open_enabled');
  static const _appOpenMaxAge = Duration(hours: 4);

  final canRequestAds = ValueNotifier<bool>(false);

  /// True once the user is past splash/onboarding and the cold-start app open ad; the banner stays hidden until then.
  final startupReady = ValueNotifier<bool>(false);

  /// Number of pages currently asking the banner to step aside (see `HideBanner`).
  final bannerHolds = ValueNotifier<int>(0);
  bool _initialized = false;
  bool privacyOptionsRequired = false;

  InterstitialAd? _interstitial;
  AppOpenAd? _appOpen;
  DateTime? _appOpenLoadedAt;
  bool _loadingInterstitial = false;
  bool _loadingAppOpen = false;
  bool _showingFullScreen = false;
  DateTime? _backgroundedAt;
  bool _suppressNextResume = false;

  /// True for the whole session in which the app was installed (onboarding not finished at launch):
  /// no app open ad until the next launch.
  bool _firstSession = false;

  /// Gathers consent (UMP), then initializes the SDK. Never throws.
  Future<void> init() async {
    _firstSession = !AppSettings.instance.onboardingDone;
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
    if (!canRequestAds.value ||
        !_interstitialOn ||
        _interstitial != null ||
        _loadingInterstitial) {
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
    // Paced by the number of finished cleans, not by time: the 1st clean, then every Nth after it.
    final every = Config.integer('interstitial_every');
    if (!_interstitialOn ||
        _showingFullScreen ||
        (successCount - 1) % (every < 1 ? 1 : every) != 0) {
      return;
    }
    _interstitial = null;
    await _show(ad, onDone: _loadInterstitial);
  }

  // ---------------------------------------------------------------- app open

  void _loadAppOpen() {
    if (!canRequestAds.value || !_appOpenOn || _loadingAppOpen) return;
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
  Future<void> showAppOpenOnLaunch({Duration? wait}) async {
    if (!_appOpenOn) return;
    wait ??= Duration(
      milliseconds: Config.integer('app_open_cold_start_wait_ms'),
    );
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
    _appOpen = null;
    await _show(ad, onDone: _loadAppOpen);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // A full-screen ad of ours pauses the app too; that is not the user leaving, so closing it is no "return".
      if (_showingFullScreen) return;
      _backgroundedAt ??= DateTime.now();
      // Have one ready for the moment the user comes back.
      if (!_firstSession) _loadAppOpen();
    } else if (state == AppLifecycleState.resumed) {
      // Only a real return from the background (a pause came first).
      final wasPaused = _backgroundedAt != null;
      _backgroundedAt = null;
      final suppressed = _suppressNextResume || _showingFullScreen;
      _suppressNextResume = false;
      if (wasPaused && !suppressed && !_firstSession && _appOpenOn) {
        _showAppOpen();
      }
    }
  }

  // ---------------------------------------------------------------- shared

  Future<void> _show(AdWithoutView ad, {required VoidCallback onDone}) {
    final done = Completer<void>();
    void finish(Ad a) {
      _showingFullScreen = false;
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
