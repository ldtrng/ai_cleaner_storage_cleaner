import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_theme.dart';
import 'ads_service.dart';

/// Anchored adaptive banner. Collapses to nothing until an ad is loaded.
class BannerAdBar extends StatefulWidget {
  const BannerAdBar({super.key});

  @override
  State<BannerAdBar> createState() => _BannerAdBarState();
}

class _BannerAdBarState extends State<BannerAdBar> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void initState() {
    super.initState();
    AdsService.instance.canRequestAds.addListener(_maybeLoad);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    if (!mounted || !AdsService.instance.canRequestAds.value) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (_ad != null && _width == width) return;
    _width = width;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    _ad?.dispose();
    _loaded = false;
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, e) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
        onAdOpened: (_) => AdsService.instance.suppressNextAppOpen(),
      ),
    )..load();
  }

  @override
  void dispose() {
    AdsService.instance.canRequestAds.removeListener(_maybeLoad);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return ColoredBox(
      color: context.tokens.bgBottom,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ),
      ),
    );
  }
}

/// Native ad rendered with Google's template, styled to the palette. Hidden until loaded.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, this.small = false});
  final bool small;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AdsService.instance.canRequestAds.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    if (!mounted || _ad != null || !AdsService.instance.canRequestAds.value) {
      return;
    }
    final dark = context.isDark;
    final fg = dark ? Palette.cream : Palette.forest;
    _ad = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, e) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
        onAdOpened: (_) => AdsService.instance.suppressNextAppOpen(),
      ),
      nativeTemplateStyle: NativeTemplateStyle(
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
      ),
    )..load();
  }

  @override
  void dispose() {
    AdsService.instance.canRequestAds.removeListener(_load);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
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
