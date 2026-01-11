import 'dart:convert';
import 'package:http/http.dart' as http;

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);
}

class OrsEtaService {
  final String apiKey;
  OrsEtaService(this.apiKey);

  Future<LatLng?> geocode(String text) async {
    final uri = Uri.https(
      'api.openrouteservice.org',
      '/geocode/search',
      {'text': text, 'size': '1'},
    );

    final res = await http.get(
      uri,
      headers: {'Authorization': apiKey, 'Accept': 'application/json'},
    );

    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    final features = data['features'] as List?;
    if (features == null || features.isEmpty) return null;

    final coords = features[0]['geometry']?['coordinates'];
    if (coords is! List || coords.length < 2) return null;

    final lng = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    return LatLng(lat, lng);
  }

  Future<Duration?> eta({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving-car',
  }) async {
    final uri = Uri.https(
      'api.openrouteservice.org',
      '/v2/directions/$profile',
    );

    final body = jsonEncode({
      'coordinates': [
        [origin.lng, origin.lat],
        [destination.lng, destination.lat],
      ],
    });

    final res = await http.post(
      uri,
      headers: {
        'Authorization': apiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      },
      body: body,
    );

    // ✅ Print full error details
    if (res.statusCode != 200) {
      // ignore: avoid_print
      print('[ORS] Directions failed: ${res.statusCode}');
      // ignore: avoid_print
      print('[ORS] Body: ${res.body}');
      return null;
    }

    final data = jsonDecode(res.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final summary = routes[0]['summary'];
    final seconds = (summary?['duration'] as num?)?.toInt();
    if (seconds == null) return null;

    return Duration(seconds: seconds);
  }

}
