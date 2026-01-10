import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../models/calendar_event.dart';
import '../storage/event_store.dart';
import '../widgets/event_tile.dart';
import 'event_editor.dart';
import 'voice_dialog.dart';

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

  // --- NEW: This handles the Menu Selection ---
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Manual Entry'),
                subtitle: const Text('Type details yourself'),
                onTap: () {
                  Navigator.pop(context); // Close the menu
                  _addEventManually(); // Run original logic
                },
              ),
              ListTile(
                leading: const Icon(Icons.mic_rounded),
                title: const Text('Voice to Event'),
                subtitle: const Text('Use AI to parse speech'),
                onTap: () async {
                  Navigator.pop(context); // Close the menu

                  // 1. Show the voice dialog and wait for result
                  final result = await showModalBottomSheet<CalendarEvent>(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => const VoiceEntryDialog(),
                  );

                  // 2. If we got an event back, open the editor for verification
                  if (result != null) {
                    // We use _editEvent because it handles the UI navigation and saving
                    _editEvent(result);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_a_photo_rounded),
                title: const Text('Scan Image'),
                subtitle: const Text('Upload or snap a schedule'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Image AI coming soon!')),
                  );
                  // TODO: Trigger Image Logic here later
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- RENAMED: This is the original logic ---
  Future<void> _addEventManually() async {
    final created = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(builder: (_) => EventEditorScreen(initialDay: _selectedDay)),
    );
    if (created == null) return;
    await store.upsert(created);
    await _loadDay(_selectedDay);
  }

  Future<void> _editEvent(CalendarEvent e) async {
    final updated = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(builder: (_) => EventEditorScreen(initialDay: _selectedDay, existing: e)),
    );
    if (updated == null) return;
    await store.upsert(updated);
    await _loadDay(_selectedDay);
  }

  Future<void> _deleteEvent(CalendarEvent e) async {
    await store.delete(e.id);
    await _loadDay(_selectedDay);
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
      ),
      // UPDATED: Now calls _showAddOptions
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
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
          Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          if (_dayEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No events. Tap + to add one.', style: TextStyle(color: Colors.grey)),
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
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  secondaryBackground: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
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
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _deleteEvent(e),
                  child: EventTile(event: e, onTap: () => _editEvent(e)),
                ),
              );
            }),
        ],
      ),
    );
  }
}