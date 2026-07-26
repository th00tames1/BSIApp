import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'bsi_table_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('설정', 'Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _section(p, tr('일반', 'GENERAL')),
          Card(
            child: Column(children: [
              _row(p, Icons.brightness_6_outlined, tr('테마', 'Theme'),
                  trailing: _Segmented(
                    options: [tr('라이트', 'Light'), tr('다크', 'Dark')],
                    index: themeMode.value == ThemeMode.dark ? 1 : 0,
                    onSelect: (i) => setState(() =>
                        setThemeMode(i == 0 ? ThemeMode.light : ThemeMode.dark)),
                  )),
              Divider(height: 1, color: p.line),
              _row(p, Icons.language, tr('언어', 'Language'),
                  trailing: _Segmented(
                    options: const ['한국어', 'English'],
                    index: appLang.value == AppLang.en ? 1 : 0,
                    onSelect: (i) => setState(
                        () => setAppLang(i == 0 ? AppLang.ko : AppLang.en)),
                  )),
            ]),
          ),
          _section(p, tr('촬영', 'CAPTURE')),
          Card(
            child: Column(children: [
              _row(p, Icons.straighten, tr('촬영 안내선', 'Capture guide'),
                  sub: tr('수고봉 정렬선 표시', 'Show the pole alignment line'),
                  trailing: Switch(
                    value: showGuides.value,
                    onChanged: (v) => setState(() => setShowGuides(v)),
                  )),
            ]),
          ),
          _section(p, tr('판정 기준', 'DECISION CRITERIA')),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BsiTableScreen())),
              child: _row(p, Icons.grid_on, tr('존치·벌채 판정표', 'Retain / fell table'),
                  sub: tr('BSI × 흉고직경 고사 확률표', 'Mortality probability by BSI × DBH'),
                  trailing: Icon(Icons.chevron_right, color: p.muted)),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AboutScreen())),
              child: _row(p, Icons.info_outline, tr('정보', 'About'),
                  trailing: Icon(Icons.chevron_right, color: p.muted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(AppPalette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: p.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.0)),
      );

  Widget _row(AppPalette p, IconData ic, String title,
      {String? sub, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(ic, size: 22, color: p.navy),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
            ],
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onSelect;
  const _Segmented({required this.options, required this.index, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration:
          BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < options.length; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: i == index ? p.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: i == index
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)]
                    : null,
              ),
              child: Text(options[i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: i == index ? p.ink : p.muted)),
            ),
          ),
      ]),
    );
  }
}
