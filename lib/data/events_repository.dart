import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/native.dart';

class CalendarEvent {
  CalendarEvent.fromMap(Map<dynamic, dynamic> m)
    : id = (m['id'] as num).toInt(),
      title = (m['title'] as String).isEmpty
          ? '(No title)'
          : m['title'] as String,
      start = DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
      end = DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
      allDay = m['allDay'] as bool,
      calendar = m['calendar'] as String,
      color = (m['color'] as num).toInt(),
      location = m['location'] as String;

  final int id;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendar;
  final int color;
  final String location;
}

class EventsRepository extends ChangeNotifier {
  EventsRepository._();
  static final instance = EventsRepository._();

  bool? hasAccess;
  bool loading = false;
  bool loaded = false;
  List<CalendarEvent> past = [];

  Future<bool> checkAccess() async {
    hasAccess = await Permission.calendarFullAccess.isGranted;
    notifyListeners();
    return hasAccess!;
  }

  Future<bool> requestAccess() async {
    final s = await Permission.calendarFullAccess.request();
    hasAccess = s.isGranted;
    notifyListeners();
    if (hasAccess!) await load();
    return hasAccess!;
  }

  Future<void> load() async {
    if (!await checkAccess()) return;
    loading = true;
    notifyListeners();
    try {
      past = (await Native.queryPastEvents())
          .map(CalendarEvent.fromMap)
          .toList();
      loaded = true;
    } catch (e) {
      debugPrint('events load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<int> delete(List<CalendarEvent> events) async {
    final n = await Native.deleteEvents(events.map((e) => e.id).toList());
    final ids = events.map((e) => e.id).toSet();
    past.removeWhere((e) => ids.contains(e.id));
    notifyListeners();
    return n;
  }
}
