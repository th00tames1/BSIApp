import 'package:flutter/material.dart';

import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('정보')),
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
              const Text('다시숲',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('ReForest',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      letterSpacing: 2,
                      color: p.muted)),
              const SizedBox(height: 8),
              Text('산불피해목 진단·복원 지원 · v0.1',
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
              _row(p, Icons.memory, '분할 모델', 'YOLO26s-seg @640 · 수간·그을음'),
              Divider(height: 1, color: p.line),
              _row(p, Icons.info_outline, 'BSI 정의',
                  'Σ 4방위 (그을음 높이 × 비율) · Kwon 2021'),
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
