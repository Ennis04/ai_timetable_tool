import 'package:hive/hive.dart';
import '../models/calendar_event.dart';

class EventStore {
  static const _boxName = 'calendar_events';

  Future<Box<CalendarEvent>> _box() async {
    return Hive.openBox<CalendarEvent>(_boxName);
  }

  Future<List<CalendarEvent>> all() async {
    final box = await _box();
    return box.values.toList();
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
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    final list = box.values.where((e) {
      return e.start.isBefore(end) && e.end.isAfter(start);
    }).toList();

    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }
}
