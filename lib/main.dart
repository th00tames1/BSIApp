import 'package:flutter/material.dart';

import 'src/app_prefs.dart';
import 'src/screens/map_screen.dart';
import 'src/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPrefs();
  runApp(const BsiApp());
}

class BsiApp extends StatelessWidget {
  const BsiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'ReForest',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const MapScreen(),
      ),
    );
  }
}
