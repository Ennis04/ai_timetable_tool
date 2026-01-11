import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/calendar_event.dart';

class EventTile extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback? onTap;

  const EventTile({super.key, required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final time =
        '${DateFormat.Hm().format(event.start)} – ${DateFormat.Hm().format(event.end)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color(event.colorValue).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: Color(event.colorValue), width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            if (event.location.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                event.location,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
