import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/calendar_event.dart';
import '../storage/event_store.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = false;

  // Chat history
  final List<_ChatItem> _chat = [];

  // Parsed actions (preview)
  List<_AiCreateAction> _preview = [];

  // For debugging / fallback
  String _rawJson = '';

  // Quick prompts
  final List<String> _suggestions = const [
    'Add AI lecture tomorrow 10am–12pm at DK1',
    'Add Gym every weekday 6pm–7pm for 4 weeks',
    'Add Study session Saturday 2pm–4pm at Library',
    'Add Meeting next Monday 9am–10am at Online',
  ];

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _preview = [];
      _rawJson = '';
      _chat.add(_ChatItem.user(text));
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse("http://10.0.2.2:8000/ai/parse"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": text}),
      );

      setState(() {
        _rawJson = response.body;
      });

      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _chat.add(_ChatItem.assistant(
            "I couldn't process that. Backend error:\n${response.body}",
            isError: true,
          ));
        });
        _scrollToBottom();
        return;
      }

      final decoded = jsonDecode(response.body);
      final actions = decoded['actions'];

      if (actions is! List) {
        throw Exception("Invalid response: actions is not a list");
      }

      final parsed = <_AiCreateAction>[];
      for (final a in actions) {
        if (a is! Map) continue;
        if (a['type'] != 'create') continue;
        parsed.add(_AiCreateAction.fromJson(Map<String, dynamic>.from(a)));
      }

      setState(() {
        _loading = false;
        _preview = parsed;

        if (parsed.isEmpty) {
          _chat.add(_ChatItem.assistant(
            "I understood your message, but I couldn't find any event to create. Try including a date/time.",
            isError: true,
          ));
        } else {
          _chat.add(_ChatItem.assistant(
            "I found ${_preview.length} event(s). Review below, then tap Apply.",
          ));
        }
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _loading = false;
        _chat.add(_ChatItem.assistant(
          "Request failed: $e",
          isError: true,
        ));
      });
      _scrollToBottom();
    }
  }

  Future<void> _apply() async {
    if (_preview.isEmpty) return;

    final store = EventStore();
    final eventsToAdd = <CalendarEvent>[];

    for (final a in _preview) {
      final repeat = a.repeat;
      final count = a.count;

      for (int i = 0; i < count; i++) {
        final start = _shiftDate(a.start, repeat, i);
        final end = _shiftDate(a.end, repeat, i);

        eventsToAdd.add(CalendarEvent(
          id: "${DateTime.now().microsecondsSinceEpoch}_$i",
          title: a.title,
          start: start,
          end: end,
          location: a.location,
          // You can change this later to a theme color or “AI tag” color
          colorValue: 0xFF007AFF,
        ));
      }
    }

    final conflicts = await _findConflicts(store, eventsToAdd);

    if (conflicts.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Schedule conflict"),
          content: Text(
            "Some events overlap existing ones.\n\n"
            "Example:\n${conflicts.first}\n\n"
            "Apply anyway?",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Apply")),
          ],
        ),
      );
      if (ok != true) return;
    }

    for (final e in eventsToAdd) {
      await store.upsert(e);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Added ${eventsToAdd.length} event(s)")),
    );

    Navigator.pop(context, true);
  }

  DateTime _shiftDate(DateTime dt, String repeat, int i) {
    if (i == 0) return dt;
    if (repeat == 'daily') return dt.add(Duration(days: i));
    if (repeat == 'weekly') return dt.add(Duration(days: 7 * i));
    return dt;
  }

  Future<List<String>> _findConflicts(EventStore store, List<CalendarEvent> toAdd) async {
    final conflicts = <String>[];

    for (final e in toAdd) {
      final sameDayExisting = await store.byDay(e.start);
      for (final ex in sameDayExisting) {
        if (_overlaps(e.start, e.end, ex.start, ex.end)) {
          conflicts.add(
            '${e.title} (${_fmt(e.start)}–${_fmt(e.end)}) overlaps ${ex.title} (${_fmt(ex.start)}–${_fmt(ex.end)})',
          );
          if (conflicts.length >= 3) return conflicts;
        }
      }
    }

    return conflicts;
  }

  bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  String _fmt(DateTime dt) => DateFormat('MMM d, HH:mm').format(dt);

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: const Text("AI Assistant"),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          if (_preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text("Apply"),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Suggestions chips (only show when chat is empty)
            if (_chat.isEmpty) _SuggestionBar(
              suggestions: _suggestions,
              onTap: (s) {
                _controller.text = s;
                _send();
              },
            ),

            // Chat + Preview
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (_chat.isEmpty)
                    _IntroCard(
                      onExampleTap: (s) {
                        _controller.text = s;
                        _send();
                      },
                    ),

                  ..._chat.map((m) => _ChatBubble(item: m)).toList(),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: _TypingIndicator(),
                    ),

                  if (_preview.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _SectionHeader(
                      title: "Preview",
                      subtitle: "${_preview.length} event(s)",
                    ),
                    const SizedBox(height: 10),
                    ..._preview.map((a) => _PreviewCard(action: a)).toList(),
                    const SizedBox(height: 90), // space for composer
                  ],

                  // If no preview, still leave space for composer
                  if (_preview.isEmpty) const SizedBox(height: 90),
                ],
              ),
            ),

            // Composer
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + (bottomInset > 0 ? 0 : 0)),
              child: _Composer(
                controller: _controller,
                loading: _loading,
                onSend: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- UI helpers ----------------

class _IntroCard extends StatelessWidget {
  final void Function(String) onExampleTap;
  const _IntroCard({required this.onExampleTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tell me your schedule in natural language.",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            "I’ll convert it into calendar events for you.",
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ExamplePill(text: "Add AI lecture tomorrow 10–12 DK1", onTap: onExampleTap),
              _ExamplePill(text: "Every Monday 8–10am for 12 weeks", onTap: onExampleTap),
              _ExamplePill(text: "Study Sat 2–4pm Library", onTap: onExampleTap),
            ],
          )
        ],
      ),
    );
  }
}

class _ExamplePill extends StatelessWidget {
  final String text;
  final void Function(String) onTap;
  const _ExamplePill({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(text),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;

  const _SuggestionBar({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => InkWell(
          onTap: () => onTap(suggestions[i]),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14),
                const SizedBox(width: 6),
                Text(
                  suggestions[i],
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final _AiCreateAction action;
  const _PreviewCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, d MMM • HH:mm');
    final start = fmt.format(action.start);
    final endTime = DateFormat('HH:mm').format(action.end);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 6),
            color: Color(0x0A000000),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text("$start – $endTime", style: const TextStyle(color: Colors.black54)),
                if (action.location.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(action.location, style: const TextStyle(color: Colors.black54)),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(label: "Repeat: ${action.repeat}"),
                    _Tag(label: "Count: ${action.count}"),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text("Thinking…"),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.loading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 8),
            color: Color(0x0A000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => loading ? null : onSend(),
              decoration: const InputDecoration(
                hintText: "Type a schedule…",
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: loading ? null : onSend,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatItem item;
  const _ChatBubble({required this.item});

  @override
  Widget build(BuildContext context) {
    final isUser = item.role == _Role.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF007AFF)
              : (item.isError ? const Color(0xFFFFEAEA) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isUser ? Colors.transparent : Colors.black12),
          boxShadow: isUser
              ? const []
              : const [
                  BoxShadow(
                    blurRadius: 10,
                    offset: Offset(0, 6),
                    color: Color(0x08000000),
                  ),
                ],
        ),
        child: Text(
          item.text,
          style: TextStyle(
            color: isUser ? Colors.white : (item.isError ? Colors.red.shade700 : Colors.black87),
          ),
        ),
      ),
    );
  }
}

// ---------------- Data helpers ----------------

enum _Role { user, assistant }

class _ChatItem {
  final _Role role;
  final String text;
  final bool isError;

  _ChatItem(this.role, this.text, {this.isError = false});

  factory _ChatItem.user(String text) => _ChatItem(_Role.user, text);
  factory _ChatItem.assistant(String text, {bool isError = false}) =>
      _ChatItem(_Role.assistant, text, isError: isError);
}

// ----- helper class for AI actions -----

class _AiCreateAction {
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String repeat; // none|daily|weekly
  final int count;

  _AiCreateAction({
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.repeat,
    required this.count,
  });

  factory _AiCreateAction.fromJson(Map<String, dynamic> a) {
    final title = (a['title'] ?? 'Untitled').toString();
    final location = (a['location'] ?? '').toString();
    final repeat = (a['repeat'] ?? 'none').toString();

    int count = 1;
    final rawCount = a['count'];
    if (rawCount is int) count = rawCount;
    if (rawCount is String) count = int.tryParse(rawCount) ?? 1;
    if (count < 1) count = 1;
    if (count > 60) count = 60;

    final start = DateTime.parse((a['start'] ?? '').toString());
    final end = DateTime.parse((a['end'] ?? '').toString());

    return _AiCreateAction(
      title: title,
      start: start,
      end: end,
      location: location,
      repeat: repeat,
      count: count,
    );
  }
}
