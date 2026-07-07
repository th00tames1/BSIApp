import 'dart:io';

import 'package:flutter/material.dart';

import '../models/draft.dart';
import '../models/survey.dart';
import '../services/db_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'saved_screen.dart';

class ResultScreen extends StatefulWidget {
  final SurveyDraft draft;
  const ResultScreen({super.key, required this.draft});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Azimuth _sel;
  bool _saving = false;

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _sel = d.capturedAzimuths.isNotEmpty ? d.capturedAzimuths.first : Azimuth.east;
  }

  String _m(double v, [int digits = 2]) =>
      v.isNaN ? '–' : '${v.toStringAsFixed(digits)} m';
  String _n(double v, [int digits = 2]) => v.isNaN ? '–' : v.toStringAsFixed(digits);

  Future<void> _save() async {
    setState(() => _saving = true);
    final rec = d.toRecord();
    final id = await DbService.instance.insert(rec);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SavedScreen(record: rec.copyWith(dbId: id))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final face = d.results[_sel];
    final integ = d.integ;
    return Scaffold(
      appBar: AppBar(
        title: const Text('수목 분석 결과'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.map_outlined))
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (d.capturedAzimuths.length > 1) _faceChips(),
          const SizedBox(height: 8),
          _overlay(face),
          const SizedBox(height: 14),
          _metricCard(face),
          const SizedBox(height: 14),
          _bsiCard(integ),
          const SizedBox(height: 14),
          _azimuthRatios(),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('데이터 저장'),
          ),
        ],
      ),
    );
  }

  Widget _faceChips() {
    return Wrap(
      spacing: 8,
      children: d.capturedAzimuths.map((a) {
        final sel = a == _sel;
        return ChoiceChip(
          label: Text('${a.ko} 방위'),
          selected: sel,
          selectedColor: AppColors.green.withValues(alpha: 0.18),
          labelStyle: TextStyle(
              color: sel ? AppColors.green : AppColors.textSecondary,
              fontWeight: FontWeight.w700),
          onSelected: (_) => setState(() => _sel = a),
        );
      }).toList(),
    );
  }

  Widget _overlay(AzimuthResult? face) {
    final path = face?.overlayPath ?? face?.imagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: path != null
            ? Image.file(File(path), fit: BoxFit.cover)
            : Container(color: Colors.black12, child: const Center(child: Text('이미지 없음'))),
      ),
    );
  }

  Widget _metricCard(AzimuthResult? f) {
    if (f == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          MetricRow(Icons.straighten, '픽셀 스케일',
              f.pxPerMetre.isNaN ? '수고봉 미검출' : '${f.pxPerMetre.round()} px / 1 m',
              valueColor: f.pxPerMetre.isNaN ? AppColors.textSecondary : null),
          const Divider(height: 1),
          MetricRow(Icons.height, '그을음 높이', _m(f.sootHeightM)),
          const Divider(height: 1),
          MetricRow(Icons.swap_horiz, '그을음 폭', _m(f.sootWidthM)),
          const Divider(height: 1),
          MetricRow(Icons.park_outlined, '줄기 보이는 높이', _m(f.visibleStemHeightM)),
          const Divider(height: 1),
          MetricRow(Icons.circle_outlined, '흉고직경(추정)', _m(f.dbhEstM)),
          const Divider(height: 1),
          MetricRow(Icons.local_fire_department, '그을음 비율',
              _n(f.sootProportion), valueColor: AppColors.green),
        ]),
      ),
    );
  }

  Widget _bsiCard(dynamic integ) {
    final bsi = (integ?.bsi as double?) ?? double.nan;
    final prob = (integ?.mortality as double?) ?? double.nan;
    final verdict = (integ?.verdict as String?) ?? '';
    final cut = verdict == '벌채';
    return Card(
      color: AppColors.navy,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            const Text('통합 BSI', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const Spacer(),
            Text(bsi.isNaN ? '–' : bsi.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('고사 가능성', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const Spacer(),
            Text(prob.isNaN ? '–' : '${(prob * 100).round()} %',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (verdict.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: cut ? AppColors.stemRed : AppColors.green,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(verdict,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _azimuthRatios() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('방위별 그을음 비율 (%)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: Azimuth.values.map((a) {
              final r = d.results[a];
              final v = r?.sootProportion ?? double.nan;
              return Expanded(
                child: Column(children: [
                  Text(v.isNaN ? '–' : '${(v * 100).round()}%',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  const SizedBox(height: 4),
                  Text(a.ko, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ]),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }
}
