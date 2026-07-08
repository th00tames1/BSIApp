import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../theme.dart';
import 'about_screen.dart';

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
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _section(p, '일반'),
          Card(
            child: Column(children: [
              _row(p, Icons.light_mode_outlined, '테마',
                  trailing: _Segmented(
                    options: const ['현장', '저조도'],
                    index: themeMode.value == ThemeMode.dark ? 1 : 0,
                    onSelect: (i) => setState(
                        () => themeMode.value = i == 0 ? ThemeMode.light : ThemeMode.dark),
                  )),
            ]),
          ),
          _section(p, '촬영'),
          Card(
            child: Column(children: [
              _row(p, Icons.gps_fixed, '촬영 안내선', sub: '수직선·크로스헤어 표시',
                  trailing: Switch(
                    value: showGuides.value,
                    onChanged: (v) => setState(() => showGuides.value = v),
                  )),
              Divider(height: 1, color: p.line),
              _row(p, Icons.bolt_outlined, '플래시 기본값',
                  trailing: _Segmented(
                    options: const ['끔', '자동'],
                    index: defaultFlashAuto.value ? 1 : 0,
                    onSelect: (i) => setState(() => defaultFlashAuto.value = i == 1),
                  )),
            ]),
          ),
          _section(p, '계측'),
          Card(
            child: Column(children: [
              _row(p, Icons.straighten, '수고봉 길이', sub: '촬영 시 픽셀→미터 스케일 기준',
                  trailing: _Stepper(
                    value: poleLengthM.value,
                    onChanged: (v) => setState(() => poleLengthM.value = v),
                  )),
              Divider(height: 1, color: p.line),
              _row(p, Icons.memory, '분할 모델',
                  trailing: Text('YOLO26s @640',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: p.navy))),
            ]),
          ),
          const SizedBox(height: 14),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AboutScreen())),
              child: _row(p, Icons.info_outline, '정보',
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
      decoration: BoxDecoration(
          color: p.surface2, borderRadius: BorderRadius.circular(9)),
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

class _Stepper extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _Stepper({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget btn(IconData ic, VoidCallback? onTap) => Material(
          color: p.surface2,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
                width: 30,
                height: 30,
                child: Icon(ic, size: 18, color: onTap == null ? p.muted : p.navy)),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove, value > 1.0 ? () => onChanged((value - 0.5).clamp(1.0, 6.0)) : null),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('${value.toStringAsFixed(1)} m',
            style: TextStyle(
                fontFamily: 'monospace', fontWeight: FontWeight.w700, color: p.navy)),
      ),
      btn(Icons.add, value < 6.0 ? () => onChanged((value + 0.5).clamp(1.0, 6.0)) : null),
    ]);
  }
}
