import 'dart:io';

import 'package:flutter/material.dart';

import '../models/survey.dart';
import '../services/csv_export.dart';
import '../theme.dart';

class SavedScreen extends StatelessWidget {
  final SurveyRecord record;
  const SavedScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('저장 완료')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.check_circle, color: AppColors.green, size: 68),
            ),
            const SizedBox(height: 22),
            const Text('데이터가 성공적으로\n저장되었습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 8),
            Text('조사목 ${record.treeId}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const Spacer(),
            ElevatedButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => _PhotoViewer(record: record))),
              child: const Text('결과 사진 보기'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => CsvExport.share([record]),
              child: const Text('CSV 내보내기'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('홈으로'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final SurveyRecord record;
  const _PhotoViewer({required this.record});
  @override
  Widget build(BuildContext context) {
    final faces = record.faces.where((f) => (f.overlayPath ?? f.imagePath) != null).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('결과 사진')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: faces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) {
          final f = faces[i];
          final path = f.overlayPath ?? f.imagePath!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f.azimuth} 방위 · 그을음 비율 ${f.sootProportion.isNaN ? '–' : (f.sootProportion * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path), fit: BoxFit.contain)),
          ]);
        },
      ),
    );
  }
}
