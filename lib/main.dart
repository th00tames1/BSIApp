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
    // Theme rebuilds the app. Language must NOT key the MaterialApp — that
    // would rebuild the Navigator and throw the user back to the map. Screens
    // opened after the switch read the new language; the one screen that
    // outlives a switch (the map) listens to [appLang] itself.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'BSI_app',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const MapScreen(),
      ),
    );
  }
}
