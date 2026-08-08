import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('정보', 'About'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Center(
            child: Column(children: [
              // 런처 아이콘과 같은 그림을 쓴다(정보 화면만 다른 그림이면 딴 앱처럼 보인다).
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset('assets/icon/icon.png',
                    width: 76, height: 76, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              const Text('ReForest',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 8),
              Text(
                  tr('산불피해목 진단·복원 지원 · v0.1',
                      'Fire-damaged tree assessment & restoration · v0.1'),
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, color: p.muted)),
            ]),
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(children: [
              _row(p, Icons.forest_outlined, 'Oregon State University',
                  'Advanced Forestry Systems Lab'),
              Divider(height: 1, color: p.line),
              _row(p, Icons.code, tr('개발', 'Developed by'),
                  tr('정희찬 · 우희성', 'Heechan Jeong · Heesung Woo')),
            ]),
          ),
          const SizedBox(height: 14),
          _bsiCard(p),
        ],
      ),
    );
  }

  /// BSI 정의는 원 논문 표기를 그대로 두고 인용 양식으로 출처를 붙인다.
  Widget _bsiCard(AppPalette p) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.functions, size: 22, color: p.navy),
              const SizedBox(width: 12),
              Text(tr('수피 그을음 지수 (BSI)', 'Bark Scorch Index (BSI)'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ]),
            const SizedBox(height: 12),
            // 아래첨자는 monospace에 글리프가 없어 깨진다. 본문 글꼴로 둔다.
            Text('BSI = Σ (Hᵢ × Rᵢ),   i ∈ {N, E, S, W}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: p.ink)),
            const SizedBox(height: 8),
            Text(
                tr('Hᵢ = 방위 i의 그을음 최고 높이 (m),   Rᵢ = 방위 i의 그을음 면적 비율',
                    'Hᵢ = maximum scorch height on aspect i (m),   '
                        'Rᵢ = scorched area ratio on aspect i'),
                style: TextStyle(fontSize: 12, height: 1.5, color: p.muted)),
            const SizedBox(height: 14),
            Divider(height: 1, color: p.line),
            const SizedBox(height: 12),
            Text(tr('출처', 'Reference'),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: p.muted)),
            const SizedBox(height: 6),
            Text(
                'Kwon, S., Kim, S., Kim, J., Kang, W., Park, K.-H., Kim, C.-B., '
                '& Girona, M. M. (2021). Predicting Post-Fire Tree Mortality in a '
                'Temperate Pine Forest, Korea. Sustainability, 13(2), 569.',
                style: TextStyle(fontSize: 11.5, height: 1.55, color: p.ink)),
            const SizedBox(height: 4),
            Text('https://doi.org/10.3390/su13020569',
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 11, color: p.muted)),
          ]),
        ),
      );

  Widget _row(AppPalette p, IconData ic, String t1, String t2) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Icon(ic, size: 22, color: p.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t1,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(t2, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        ]),
      );
}
