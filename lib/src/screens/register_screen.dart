import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../services/db_service.dart';
import '../theme.dart';

/// Create or edit one project (조사지). 조사지명·위치는 한 번만 입력하고,
/// 이후 조사목은 지도의 나무 버튼으로 자동 번호와 함께 바로 촬영한다.
class ProjectScreen extends StatefulWidget {
  final Project? project; // null = 새 프로젝트, non-null = 편집
  const ProjectScreen({super.key, this.project});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _site =
      TextEditingController(text: widget.project?.site ?? '');
  late final TextEditingController _loc =
      TextEditingController(text: widget.project?.location ?? '');
  late final TextEditingController _seq =
      TextEditingController(text: (widget.project?.treeSeq ?? 0).toString());

  @override
  void dispose() {
    _site.dispose();
    _loc.dispose();
    _seq.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final oldSite = widget.project?.site;
    final newSite = _site.text.trim();
    final ok = upsertProject(
      existing: widget.project,
      site: _site.text,
      location: _loc.text,
      treeSeq: int.tryParse(_seq.text.trim()) ?? 0,
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('이미 있는 조사지명입니다')));
      }
      return;
    }
    // Renamed an existing project → move its saved records to the new site key.
    if (oldSite != null && oldSite != newSite) {
      await DbService.instance.renameSite(oldSite, newSite);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final editing = widget.project != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '프로젝트 수정' : '새 프로젝트')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            Text('조사지 정보는 한 번만 입력합니다. 이후 조사목은 지도의 나무 버튼으로 자동 번호와 함께 바로 촬영합니다.',
                style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5)),
            _label(p, '조사지명', required: true),
            TextFormField(
              controller: _site,
              decoration: const InputDecoration(hintText: '예: 인제 남면 3-2 임반'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null,
            ),
            _label(p, '위치'),
            TextFormField(
              controller: _loc,
              decoration: const InputDecoration(hintText: '강원 인제군 남면'),
            ),
            _label(p, '다음 조사목 번호'),
            TextFormField(
              controller: _seq,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  hintText: '0', helperText: '이 번호부터 +1씩 자동 부여됩니다'),
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _save,
              child: Text(editing ? '수정 저장' : '프로젝트 시작'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AppPalette p, String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Row(children: [
          Text(text,
              style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (required)
            Text('  *', style: TextStyle(color: p.ember, fontWeight: FontWeight.w700)),
        ]),
      );
}
