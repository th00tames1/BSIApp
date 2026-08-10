import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../theme.dart';
import 'register_screen.dart';

/// Project picker/manager: create, select, edit, or delete 조사지 projects.
/// Selecting one makes it active and returns to the map.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  Future<void> _new() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const ProjectScreen()));
    if (ok == true && mounted) Navigator.pop(context, true); // new → active → map
  }

  Future<void> _edit(Project p) async {
    await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => ProjectScreen(project: p)));
    if (mounted) setState(() {});
  }

  void _select(Project p) {
    selectProject(p.site);
    Navigator.pop(context, true);
  }

  Future<void> _delete(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('프로젝트 삭제', 'Delete project')),
        content: Text(tr(
          '"${p.site}" 프로젝트를 목록에서 지웁니다.\n(저장된 조사목 기록은 그대로 남습니다.)',
          'Removes "${p.site}" from the project list.\n(Saved tree records are kept.)',
        )),
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
    if (ok == true) {
      deleteProject(p.site);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('프로젝트', 'Projects')),
        actions: [
          IconButton(
              tooltip: tr('새 프로젝트', 'New project'),
              onPressed: _new,
              icon: const Icon(Icons.add)),
        ],
      ),
      body: ValueListenableBuilder<List<Project>>(
        valueListenable: projects,
        builder: (_, list, __) {
          if (list.isEmpty) return _empty(p);
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _tile(p, list[i]),
          );
        },
      ),
    );
  }

  Widget _empty(AppPalette p) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open_outlined, size: 56, color: p.muted),
          const SizedBox(height: 12),
          Text(tr('프로젝트가 없습니다', 'No projects yet'),
              style: TextStyle(color: p.muted)),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: ElevatedButton.icon(
                onPressed: _new,
                icon: const Icon(Icons.add),
                label: Text(tr('새 프로젝트', 'New project'))),
          ),
        ]),
      );

  Widget _tile(AppPalette p, Project proj) {
    final active = proj.site == activeSite.value;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _select(proj),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: (active ? p.green : p.navy).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(active ? Icons.check_circle : Icons.local_fire_department_outlined,
                  color: active ? p.green : p.navy),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(proj.site,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  tr(
                    '${proj.location.isEmpty ? '' : '${proj.location} · '}조사목 ${proj.treeSeq}${active ? ' · 사용 중' : ''}',
                    '${proj.location.isEmpty ? '' : '${proj.location} · '}Trees ${proj.treeSeq}${active ? ' · Active' : ''}',
                  ),
                  style: TextStyle(fontSize: 12, color: p.muted, fontFamily: 'monospace'),
                ),
              ]),
            ),
            IconButton(
                tooltip: tr('수정', 'Edit'),
                onPressed: () => _edit(proj),
                icon: Icon(Icons.edit_outlined, size: 20, color: p.muted)),
            IconButton(
                tooltip: tr('삭제', 'Delete'),
                onPressed: () => _delete(proj),
                icon: Icon(Icons.delete_outline, size: 20, color: p.danger)),
          ]),
        ),
      ),
    );
  }
}
