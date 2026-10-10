import 'package:flutter/material.dart';

import '../core/settings.dart';
import '../data/media_repository.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  const _Slide(this.title, this.body, this.icon, this.badge);
  final String title;
  final String body;
  final IconData icon;
  final String badge;
}

const _slides = [
  _Slide(
    'Welcome to $appName',
    'Free up space taken by duplicate, similar and blurry photos — in one tap.',
    Icons.auto_awesome_rounded,
    'Smart Clean',
  ),
  _Slide(
    'Eliminate Duplicates',
    'Merge duplicate contacts and remove look-alike photos and videos.',
    Icons.content_copy_rounded,
    'Duplicates',
  ),
  _Slide(
    'Shrink, don\'t delete',
    'Compress large photos and videos to reclaim storage without losing memories.',
    Icons.compress_rounded,
    'Compress',
  ),
  _Slide(
    'Your Secret Space',
    'Keep private photos, videos and contacts locked behind your PIN or fingerprint.',
    Icons.lock_rounded,
    'Private',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  Future<void> _finish() async {
    AppSettings.instance.onboardingDone = true;
    await MediaRepository.instance.requestPermission();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _SlideView(slide: _slides[i], index: i),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? context.tokens.accent
                          : context.tokens.track,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: FilledButton(
                onPressed: last
                    ? _finish
                    : () => _page.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                      ),
                child: Text(last ? 'Get Started' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.index});
  final _Slide slide;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1100),
                builder: (context, v, _) =>
                    _Illustration(slide: slide, index: index, progress: v),
              ),
            ),
          ),
          Text(
            slide.title,
            style: context.text.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.tokens.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.slide,
    required this.index,
    required this.progress,
  });
  final _Slide slide;
  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) {
    // Rotate the palette so each slide leads with a different colour.
    final colors = [
      for (var i = 0; i < 5; i++) PillStack.colors[(i + index) % 5],
    ];
    return SizedBox(
      width: 280,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 5; i++)
            Transform.rotate(
              angle: (i - 2) * 0.16 * Curves.easeOutBack.transform(progress),
              child: Opacity(
                opacity: progress.clamp(0, 1),
                child: Container(
                  width: 230 - i * 22.0,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(48),
                    boxShadow: [
                      BoxShadow(
                        color: Palette.forest.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Transform.scale(
            scale: Curves.elasticOut.transform(progress),
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Palette.forest,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.cream, width: 5),
              ),
              child: Icon(slide.icon, size: 52, color: Palette.cream),
            ),
          ),
          Positioned(
            bottom: 18,
            child: Opacity(
              opacity: progress,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Palette.forest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  slide.badge,
                  style: font(14, FontWeight.w700, color: Palette.cream),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
