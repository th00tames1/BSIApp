import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../services/db_service.dart';
import '../services/overlay_store.dart';
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
  // Project.treeSeq는 마지막 조사목 번호이므로 화면에는 그다음 번호를 보여 주고
  // 저장할 때 1을 빼서 되돌린다.
  late final TextEditingController _seq = TextEditingController(
      text: ((widget.project?.treeSeq ?? 0) + 1).toString());

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
      treeSeq: math.max((int.tryParse(_seq.text.trim()) ?? 1) - 1, 0),
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(tr('이미 등록된 조사지명입니다', 'Site name already exists'))));
      }
      return;
    }
    // Renamed an existing project → move its saved records and boundary to the
    // new site key (the in-progress draft follows inside upsertProject).
    if (oldSite != null && oldSite != newSite) {
      await DbService.instance.renameSite(oldSite, newSite);
      await OverlayStore.rename(oldSite, newSite);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final editing = widget.project != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(editing
              ? tr('프로젝트 수정', 'Edit project')
              : tr('새 프로젝트', 'New project'))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            Text(
                tr('조사지 정보는 최초 1회만 입력합니다. 이후 조사목은 지도 화면의 조사목 추가 버튼으로 번호가 자동 부여됩니다.',
                    'Site details are entered once. Trees are then added from the map with automatic numbering.'),
                style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5)),
            _label(p, tr('조사지명', 'Site name'), required: true),
            TextFormField(
              controller: _site,
              decoration: InputDecoration(
                  hintText: tr('예: 인제 남면 3-2 임반',
                      'e.g. Inje Nam-myeon compartment 3-2')),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('필수 항목입니다', 'Required')
                  : null,
            ),
            _label(p, tr('위치', 'Location')),
            TextFormField(
              controller: _loc,
              decoration: InputDecoration(
                  hintText: tr('강원 인제군 남면', 'Nam-myeon, Inje-gun, Gangwon')),
            ),
            _label(p, tr('다음 조사목 번호', 'Next tree number')),
            TextFormField(
              controller: _seq,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: '1',
                  helperText: tr('이 번호부터 자동 부여되며 이미 사용한 번호는 건너뜁니다',
                      'Assigned from this number, skipping IDs already used')),
            ),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _save,
              child: Text(editing
                  ? tr('저장', 'Save')
                  : tr('프로젝트 생성', 'Create project')),
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
