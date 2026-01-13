import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:image_picker/image_picker.dart';

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

  // --- VOICE VARIABLES ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  // --- IMAGE VARIABLES ---
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  bool _loading = false;

  // Chat history
  final List<_ChatItem> _chat = [];

  // Parsed actions (preview)
  List<_AiCreateAction> _preview = [];
  Set<int> _selectedIndices = {};

  // Quick prompts
  final List<String> _suggestions = const [
    'Add AI lecture tomorrow 10am–12pm at DK1',
    'Add Gym every weekday 6pm–7pm for 4 weeks',
    'Add Study session Saturday 2pm–4pm at Library',
    'Add Meeting next Monday 9am–10am at Online',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  /// Initialize the microphone engine
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  /// Toggle microphone recording
  void _toggleListening() async {
    if (!_speechEnabled) return;

    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    } else {
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
            // Keep cursor at the end
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });
        },
      );
      setState(() => _isListening = true);
    }
  }

  /// Pick an image from Camera or Gallery
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 50, // Compress to speed up upload
      );
      if (photo == null) return;

      setState(() {
        _selectedImage = File(photo.path);
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  void _removeImage() {
    setState(() => _selectedImage = null);
  }

  /// Send request to Python Backend
  Future<void> _send() async {
    final text = _controller.text.trim();

    // Validate: Must have text OR image to send
    if ((text.isEmpty && _selectedImage == null) || _loading) return;

    // Stop listening if we hit send while talking
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    }

    setState(() {
      _loading = true;
      _preview = [];
      _selectedIndices.clear();

      // Create a user message for the chat bubble
      String displayMsg = text;
      if (_selectedImage != null) {
        displayMsg = text.isEmpty ? "[Sent an Image]" : "[Image] $text";
      }
      _chat.add(_ChatItem.user(displayMsg));
    });

    _controller.clear();
    _scrollToBottom();

    // --- PREPARE DATA ---
    String? base64Image;
    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      base64Image = base64Encode(bytes);
    }

    // IMPORTANT: Use 10.0.2.2 for Android Emulator. Use your Real IP for physical devices.
    const String apiUrl = "http://10.0.2.2:8000/ai/parse";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "text": text.isEmpty
              ? "Extract event details from this image."
              : text,
          "image": base64Image, // Sending the image data
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
          "Backend error: ${response.statusCode}\n${response.body}",
        );
      }

      final decoded = jsonDecode(response.body);

      // Check if Python sent a specific error message
      if (decoded is Map && decoded.containsKey('error')) {
        throw Exception(decoded['error']);
      }

      final actions = decoded['actions'];

      if (actions is! List) {
        throw Exception("Invalid response: 'actions' is not a list");
      }

      final parsed = <_AiCreateAction>[];
      for (final a in actions) {
        if (a is! Map) continue;
        if (a['type'] != 'create') continue;
        parsed.add(_AiCreateAction.fromJson(Map<String, dynamic>.from(a)));
      }

      setState(() {
        _loading = false;
        _selectedImage = null; // Clear image after successful send
        _preview = parsed;
        // Default select all
        _selectedIndices = List.generate(parsed.length, (i) => i).toSet();

        if (parsed.isEmpty) {
          _chat.add(
            _ChatItem.assistant(
              "I couldn't find any events to create. Try providing more details.",
              isError: true,
            ),
          );
        } else {
          _chat.add(
            _ChatItem.assistant(
              "I found ${_preview.length} event(s). Review below, then tap Apply.",
            ),
          );
        }
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _loading = false;
        _chat.add(_ChatItem.assistant("Request failed: $e", isError: true));
      });
      _scrollToBottom();
    }
  }

  Future<void> _apply() async {
    print("DEBUG: Apply button clicked"); // 1. Check if button works

    if (_preview.isEmpty) {
      print("DEBUG: Preview is empty, returning");
      return;
    }

    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one event.")),
      );
      return;
    }

    final store = EventStore();
    final eventsToAdd = <CalendarEvent>[];

    // Build the list of events
    for (int i = 0; i < _preview.length; i++) {
      if (!_selectedIndices.contains(i)) continue;
      final a = _preview[i];

      final repeat = a.repeat;
      final count = a.count;

      for (int i = 0; i < count; i++) {
        final start = _shiftDate(a.start, repeat, i);
        final end = _shiftDate(a.end, repeat, i);

        eventsToAdd.add(
          CalendarEvent(
            id: "${DateTime.now().microsecondsSinceEpoch}_$i",
            title: a.title,
            start: start,
            end: end,
            location: a.location,
            colorValue: 0xFF007AFF,
          ),
        );
      }
    }
    print("DEBUG: Prepared ${eventsToAdd.length} events to add");

    // Check conflicts
    try {
      final conflicts = await _findConflicts(store, eventsToAdd);
      print("DEBUG: Checked conflicts, found: ${conflicts.length}");

      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Schedule conflict"),
            content: SingleChildScrollView(
              child: Text(
                "Overlap detected: ${conflicts.first}\nApply anyway?",
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Apply"),
              ),
            ],
          ),
        );
        if (ok != true) {
          print("DEBUG: User cancelled conflict dialog");
          return;
        }
      }
    } catch (e) {
      print("DEBUG: Error checking conflicts: $e");
    }

    // Save to Database
    try {
      for (final e in eventsToAdd) {
        await store.upsert(e);
      }
      print("DEBUG: Saved events to Hive database");
    } catch (e) {
      print("DEBUG: CRASH saving to database: $e");
      // If it crashes here, the screen won't close
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Added ${eventsToAdd.length} event(s)")),
    );

    // Close screen and return Date
    if (eventsToAdd.isNotEmpty) {
      print(
        "DEBUG: Closing screen, returning date: ${eventsToAdd.first.start}",
      );
      Navigator.pop(context, eventsToAdd.first.start);
    } else {
      Navigator.pop(context, null);
    }
  }

  DateTime _shiftDate(DateTime dt, String repeat, int i) {
    if (i == 0) return dt;
    if (repeat == 'daily') return dt.add(Duration(days: i));
    if (repeat == 'weekly') return dt.add(Duration(days: 7 * i));
    return dt;
  }

  Future<List<String>> _findConflicts(
    EventStore store,
    List<CalendarEvent> toAdd,
  ) async {
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

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
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

  /// Show bottom sheet to choose Camera or Gallery
  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speechToText.stop(); // Stop listening
    super.dispose();
  }

  // --- RECOMMENDATION ENGINE ---
  void _showRecommendationDialog() {
    final taskController = TextEditingController();
    final durationController = TextEditingController(text: "1 hour");
    final prefsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Get Recommendations"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: taskController,
                decoration: const InputDecoration(
                  labelText: "Task Name",
                  hintText: "e.g., Gym, Study, Meeting",
                ),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: durationController,
                decoration: const InputDecoration(
                  labelText: "Duration",
                  hintText: "e.g., 2 hours, 30 mins",
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: prefsController,
                decoration: const InputDecoration(
                  labelText: "Preferences (Optional)",
                  hintText: "e.g., After 5pm, Weekdays only",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final task = taskController.text.trim();
              final duration = durationController.text.trim();
              final prefs = prefsController.text.trim();

              if (task.isEmpty) return;

              Navigator.pop(ctx);
              _fetchAndSuggest(task, duration, prefs);
            },
            child: const Text("Suggest"),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAndSuggest(
    String task,
    String duration,
    String prefs,
  ) async {
    setState(() {
      _loading = true;
      _chat.add(
        _ChatItem.user(
          "Recommend slots for '$task' ($duration). Prefs: ${prefs.isEmpty ? 'None' : prefs}",
        ),
      );
    });
    _scrollToBottom();

    try {
      // 1. Fetch upcoming events (next 7 days)
      final store = EventStore();
      final now = DateTime.now();
      // final end = now.add(const Duration(days: 7)); // Unused

      // We need a way to get range, but existing is byDay.
      // Iterating 7 days is simple enough.
      final upcomingEvents = <CalendarEvent>[];
      for (int i = 0; i < 7; i++) {
        final dayEvents = await store.byDay(now.add(Duration(days: i)));
        upcomingEvents.addAll(dayEvents);
      }

      // 2. Format schedule string
      final sb = StringBuffer();
      if (upcomingEvents.isEmpty) {
        sb.writeln("My schedule is completely free for the next 7 days.");
      } else {
        sb.writeln(
          "Here is my existing schedule for the next 7 days (Do not overlap these):",
        );
        for (final e in upcomingEvents) {
          final timeStr =
              "${DateFormat('EEE HH:mm').format(e.start)} - ${DateFormat('HH:mm').format(e.end)}";
          sb.writeln("- $timeStr: ${e.title}");
        }
      }

      // 3. Construct Prompt
      final prompt =
          """
I need to schedule '$task' for a duration of $duration.
My preferences: ${prefs.isEmpty ? 'None' : prefs}.

$sb

Based on this, suggest 3 optimal time slots.
Return them as 'create' actions in the JSON.
""";

      // 4. Send to backend (simulated by updating controller and calling existing logic,
      // but we need to bypass the UI input)

      // Actually, we can just call the HTTP logic directly.
      // Let's refactor _send to be usable or just copy the http part specifically for this.
      // Re-using _send via _controller is hacky but ensures we use the exact same backend logic.
      // A cleaner way is to extract the API call. For now, let's just make the API call here to separate concerns.

      // Helper to avoid code dup later if we refactor.
      await _sendRawPrompt(prompt);
    } catch (e) {
      setState(() {
        _loading = false;
        _chat.add(
          _ChatItem.assistant(
            "Error getting recommendations: $e",
            isError: true,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  // Refactored from _send to allow raw text sending
  Future<void> _sendRawPrompt(String text) async {
    // IMPORTANT: Use 10.0.2.2 for Android Emulator. Use your Real IP for physical devices.
    const String apiUrl = "http://10.0.2.2:8000/ai/parse";

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": text, "image": null}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          "Backend error: ${response.statusCode}\n${response.body}",
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded.containsKey('error')) {
        throw Exception(decoded['error']);
      }

      final actions = decoded['actions'];
      if (actions is! List) {
        throw Exception("Invalid response: 'actions' is not a list");
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
        _selectedIndices = List.generate(parsed.length, (i) => i).toSet();

        if (parsed.isEmpty) {
          _chat.add(_ChatItem.assistant("I couldn't find any good slots."));
        } else {
          _chat.add(
            _ChatItem.assistant(
              "I found ${_preview.length} suggestion(s). Tap Apply to add one.",
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      rethrow; // Let caller handle
    }
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
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.lightbulb_outline, color: Colors.amber),
                tooltip: "Get AI Recommendations",
                onPressed: _showRecommendationDialog,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Suggestions chips (only show when chat is empty)
            if (_chat.isEmpty && _preview.isEmpty)
              _SuggestionBar(
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

                  ..._chat.map((m) => _ChatBubble(item: m)),

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
                    ..._preview.asMap().entries.map((entry) {
                      final i = entry.key;
                      final a = entry.value;
                      return _PreviewCard(
                        action: a,
                        isSelected: _selectedIndices.contains(i),
                        onToggle: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIndices.add(i);
                            } else {
                              _selectedIndices.remove(i);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),

            // --- IMAGE PREVIEW AREA (Above the composer) ---
            if (_selectedImage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedImage!,
                        height: 50,
                        width: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Image attached",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: _removeImage,
                    ),
                  ],
                ),
              ),

            // --- COMPOSER WITH MIC & CAMERA ---
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12 + (bottomInset > 0 ? 0 : 0),
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Camera Button
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.blue,
                    ),
                    onPressed: _showImageSourceSheet,
                  ),

                  // 2. Microphone Button
                  GestureDetector(
                    onTap: _toggleListening,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.redAccent
                            : Colors.grey.shade100,
                        shape: BoxShape.circle,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.white : Colors.black54,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Text Field
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _loading ? null : _send(),
                        decoration: const InputDecoration(
                          hintText: "Type, speak, or snap...",
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 4. Send Button
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- UI Helpers ----------------

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
            "I’ll convert it into calendar events for you. You can also scan a timetable image!",
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ExamplePill(
                text: "Add AI lecture tomorrow 10–12 DK1",
                onTap: onExampleTap,
              ),
              _ExamplePill(
                text: "Every Monday 8–10am for 12 weeks",
                onTap: onExampleTap,
              ),
              _ExamplePill(
                text: "Study Sat 2–4pm Library",
                onTap: onExampleTap,
              ),
            ],
          ),
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
                Text(suggestions[i], style: const TextStyle(fontSize: 12)),
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
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final _AiCreateAction action;
  final bool isSelected;
  final ValueChanged<bool?>? onToggle;

  const _PreviewCard({
    required this.action,
    this.isSelected = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, d MMM • HH:mm');
    final start = fmt.format(action.start);
    final endTime = DateFormat('HH:mm').format(action.end);

    return InkWell(
      onTap: () => onToggle?.call(!isSelected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.black12,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 6),
              color: const Color(0x0A000000),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox logic replacing indicator
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Colors.blue : Colors.grey.shade400,
              ),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$start – $endTime",
                    style: const TextStyle(color: Colors.black54),
                  ),
                  if (action.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      action.location,
                      style: const TextStyle(color: Colors.black54),
                    ),
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
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.black87),
      ),
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
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text("Thinking…"),
          ],
        ),
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
          border: Border.all(
            color: isUser ? Colors.transparent : Colors.black12,
          ),
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
            color: isUser
                ? Colors.white
                : (item.isError ? Colors.red.shade700 : Colors.black87),
          ),
        ),
      ),
    );
  }
}

// ---------------- Data Helpers ----------------

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

// ----- Helper class for AI actions -----

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

    final startStr = (a['start'] ?? '').toString();
    final endStr = (a['end'] ?? '').toString();

    // Basic fallback to "now" if parsing fails
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(hours: 1));

    if (startStr.isNotEmpty) {
      try {
        start = DateTime.parse(startStr).toLocal();
      } catch (_) {}
    }
    if (endStr.isNotEmpty) {
      try {
        end = DateTime.parse(endStr).toLocal();
      } catch (_) {}
    }

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
