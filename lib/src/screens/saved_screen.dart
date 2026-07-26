import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/survey.dart';
import '../services/csv_export.dart';
import '../services/db_service.dart';
import '../theme.dart';

/// Detail view for a saved survey record (opened from the map pin / 기록).
class SavedScreen extends StatelessWidget {
  final SurveyRecord record;
  const SavedScreen({super.key, required this.record});

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('조사목 삭제', 'Delete tree')),
        content: Text(tr('조사목 ${record.treeId}을(를) 삭제합니다. 되돌릴 수 없습니다.',
            'Tree ${record.treeId} will be deleted. This cannot be undone.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('취소', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('삭제', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    if (record.dbId != null) await DbService.instance.delete(record.dbId!);
    if (context.mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cut = record.verdict == '벌채';
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('조사목 상세', 'Tree detail')),
        actions: [
          IconButton(
            tooltip: tr('CSV 내보내기', 'Export CSV'),
            onPressed: () => CsvExport.share([record]),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: tr('삭제', 'Delete'),
            onPressed: () => _delete(context),
            icon: Icon(Icons.delete_outline, color: p.danger),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(record.treeId,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (record.verdict.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: (cut ? p.danger : p.green).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(verdictLabel(record.verdict),
                    style: TextStyle(
                        color: cut ? p.danger : p.green,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          if (record.site.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.site, style: TextStyle(color: p.muted, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _row(p, Icons.local_fire_department_outlined,
                    tr('통합 BSI', 'Integrated BSI'),
                    record.bsi.isNaN ? '–' : record.bsi.toStringAsFixed(2)),
                Divider(height: 1, color: p.line),
                _row(p, Icons.warning_amber_rounded, tr('고사 확률', 'Mortality'),
                    record.mortalityProb.isNaN
                        ? '–'
                        : '${(record.mortalityProb * 100).round()}%'),
                Divider(height: 1, color: p.line),
                _row(p, Icons.forest_outlined, tr('수종', 'Species'),
                    record.species.isEmpty ? '–' : speciesLabel(record.species)),
                Divider(height: 1, color: p.line),
                _row(p, Icons.straighten, tr('흉고직경', 'DBH'),
                    record.dbhCm == 0 ? '–' : '${record.dbhCm.toStringAsFixed(1)} cm'),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => _PhotoViewer(record: record))),
            child: Text(tr('결과 사진 보기', 'View result photos')),
          ),
        ],
      ),
    );
  }

  Widget _row(AppPalette p, IconData ic, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Icon(ic, size: 20, color: p.green),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: p.muted))),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 15.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _PhotoViewer extends StatelessWidget {
  final SurveyRecord record;
  const _PhotoViewer({required this.record});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final faces =
        record.faces.where((f) => (f.overlayPath ?? f.imagePath) != null).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('결과 사진', 'Result photos'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: faces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) {
          final f = faces[i];
          final path = f.overlayPath ?? f.imagePath!;
          final pct = f.sootProportion.isNaN
              ? '–'
              : '${(f.sootProportion * 100).round()}%';
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                tr('${azimuthLabelFromCode(f.azimuth)} · 그을음 비율 $pct',
                    '${azimuthLabelFromCode(f.azimuth)} · Char ratio $pct'),
                style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
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
