import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../services/demo_sample.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'analysis_screen.dart';
import 'bsi_table_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  /// 내장 예시 사진 4장을 불러와 바로 AI 분석을 실행한다. 촬영 화면을 거치지
  /// 않으므로 카메라 권한 없이도 전체 분석 파이프라인을 시험할 수 있다.
  Future<void> _runDemo() async {
    setState(() => _busy = true);
    try {
      final draft = await DemoSample.createDraft();
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnalysisScreen(draft: draft)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(tr('예시 데이터를 불러오지 못했습니다: $e',
                'Could not load the sample data: $e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('설정', 'Settings'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 6, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
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
          // 시험 섹션은 개발자 모드(지도의 현재 위치 버튼 7번 탭)에서만 보인다.
          if (devMode.value) ...[
            _section(p, tr('시험 (개발자)', 'TRY IT (DEVELOPER)')),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : _runDemo,
                child: _row(p, Icons.science_outlined,
                    tr('예시 사진으로 시험', 'Try with sample photos'),
                    sub: tr('내장된 4방위 사진으로 분석 전체를 실행',
                        'Run the full analysis on the four bundled photos'),
                    trailing: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.chevron_right, color: p.muted)),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: _row(p, Icons.smart_display_outlined, tr('시연 모드', 'Demo mode'),
                  sub: tr('조사목 추가 시 예시 사진으로 촬영→분석→판정표→기록까지 자동 진행',
                      'New tree auto-runs capture→analysis→table→records with sample photos'),
                  trailing: Switch(
                    value: demoMode.value,
                    onChanged: (v) => setState(() => setDemoMode(v)),
                  )),
            ),
          ],
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
