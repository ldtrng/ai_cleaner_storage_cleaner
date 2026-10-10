import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaRecovery { trash, delete }

/// User preferences persisted in SharedPreferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static late final AppSettings instance;

  static Future<void> init() async {
    instance = AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  SharedPreferences get prefs => _prefs;

  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
  set themeMode(ThemeMode v) {
    _prefs.setInt('themeMode', v.index);
    notifyListeners();
  }

  MediaRecovery get mediaRecovery =>
      MediaRecovery.values[_prefs.getInt('mediaRecovery') ??
          MediaRecovery.trash.index];
  set mediaRecovery(MediaRecovery v) {
    _prefs.setInt('mediaRecovery', v.index);
    notifyListeners();
  }

  bool get onboardingDone => _prefs.getBool('onboardingDone') ?? false;
  set onboardingDone(bool v) {
    _prefs.setBool('onboardingDone', v);
    notifyListeners();
  }

  int get totalCleanedBytes => _prefs.getInt('totalCleanedBytes') ?? 0;
  void addCleanedBytes(int bytes) {
    _prefs.setInt('totalCleanedBytes', totalCleanedBytes + bytes);
    notifyListeners();
  }
}
