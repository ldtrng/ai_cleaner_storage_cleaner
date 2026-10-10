import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

import '../ads/ad_widgets.dart';
import '../ads/ads_service.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({
    super.key,
    required this.title,
    required this.deleted,
    this.freedBytes,
    this.freedLabel,
    this.firstLabel = 'Deleted',
    this.note,
  });

  final String title;
  final String deleted;
  final String firstLabel;
  final int? freedBytes;
  final String? freedLabel;
  final String? note;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    _maybeAskReview();
  }

  // Ask for a store review after the 3rd successful clean, once.
  Future<void> _maybeAskReview() async {
    final prefs = AppSettings.instance.prefs;
    final n = (prefs.getInt('successCount') ?? 0) + 1;
    await prefs.setInt('successCount', n);
    if (n == 3 && !(prefs.getBool('reviewAsked') ?? false)) {
      await prefs.setBool('reviewAsked', true);
      await Future.delayed(const Duration(seconds: 2));
      final review = InAppReview.instance;
      if (await review.isAvailable()) review.requestReview();
    }
  }

  bool _closing = false;

  // Natural break: the clean is finished, so an interstitial may show (rate-limited in AdsService).
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final n = AppSettings.instance.prefs.getInt('successCount') ?? 0;
    await AdsService.instance.maybeShowInterstitial(successCount: n);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final freed =
        widget.freedLabel ??
        (widget.freedBytes != null ? formatBytes(widget.freedBytes!) : null);
    return GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 16),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 1200),
                            builder: (context, v, _) => PillStack(
                              width: 170,
                              progress: v,
                              child: Transform.scale(
                                scale: Curves.elasticOut.transform(
                                  ((v - 0.7) / 0.3).clamp(0, 1),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 36,
                                  color: Palette.moss,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Congratulations!',
                            style: context.text.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            style: context.text.titleMedium?.copyWith(
                              color: context.tokens.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: _Stat(
                                  label: widget.firstLabel,
                                  value: widget.deleted,
                                ),
                              ),
                              if (freed != null) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _Stat(label: 'Freed up', value: freed),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Native ad sits well above the primary button, separated by the note, to avoid accidental taps.
              const NativeAdCard(small: true),
              const SizedBox(height: 20),
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    widget.note!,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall,
                  ),
                ),
              FilledButton(onPressed: _close, child: const Text('Great!')),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
