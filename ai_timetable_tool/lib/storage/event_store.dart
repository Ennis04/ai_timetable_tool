import 'package:hive/hive.dart';
import '../models/calendar_event.dart';

class EventStore {
  static const String _boxName = 'eventsBox';

  Future<Box<CalendarEvent>> _box() async {
    return await Hive.openBox<CalendarEvent>(_boxName);
  }

  Future<void> upsert(CalendarEvent event) async {
    final box = await _box();
    await box.put(event.id, event);
  }

  Future<void> delete(String id) async {
    final box = await _box();
    await box.delete(id);
  }

  Future<List<CalendarEvent>> all() async {
    final box = await _box();
    return box.values.toList();
  }

  Future<List<CalendarEvent>> byDay(DateTime day) async {
    final box = await _box();

    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final events = box.values.where((e) {
      // event overlaps with day
      return e.start.isBefore(endOfDay) && e.end.isAfter(startOfDay);
    }).toList();

    // sort by start time
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  /// Syncs Google events into the local store, avoiding duplicates by googleId.
  Future<void> syncGoogleEvents(List<CalendarEvent> incoming) async {
    final box = await _box();
    final allEvents = box.values.toList();

    for (final incomingEvent in incoming) {
      if (incomingEvent.googleId == null) continue;

      // Find existing event with same googleId
      final existingIndex = allEvents.indexWhere(
        (e) => e.googleId == incomingEvent.googleId,
      );

      if (existingIndex != -1) {
        // Update existing (preserving the same local id if we want, or just overwriting)
        final existing = allEvents[existingIndex];
        await box.put(existing.id, incomingEvent.copyWith());
      } else {
        // Add new
        await box.put(incomingEvent.id, incomingEvent);
      }
    }
  }
}
