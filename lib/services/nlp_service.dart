import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/calendar_event.dart';

class NLPService {
  
  // --- NEW: Helper to convert "five" -> "5", "first" -> "1" ---
  static String _normalizeText(String input) {
    String text = input.toLowerCase();
    
    const numberMap = {
      'one': '1', 'first': '1',
      'two': '2', 'second': '2',
      'three': '3', 'third': '3',
      'four': '4', 'fourth': '4',
      'five': '5', 'fifth': '5',
      'six': '6', 'sixth': '6',
      'seven': '7', 'seventh': '7',
      'eight': '8', 'eighth': '8',
      'nine': '9', 'ninth': '9',
      'ten': '10', 'tenth': '10',
      'eleven': '11', 'eleventh': '11',
      'twelve': '12', 'twelfth': '12',
      'thirteen': '13', 'thirteenth': '13',
      'fourteen': '14', 'fourteenth': '14',
      'fifteen': '15', 'fifteenth': '15',
      'sixteen': '16', 'sixteenth': '16',
      'seventeen': '17', 'seventeenth': '17',
      'eighteen': '18', 'eighteenth': '18',
      'nineteen': '19', 'nineteenth': '19',
      'twenty': '20', 'twentieth': '20',
      'thirty': '30', 'thirtieth': '30',
    };

    // 1. Replace simple words
    numberMap.forEach((word, digit) {
      // \b ensures we match "one" but not "bone" or "phone"
      text = text.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
    });

    // 2. Handle composite numbers (like "twenty one" -> "21")
    // We check this AFTER simple replacements. e.g. "twenty one" became "20 1"
    // So we look for "20 1", "20 2", etc.
    final compositeMap = {
      '20 1': '21', '20 2': '22', '20 3': '23', '20 4': '24', '20 5': '25',
      '20 6': '26', '20 7': '27', '20 8': '28', '20 9': '29',
      '30 1': '31'
    };

    compositeMap.forEach((pattern, digit) {
      text = text.replaceAll(pattern, digit);
    });

    return text;
  }

  static CalendarEvent parse(String rawText) {
    // STEP 1: Normalize the text (convert words to digits)
    final String lower = _normalizeText(rawText);
    
    final now = DateTime.now();

    // --- 2. DETECT DATE ---
    DateTime date = DateTime(now.year, now.month, now.day);
    bool dateFound = false;

    // Map for months
    final monthMap = {
      'jan': 1, 'ja': 1, 'feb': 2, 'fe': 2, 'mar': 3, 'ma': 3,
      'apr': 4, 'ap': 4, 'may': 5, 'jun': 6, 'jul': 7,
      'aug': 8, 'au': 8, 'sep': 9, 'se': 9, 'oct': 10, 'oc': 10,
      'nov': 11, 'no': 11, 'dec': 12, 'de': 12
    };

    // Regex now works perfectly because "five" is already "5"
    // Pattern 1: "5 February"
    final dayMonthRegex = RegExp(r'(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*');
    // Pattern 2: "February 5"
    final monthDayRegex = RegExp(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?');

    Match? dmMatch = dayMonthRegex.firstMatch(lower);
    Match? mdMatch = monthDayRegex.firstMatch(lower);

    if (dmMatch != null) {
      int day = int.parse(dmMatch.group(1)!);
      String monthStr = dmMatch.group(2)!;
      int month = monthMap[monthStr] ?? 1;
      
      int year = now.year;
      if (month < now.month || (month == now.month && day < now.day)) {
        year++; 
      }
      date = DateTime(year, month, day);
      dateFound = true;
    } else if (mdMatch != null) {
      String monthStr = mdMatch.group(1)!;
      int day = int.parse(mdMatch.group(2)!);
      int month = monthMap[monthStr] ?? 1;
      
      int year = now.year;
      if (month < now.month || (month == now.month && day < now.day)) {
        year++;
      }
      date = DateTime(year, month, day);
      dateFound = true;
    }

    if (!dateFound) {
      if (lower.contains('tomorrow')) {
        date = date.add(const Duration(days: 1));
      } else if (lower.contains('next week')) {
        date = date.add(const Duration(days: 7));
      }
    }

    // --- 3. DETECT TIME ---
    TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
    bool timeFound = false;

    // Pattern for "1 pm", "1 30 pm" (since normalization might strip colon or separate digits)
    // We allow optional colon or space between hour and minute
    final timeRegex = RegExp(r'(\d{1,2})[:\s]?(\d{2})?\s?(am|pm)|(\d{1,2}):(\d{2})');
    final timeMatch = timeRegex.firstMatch(lower);

    if (timeMatch != null) {
      // Group 1-3: AM/PM format
      if (timeMatch.group(3) != null) {
        int h = int.parse(timeMatch.group(1)!);
        int m = timeMatch.group(2) != null ? int.parse(timeMatch.group(2)!) : 0;
        String period = timeMatch.group(3)!;

        if (period == 'pm' && h < 12) h += 12;
        if (period == 'am' && h == 12) h = 0;
        time = TimeOfDay(hour: h, minute: m);
        timeFound = true;
      } 
      // Group 4-5: 24h format (requires colon to distinguish from random numbers)
      else if (timeMatch.group(4) != null) {
        int h = int.parse(timeMatch.group(4)!);
        int m = int.parse(timeMatch.group(5)!);
        time = TimeOfDay(hour: h, minute: m);
        timeFound = true;
      }
    }

    // Fallback context
    if (!timeFound) {
      if (lower.contains('dinner')) time = const TimeOfDay(hour: 19, minute: 0);
      else if (lower.contains('lunch')) time = const TimeOfDay(hour: 12, minute: 30);
      else if (lower.contains('breakfast')) time = const TimeOfDay(hour: 8, minute: 0);
    }

    // --- 4. TITLE CLEANUP ---
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final end = start.add(const Duration(hours: 1));

    String title = rawText; // Use rawText for title to keep original casing/words if preferred
    // ...but usually better to clean the Normalized text so "5" is consistent
    title = lower;

    title = title.replaceAll(dayMonthRegex, '').replaceAll(monthDayRegex, '');
    title = title.replaceAll(timeRegex, '');
    title = title.replaceAll(RegExp(r'tomorrow|today|next week', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\b(at|on|from|with)\b', caseSensitive: false), '');
    title = title.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (title.isEmpty || title.length < 2) {
       if (lower.contains('dinner')) title = 'Dinner';
       else if (lower.contains('lunch')) title = 'Lunch';
       else title = 'New Event';
    } else {
      title = title[0].toUpperCase() + title.substring(1);
    }

    return CalendarEvent(
      id: const Uuid().v4(),
      title: title,
      start: start,
      end: end,
      location: '', 
      colorValue: 0xFF007AFF,
    );
  }
}