import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/calendar_event.dart';
import 'screens/calendar_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(CalendarEventAdapter());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const CalendarHomeScreen(),
    );
  }
}
