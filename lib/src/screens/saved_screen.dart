import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/survey.dart';
import '../services/csv_export.dart';
import '../services/db_service.dart';
import '../theme.dart';

/// Detail view for a saved survey record (opened from the map pin / 기록).
class SavedScreen extends StatefulWidget {
  final SurveyRecord record;
  const SavedScreen({super.key, required this.record});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final _pager = PageController();
  int _page = 0;

  SurveyRecord get record => widget.record;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

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
    final faces =
        record.faces.where((f) => (f.overlayPath ?? f.imagePath) != null).toList();
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
          const SizedBox(height: 12),
          if (faces.isNotEmpty) ...[
            _photoPager(p, faces),
            const SizedBox(height: 8),
            _dots(p, faces.length),
            const SizedBox(height: 10),
          ],
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
        ],
      ),
    );
  }

  /// 결과 사진을 표 위에 바로 띄우고 옆으로 넘겨 본다.
  /// 각 장에 방위와 그을음 비율을 함께 표시한다.
  Widget _photoPager(AppPalette p, List<AzimuthResult> faces) {
    final h = (MediaQuery.of(context).size.height * 0.38).clamp(240.0, 420.0);
    return SizedBox(
      height: h,
      child: PageView.builder(
        controller: _pager,
        itemCount: faces.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) {
          final f = faces[i];
          final path = f.overlayPath ?? f.imagePath!;
          final pct = f.sootProportion.isNaN
              ? '–'
              : '${(f.sootProportion * 100).round()}%';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                Image.file(File(path), fit: BoxFit.cover),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xB3080C12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(
                        tr('${azimuthLabelFromCode(f.azimuth)} · 그을음 $pct',
                            '${azimuthLabelFromCode(f.azimuth)} · Char $pct'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xB3080C12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('${i + 1}/${faces.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _dots(AppPalette p, int n) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (int i = 0; i < n; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _page ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
              color: i == _page ? p.navy : p.line,
              borderRadius: BorderRadius.circular(999)),
        ),
    ]);
  }

  // 사진이 위 공간을 차지하는 만큼 표는 세로만 살짝 줄였다(좌우 여백은 유지).
  Widget _row(AppPalette p, IconData ic, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Icon(ic, size: 18, color: p.green),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: p.muted))),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );
}
