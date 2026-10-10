import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ads/ads_service.dart';
import '../core/settings.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1900)),
      AdsService.instance.init(),
    ]);
    // No app-open ad on the very first launch (before onboarding).
    if (AppSettings.instance.onboardingDone) {
      await AdsService.instance.showAppOpenOnLaunch(
        wait: const Duration(seconds: 3),
      );
    }
    _next();
  }

  void _next() {
    if (!mounted) return;
    final target = AppSettings.instance.onboardingDone
        ? const HomeScreen()
        : const OnboardingScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => target,
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Palette.forest,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillStack(
                  width: 150,
                  progress: _c.value,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Palette.moss.withValues(alpha: _c.value),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 32),
                Opacity(
                  opacity: Curves.easeIn.transform(
                    ((_c.value - 0.6) / 0.4).clamp(0, 1),
                  ),
                  child: Text(
                    appName,
                    style: font(30, FontWeight.w700, color: Palette.cream),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
