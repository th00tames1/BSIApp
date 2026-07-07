import 'package:flutter/material.dart';

import 'src/screens/home_screen.dart';
import 'src/screens/records_screen.dart';
import 'src/screens/register_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/theme.dart';
import 'src/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BsiApp());
}

class BsiApp extends StatelessWidget {
  const BsiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '산불피해목 BSI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final _pages = const [HomeScreen(), SizedBox.shrink(), RecordsScreen(), SettingsScreen()];

  Future<void> _onTap(int i) async {
    if (i == 1) {
      // 조사 → start a new survey flow
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
      if (mounted) setState(() {}); // refresh on return
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: AppBottomNav(index: _index, onTap: _onTap),
    );
  }
}
