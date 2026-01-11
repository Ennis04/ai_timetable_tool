import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../models/calendar_event.dart';
import '../storage/event_store.dart';
import 'package:flutter/foundation.dart'; // Required for kDebugMode

class GoogleCalendarService {
  static final GoogleCalendarService _instance =
      GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();

  static String? clientId =
      "361896201650-gt2hq55o8qd82u088jdl1s2fvfpd81t8.apps.googleusercontent.com";

  static const _scopes = <String>[cal.CalendarApi.calendarReadonlyScope];

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
    clientId: clientId,
  );

  /// Sign in and load events, merging them into the local EventStore.
  Future<void> signInAndLoadEvents() async {
    final gEvents = await fetchUpcomingEvents();
    if (gEvents.isEmpty) return;

    final store = EventStore();
    final List<CalendarEvent> converted = [];

    for (final e in gEvents) {
      // Handle both timed events (dateTime) and all-day events (date)
      DateTime? start = e.start?.dateTime ?? e.start?.date;
      DateTime? end = e.end?.dateTime ?? e.end?.date;

      if (start == null) continue;
      // If end is null, assume 1 hour duration
      end ??= start.add(const Duration(hours: 1));

      converted.add(
        CalendarEvent(
          id: "gcal_${e.id ?? DateTime.now().microsecondsSinceEpoch}",
          title: e.summary ?? '(No title)',
          start: start.toLocal(),
          end: end.toLocal(),
          location: e.location ?? '',
          colorValue: 0xFF34A853, // Google Green
          googleId: e.id,
        ),
      );
    }

    await store.syncGoogleEvents(converted);
  }

  Future<List<cal.Event>> fetchUpcomingEvents({int maxResults = 50}) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return []; // user cancelled

      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception("Failed to get authenticated HTTP client");
      }

      final api = cal.CalendarApi(authClient);

      final now = DateTime.now().toUtc();
      final events = await api.events.list(
        "primary",
        timeMin: now,
        singleEvents: true,
        orderBy: "startTime",
        maxResults: maxResults,
      );

      return events.items ?? [];
    } catch (e) {
      if (kDebugMode) {
        print("Google Calendar Fetch Error: $e");
      }
      rethrow;
    }
  }

  Future<void> signOut() => _googleSignIn.signOut();
}
