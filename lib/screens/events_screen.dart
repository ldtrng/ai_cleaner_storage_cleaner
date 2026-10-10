import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/native.dart';
import '../data/events_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'success_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final repo = EventsRepository.instance;
  final _sel = <int>{};
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    repo.checkAccess().then((ok) {
      if (ok) repo.load();
    });
  }

  Future<void> _delete() async {
    final list = repo.past.where((e) => _sel.contains(e.id)).toList();
    final ok = await showConfirm(
      context,
      title: 'Allow deleting ${plural(list.length, 'event')}?',
      message: 'Events will be removed from Calendar.',
    );
    if (!ok || !mounted) return;
    final n = await runWithProgress(context, (_) => repo.delete(list));
    _sel.removeAll(list.map((e) => e.id));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuccessScreen(
          title: "You've cleaned your calendar",
          deleted: plural(n, 'event'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (repo.hasAccess == false) {
          return GradientScaffold(
            title: 'Events',
            body: NoAccessView(
              icon: Icons.event_rounded,
              title: 'No access to Calendar',
              message: 'To remove old calendar events, allow access.',
              onAllow: () async {
                if (!await repo.requestAccess()) Native.openAppSettings();
              },
            ),
          );
        }
        if (repo.loaded && !_seeded) {
          _sel.addAll(repo.past.map((e) => e.id));
          _seeded = true;
        }
        // Group by month.
        final groups = <String, List<CalendarEvent>>{};
        for (final e in repo.past) {
          groups.putIfAbsent(formatMonthYear(e.start), () => []).add(e);
        }
        final allOn = repo.past.isNotEmpty && _sel.length == repo.past.length;
        return GradientScaffold(
          title: 'Events',
          body: !repo.loaded
              ? const Center(child: CircularProgressIndicator())
              : repo.past.isEmpty
              ? const EmptyState(icon: Icons.event_available_rounded)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              plural(repo.past.length, 'past event'),
                              style: context.text.bodySmall,
                            ),
                          ),
                        ),
                        SelectAllButton(
                          allSelected: allOn,
                          onChanged: (v) => setState(() {
                            _sel.clear();
                            if (v) _sel.addAll(repo.past.map((e) => e.id));
                          }),
                        ),
                      ],
                    ),
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(entry.key, style: context.text.titleSmall),
                      ),
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final e in entry.value)
                              CheckboxListTile(
                                value: _sel.contains(e.id),
                                onChanged: (v) => setState(
                                  () => v! ? _sel.add(e.id) : _sel.remove(e.id),
                                ),
                                title: Text(
                                  e.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    formatDate(e.start),
                                    if (!e.allDay)
                                      TimeOfDay.fromDateTime(
                                        e.start,
                                      ).format(context),
                                    if (e.calendar.isNotEmpty) e.calendar,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                secondary: Container(
                                  width: 6,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: e.color != 0
                                        ? Color(e.color | 0xFF000000)
                                        : Palette.sage,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
          bottom: repo.past.isEmpty
              ? null
              : BottomAction(
                  label: _sel.isEmpty
                      ? 'Delete'
                      : 'Delete ${plural(_sel.length, 'event')}',
                  icon: Icons.delete_outline_rounded,
                  onPressed: _sel.isEmpty ? null : _delete,
                ),
        );
      },
    );
  }
}
