import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/calendar_event.dart';

class EventEditorScreen extends StatefulWidget {
  final DateTime initialDay;
  final CalendarEvent? existing;

  const EventEditorScreen({super.key, required this.initialDay, this.existing});

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  int _color = 0xFF007AFF;

  @override
  void initState() {
    super.initState();
    final day = widget.initialDay;
    final baseStart = DateTime(day.year, day.month, day.day, 9, 0);
    final baseEnd = baseStart.add(const Duration(hours: 1));

    final e = widget.existing;
    _titleCtrl.text = e?.title ?? '';
    _locCtrl.text = e?.location ?? '';
    _start = e?.start ?? baseStart;
    _end = e?.end ?? baseEnd;
    _color = e?.colorValue ?? 0xFF007AFF;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title cannot be empty')));
      return;
    }
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time')));
      return;
    }

    final id = widget.existing?.id ?? const Uuid().v4();
    final event = CalendarEvent(
      id: id,
      title: title,
      start: _start,
      end: _end,
      location: _locCtrl.text.trim(),
      colorValue: _color,
    );

    Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Event' : 'New Event'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locCtrl,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          _DateRow(
            label: 'Starts',
            value: DateFormat('EEE, d MMM • HH:mm').format(_start),
            onTap: () async {
              final picked = await _pickDateTime(_start);
              if (picked == null) return;
              setState(() {
                _start = picked;
                if (!_end.isAfter(_start)) {
                  _end = _start.add(const Duration(hours: 1));
                }
              });
            },
          ),
          const SizedBox(height: 10),
          _DateRow(
            label: 'Ends',
            value: DateFormat('EEE, d MMM • HH:mm').format(_end),
            onTap: () async {
              final picked = await _pickDateTime(_end);
              if (picked == null) return;
              setState(() => _end = picked);
            },
          ),

          const SizedBox(height: 16),
          const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ColorDot(color: 0xFF007AFF, selected: _color == 0xFF007AFF, onTap: () => setState(() => _color = 0xFF007AFF)),
              _ColorDot(color: 0xFF34C759, selected: _color == 0xFF34C759, onTap: () => setState(() => _color = 0xFF34C759)),
              _ColorDot(color: 0xFFFF9500, selected: _color == 0xFFFF9500, onTap: () => setState(() => _color = 0xFFFF9500)),
              _ColorDot(color: 0xFFFF3B30, selected: _color == 0xFFFF3B30, onTap: () => setState(() => _color = 0xFFFF3B30)),
              _ColorDot(color: 0xFFAF52DE, selected: _color == 0xFFAF52DE, onTap: () => setState(() => _color = 0xFFAF52DE)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value)),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final int color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.black : Colors.transparent, width: 2),
        ),
      ),
    );
  }
}
