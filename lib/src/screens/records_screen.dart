import 'package:flutter/material.dart';

import '../models/survey.dart';
import '../services/csv_export.dart';
import '../services/db_service.dart';
import '../theme.dart';
import 'saved_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<SurveyRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await DbService.instance.all();
    if (mounted) {
      setState(() {
        _records = r;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('조사 기록'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '전체 CSV 내보내기',
            onPressed: _records.isEmpty ? null : () => CsvExport.share(_records),
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const _Empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tile(_records[i]),
                  ),
                ),
    );
  }

  Widget _tile(SurveyRecord r) {
    final cut = r.verdict == '벌채';
    return Dismissible(
      key: ValueKey(r.dbId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.stemRed, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        if (r.dbId != null) await DbService.instance.delete(r.dbId!);
        _load();
      },
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SavedScreen(record: r))),
          leading: CircleAvatar(
            backgroundColor: AppColors.navy.withValues(alpha: 0.1),
            child: const Icon(Icons.park, color: AppColors.navy),
          ),
          title: Text(r.treeId, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${r.site.isEmpty ? '' : '${r.site} · '}BSI ${r.bsi.isNaN ? '–' : r.bsi.toStringAsFixed(2)} · ${_date(r.createdAt)}',
              style: const TextStyle(fontSize: 12)),
          trailing: r.verdict.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: (cut ? AppColors.stemRed : AppColors.green).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(r.verdict,
                      style: TextStyle(
                          color: cut ? AppColors.stemRed : AppColors.green,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
        ),
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 56, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text('저장된 조사 기록이 없습니다', style: TextStyle(color: AppColors.textSecondary)),
        ]),
      );
}
