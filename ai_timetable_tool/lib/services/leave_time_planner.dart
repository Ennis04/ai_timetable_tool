import 'package:geolocator/geolocator.dart';

import '../models/calendar_event.dart';
import 'ors_eta_service.dart';
import 'reminder_service.dart';

class LeaveTimePlanner {
  final OrsEtaService ors;
  final String profile;
  final Duration buffer;

  LeaveTimePlanner(
    this.ors, {
    this.profile = 'driving-car',
    this.buffer = const Duration(minutes: 10),
  });

  Future<void> planForEvent(CalendarEvent e) async {
    final now = DateTime.now();

    // Ignore events that already started
    if (!e.start.isAfter(now)) {
      _log('Skip "${e.title}" because event already started.');
      return;
    }

    final notifId = _notifId(e);

    // Clear old reminder
    await ReminderService.instance.cancel(notifId);

    _log('--- Plan for "${e.title}" ---');
    _log('Now: $now');
    _log('Start: ${e.start}');
    _log('Location text: "${e.location}"');

    // No location -> 30 min before (or immediate)
    if (e.location.trim().isEmpty) {
      _log('No location. Using 30-min reminder.');
      return _schedule30Min(e, notifId, reason: null);
    }

    // Location services
    final enabled = await Geolocator.isLocationServiceEnabled();
    _log('Location service enabled: $enabled');
    if (!enabled) {
      return _schedule30Min(e, notifId, reason: 'Location service is OFF');
    }

    // Permission
    var perm = await Geolocator.checkPermission();
    _log('Initial permission: $perm');

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      _log('Permission after request: $perm');
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return _schedule30Min(e, notifId, reason: 'No location permission');
    }

    // Current position
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (err) {
      _log('getCurrentPosition failed: $err');
      return _schedule30Min(e, notifId, reason: 'Cannot get current position');
    }

    final origin = LatLng(pos.latitude, pos.longitude);
    _log('Origin: lat=${origin.lat}, lng=${origin.lng}');

    // Geocode destination
    LatLng? dest;
    try {
      dest = await ors.geocode(e.location);
    } catch (err) {
      _log('Geocode threw error: $err');
      dest = null;
    }

    if (dest == null) {
      return _schedule30Min(e, notifId, reason: 'Geocode failed (no result)');
    }
    _log('Destination: lat=${dest.lat}, lng=${dest.lng}');

    // ETA
    Duration? eta;
    try {
      eta = await ors.eta(origin: origin, destination: dest, profile: profile);
    } catch (err) {
      _log('ETA threw error: $err');
      eta = null;
    }

    if (eta == null) {
      return _schedule30Min(e, notifId, reason: 'ETA failed (ORS directions)');
    }

    _log('ETA: ${eta.inMinutes} min');

    // Leave time
    final leaveAt = e.start.subtract(eta).subtract(buffer);
    _log('Buffer: ${buffer.inMinutes} min');
    _log('LeaveAt: $leaveAt');

    await _notifyOrSchedule(
      id: notifId,
      title: 'Time to leave',
      body: 'Leave now for "${e.title}" (ETA ${eta.inMinutes} min)',
      when: leaveAt,
      debugReason: 'ETA route ok',
    );
  }

  Future<void> _schedule30Min(
    CalendarEvent e,
    int notifId, {
    String? reason,
  }) async {
    final when = e.start.subtract(const Duration(minutes: 30));
    final msg = reason == null
        ? 'Starts in 30 minutes.'
        : 'Starts in 30 minutes. ($reason)';

    _log('Fallback 30-min. When=$when. Reason=$reason');

    await _notifyOrSchedule(
      id: notifId,
      title: 'Upcoming: ${e.title}',
      body: msg,
      when: when,
      debugReason: reason ?? 'no reason',
    );
  }

  /// If reminder time already passed but event not started -> notify now.
  Future<void> _notifyOrSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String debugReason,
  }) async {
    final now = DateTime.now();

    if (!when.isAfter(now)) {
      _log('Notify NOW (missed time). when=$when now=$now reason=$debugReason');
      await ReminderService.instance.showNow(id: id, title: title, body: body);
      return;
    }

    _log('Schedule. when=$when now=$now reason=$debugReason');
    await ReminderService.instance.schedule(
      id: id,
      title: title,
      body: body,
      when: when,
    );
  }

  int _notifId(CalendarEvent e) => e.id.hashCode & 0x7fffffff;

  void _log(String msg) {
    // Easy to search in console
    // ignore: avoid_print
    print('[LeaveTimePlanner] $msg');
  }
}
