import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/settings.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

const appName = 'AI Cleaner';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const CleanerApp());
}

class CleanerApp extends StatelessWidget {
  const CleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppSettings.instance.themeMode,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Colors.transparent,
                    ),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
