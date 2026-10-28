import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/firebase.dart';
import '../theme/app_theme.dart';
import 'ads_service.dart';
import 'native_ad_pool.dart';

/// One anchored adaptive banner under the whole navigator (installed through `MaterialApp.builder`), so every
/// page shows it without per-screen widgets and without a new ad request each time a page opens. Collapses to
/// nothing while no ad is loaded, ads are off or startup isn't finished, and steps aside while the keyboard is open.
class AdBannerHost extends StatefulWidget {
  const AdBannerHost({super.key, required this.child});
  final Widget child;

  @override
  State<AdBannerHost> createState() => _AdBannerHostState();
}

class _AdBannerHostState extends State<AdBannerHost> {
  late final Listenable _gate = Listenable.merge([
    AdsService.instance.canRequestAds,
    AdsService.instance.startupReady,
    AdsService.instance.bannerHolds,
  ]);
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  int? _width;
  int _failures = 0;
  Timer? _retry;

  bool get _enabled =>
      AdsService.instance.canRequestAds.value &&
      Config.adsEnabled &&
      Config.flag('banner_home_enabled');

  @override
  void initState() {
    super.initState();
    _gate.addListener(_onGate);
  }

  void _onGate() {
    if (!mounted) return;
    if (!_enabled) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
    } else {
      _load();
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_enabled) return;
    // Wait out the back-off after a failed request instead of requesting on every rebuild.
    if (_retry?.isActive ?? false) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (_ad != null && _width == width) return;
    _loading = true;
    // ignore: deprecated_member_use
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width,
    );
    _loading = false;
    if (!mounted) return;
    if (size == null) return _scheduleRetry();
    _width = width;
    _loaded = false;
    _ad?.dispose();
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (a) {
          if (!mounted || !identical(a, _ad)) return;
          _failures = 0;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          debugPrint('banner failed: ${e.message}');
          if (!mounted || !identical(a, _ad)) return;
          setState(() {
            _ad = null;
            _loaded = false;
            _width = null;
          });
          _scheduleRetry();
        },
        onAdOpened: (_) => AdsService.instance.suppressNextAppOpen(),
      ),
    );
    _ad = ad;
    ad.load();
  }

  /// 30 s, 1 m, 2 m, 4 m, then every 5 m while the banner stays on screen.
  void _scheduleRetry() {
    _failures++;
    final seconds = min(30 * (1 << min(_failures - 1, 4)), 300);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    _gate.removeListener(_onGate);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final mq = MediaQuery.of(context);
    final shown =
        ad != null &&
        _loaded &&
        _enabled &&
        AdsService.instance.startupReady.value;
    // Steps aside while the keyboard is up or a page asked for it (HideBanner).
    final hidden =
        mq.viewInsets.bottom > 0 || AdsService.instance.bannerHolds.value > 0;
    // The banner takes over the bottom system inset, so pages above it must not pad for it again.
    final inset = mq.padding.bottom;
    final pageMedia = (!shown || hidden)
        ? mq
        : mq.copyWith(
            padding: mq.padding.copyWith(bottom: 0),
            viewPadding: mq.viewPadding.copyWith(bottom: 0),
          );
    // The tree shape never changes, so the navigator keeps its state when the ad appears or goes away.
    return Column(
      children: [
        Expanded(
          child: MediaQuery(data: pageMedia, child: widget.child),
        ),
        if (shown)
          // Kept in the tree (just not laid out) while hidden, so the loaded ad survives
          // and no new request is made.
          Visibility(
            visible: !hidden,
            maintainState: true,
            child: ColoredBox(
              color: context.tokens.bgBottom,
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: inset),
                child: SizedBox(
                  width: double.infinity,
                  height: ad.size.height.toDouble(),
                  child: Center(
                    child: SizedBox(
                      width: ad.size.width.toDouble(),
                      height: ad.size.height.toDouble(),
                      child: AdWidget(ad: ad),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Hides the global banner while [child]'s page is mounted, e.g. where it would sit next to a primary button.
class HideBanner extends StatefulWidget {
  const HideBanner({super.key, required this.child});
  final Widget child;

  @override
  State<HideBanner> createState() => _HideBannerState();
}

class _HideBannerState extends State<HideBanner> {
  final _holds = AdsService.instance.bannerHolds;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    // Not synchronously: the banner host rebuilds on this and the tree is mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _held = true;
      _holds.value++;
    });
  }

  @override
  void dispose() {
    // The tree is locked while disposing, so release in a microtask.
    if (_held) scheduleMicrotask(() => _holds.value--);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Slot for the app's single native ad ([NativeAdPool]), styled to the palette. It claims the ad while its
/// page is the visible one and renders nothing when it can't have it (ad not loaded yet, or another slot owns it).
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, this.small = false});
  final bool small;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  final _pool = NativeAdPool.instance;
  bool _routeVisible = true;
  Size _screen = Size.zero;
  late NativeTemplateStyle _style;
  late Object _styleKey;

  @override
  void initState() {
    super.initState();
    _pool.addListener(_onPool);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context);
    // Pages under another route are built but have their tickers off.
    _routeVisible = TickerMode.valuesOf(context).enabled;
    final dark = context.isDark;
    _styleKey = (widget.small, dark);
    _style = _buildStyle(dark);
    _sync();
  }

  NativeTemplateStyle _buildStyle(bool dark) {
    final fg = dark ? Palette.cream : Palette.forest;
    return NativeTemplateStyle(
      templateType: widget.small ? TemplateType.small : TemplateType.medium,
      mainBackgroundColor: context.tokens.card,
      cornerRadius: 20,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: dark ? Palette.forest : Palette.cream,
        backgroundColor: dark ? Palette.cream : Palette.moss,
        style: NativeTemplateFontStyle.bold,
        size: 15,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: fg,
        style: NativeTemplateFontStyle.bold,
        size: 15,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: context.tokens.textMuted,
        size: 13,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: context.tokens.textMuted,
        size: 13,
      ),
    );
  }

  void _onPool() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  void _sync() {
    if (_routeVisible) {
      _pool.claim(this, _style, _styleKey, _isOnScreen);
    } else {
      _pool.release(this);
    }
  }

  /// At least half of the card is inside the screen.
  bool _isOnScreen() {
    final box = context.findRenderObject();
    if (!mounted ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return false;
    }
    final r = (box.localToGlobal(Offset.zero) & box.size).intersect(
      Offset.zero & _screen,
    );
    return !r.isEmpty && r.height >= box.size.height / 2;
  }

  @override
  void dispose() {
    _pool.removeListener(_onPool);
    _pool.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _pool.adFor(this);
    if (ad == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.small ? 90 : 300,
        maxHeight: widget.small ? 120 : 360,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
