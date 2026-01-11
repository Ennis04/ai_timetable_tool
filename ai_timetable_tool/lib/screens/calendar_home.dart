import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../models/calendar_event.dart';
import '../storage/event_store.dart';
import '../widgets/event_tile.dart';
import 'event_editor.dart';
import 'ai_assistant_screen.dart';

class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends State<CalendarHomeScreen> {
  final store = EventStore();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<CalendarEvent> _dayEvents = [];

  @override
  void initState() {
    super.initState();
    _loadDay(_selectedDay);
  }

  Future<void> _loadDay(DateTime day) async {
    final events = await store.byDay(day);
    if (!mounted) return;
    setState(() => _dayEvents = events);
  }

  Future<void> _addEvent() async {
    final created = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => EventEditorScreen(initialDay: _selectedDay),
      ),
    );
    if (created == null) return;
    await store.upsert(created);
    await _loadDay(_selectedDay);
  }

  Future<void> _editEvent(CalendarEvent e) async {
    final updated = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventEditorScreen(initialDay: _selectedDay, existing: e),
      ),
    );
    if (updated == null) return;
    await store.upsert(updated);
    await _loadDay(_selectedDay);
  }

  Future<void> _deleteEvent(CalendarEvent e) async {
    await store.delete(e.id);
    await _loadDay(_selectedDay);
  }

  // ✅ NEW: open AI and refresh after Apply
  Future<void> _openAiAssistant() async {
    // We expect a DateTime? (The date of the new event)
    final result = await Navigator.push<DateTime?>(
      context,
      MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
    );

    // If we got a date, jump to it and reload
    if (result != null) {
      setState(() {
        _selectedDay = result;
        _focusedDay = result;
      });
      await _loadDay(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = DateFormat('EEEE, d MMM').format(_selectedDay);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'AIT³',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'AI Assistant',
            onPressed: _openAiAssistant,
            icon: const Icon(Icons.auto_awesome),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: TableCalendar(
              firstDay: DateTime(2020, 1, 1),
              lastDay: DateTime(2035, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
              ),
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selected, focused) async {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
                await _loadDay(selected);
              },
              onPageChanged: (focused) => _focusedDay = focused,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            header,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),

          if (_dayEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No events. Tap + to add one.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ..._dayEvents.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Dismissible(
                  key: ValueKey(e.id),
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete event?'),
                        content: Text('Delete "${e.title}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _deleteEvent(e),
                  child: EventTile(event: e, onTap: () => _editEvent(e)),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }
}
