import 'package:hive/hive.dart';
import '../models/calendar_event.dart';

class EventStore {
  static const String _boxName = 'eventsBox';

  Future<Box<CalendarEvent>> _box() async {
    return Hive.openBox<CalendarEvent>(_boxName);
  }

  Future<void> upsert(CalendarEvent event) async {
    final box = await _box();
    await box.put(event.id, event);
  }

  Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }

  Future<List<CalendarEvent>> byDay(DateTime day) async {
    final box = await _box();

    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final events = box.values.where((e) {
      return e.start.isBefore(endOfDay) && e.end.isAfter(startOfDay);
    }).toList();

    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  Future<List<CalendarEvent>> upcoming({int days = 7}) async {
    final box = await _box();
    final now = DateTime.now();
    final end = now.add(Duration(days: days));

    final events = box.values.where((e) {
      return e.start.isAfter(now) && e.start.isBefore(end);
    }).toList();

    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  /// Merge Google events into Hive using googleId matching.
  /// Local ID stays stable when updating an existing google event.
  Future<void> syncGoogleEvents(List<CalendarEvent> incoming) async {
    final box = await _box();
    final allEvents = box.values.toList();

    for (final inc in incoming) {
      if (inc.googleId == null) continue;

      final existing = allEvents.firstWhere(
        (e) => e.googleId == inc.googleId,
        orElse: () => CalendarEvent(
          id: '',
          title: '',
          start: DateTime.now(),
          end: DateTime.now(),
          location: '',
          colorValue: 0,
        ),
      );

      if (existing.id.isNotEmpty) {
        // overwrite using the existing local key
        await box.put(existing.id, inc.copyWith());
      } else {
        await box.put(inc.id, inc);
      }
    }
  }
}
