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
        padding: EdgeInsets.fromLTRB(
            16, 20, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
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
              const Text('BSI_app',
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('개발자 정보', 'Developers'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: p.muted)),
                const SizedBox(height: 8),
                const Text('Oregon State University',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text('College of Forestry',
                    style: TextStyle(fontSize: 13, color: p.ink)),
                const SizedBox(height: 3),
                Text('Heechan Jeong, Heesung Woo',
                    style: TextStyle(fontSize: 13, color: p.ink)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _bsiCard(p),
        ],
      ),
    );
  }

  /// BSI 공식의 출처. 공식 세부는 논문에 맡기고 인용만 남긴다.
  Widget _bsiCard(AppPalette p) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('BSI 공식 출처', 'BSI formula reference'),
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

}
