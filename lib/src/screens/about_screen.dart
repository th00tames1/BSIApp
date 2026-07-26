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
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1F8A4C), Color(0xFFC24A1E)]),
                ),
                child: const Icon(Icons.gps_fixed, color: Colors.white, size: 34),
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
              _row(
                  p,
                  Icons.memory,
                  tr('분할 모델', 'Segmentation model'),
                  tr('YOLO26s-seg @640 · 수간·그을음',
                      'YOLO26s-seg @640 · Stem & char')),
              Divider(height: 1, color: p.line),
              _row(
                  p,
                  Icons.info_outline,
                  tr('BSI 정의', 'BSI definition'),
                  tr('Σ 4방위 (그을음 높이 × 비율) · Kwon 2021',
                      'Σ 4 aspects (char height × ratio) · Kwon 2021')),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(AppPalette p, IconData ic, String t1, String t2) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Icon(ic, size: 22, color: p.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text(t2, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
        ]),
      );
}
