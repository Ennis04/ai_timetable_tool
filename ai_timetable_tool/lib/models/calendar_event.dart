import 'package:hive/hive.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final int colorValue;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.colorValue = 0xFF007AFF,
  });

  CalendarEvent copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    String? location,
    int? colorValue,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      location: location ?? this.location,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}

class CalendarEventAdapter extends TypeAdapter<CalendarEvent> {
  @override
  final int typeId = 1;

  @override
  CalendarEvent read(BinaryReader reader) {
    final fields = Map<int, dynamic>.fromIterables(
      List<int>.generate(reader.readByte(), (_) => reader.readByte()),
      List<dynamic>.generate(reader.readByte(), (_) => reader.read()),
    );

    // Fallback-safe reads
    return CalendarEvent(
      id: (fields[0] as String?) ?? '',
      title: (fields[1] as String?) ?? 'Untitled',
      start: (fields[2] as DateTime?) ?? DateTime.now(),
      end: (fields[3] as DateTime?) ?? DateTime.now().add(const Duration(hours: 1)),
      location: (fields[4] as String?) ?? '',
      colorValue: (fields[5] as int?) ?? 0xFF007AFF,
    );
  }

  @override
  void write(BinaryWriter writer, CalendarEvent obj) {
    writer
      ..writeByte(6) // number of fields
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.start)
      ..writeByte(3)
      ..write(obj.end)
      ..writeByte(4)
      ..write(obj.location)
      ..writeByte(5)
      ..write(obj.colorValue);
  }
}
