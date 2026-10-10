import 'package:flutter/foundation.dart';

import '../core/native.dart';

class InstalledApp {
  InstalledApp.fromMap(Map<dynamic, dynamic> m)
    : package = m['package'] as String,
      name = m['name'] as String,
      installTime = (m['installTime'] as num).toInt(),
      lastUsed = (m['lastUsed'] as num).toInt(),
      size = (m['size'] as num).toInt(),
      icon = m['icon'] as Uint8List?;

  final String package;
  final String name;
  final int installTime;
  final int lastUsed;

  /// -1 when usage access is not granted.
  final int size;
  final Uint8List? icon;
}

class AppsRepository extends ChangeNotifier {
  AppsRepository._();
  static final instance = AppsRepository._();

  bool usageAccess = false;
  bool loading = false;
  bool loaded = false;
  List<InstalledApp> apps = [];

  int get totalSize => apps.fold(0, (a, e) => a + (e.size > 0 ? e.size : 0));

  /// Apps unused for 30+ days (or never), the default cleanup candidates.
  List<InstalledApp> get unused {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    return apps.where((a) => a.lastUsed < cutoff).toList();
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      usageAccess = await Native.hasUsageAccess();
      apps = (await Native.listApps()).map(InstalledApp.fromMap).toList()
        ..sort((a, b) => b.size.compareTo(a.size));
      loaded = true;
    } catch (e) {
      debugPrint('apps load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  void removeLocal(Set<String> packages) {
    apps.removeWhere((a) => packages.contains(a.package));
    notifyListeners();
  }
}
