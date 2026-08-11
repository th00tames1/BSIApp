import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'services/geomag.dart';

/// App-wide state + preferences, persisted to disk (survives restarts).
/// Call [loadPrefs] once at startup before running the app.

// ── Project (한 조사지에서 여러 나무를 조사) ─────────────────────────
/// A survey project = one 조사지 with its own running tree counter.
class Project {
  String site; // 조사지명
  String location; // 위치(주소)
  int treeSeq; // 마지막 조사목 번호
  Project({required this.site, this.location = '', this.treeSeq = 0});

  Map<String, dynamic> toJson() =>
      {'site': site, 'location': location, 'treeSeq': treeSeq};
  factory Project.fromJson(Map<String, dynamic> j) => Project(
        site: j['site'] as String? ?? '',
        location: j['location'] as String? ?? '',
        treeSeq: (j['treeSeq'] as num?)?.toInt() ?? 0,
      );
}

/// All projects, and which one is active.
final ValueNotifier<List<Project>> projects = ValueNotifier([]);
final ValueNotifier<String?> activeSite = ValueNotifier(null);

// Active-project mirrors — read directly by map/capture screens.
final ValueNotifier<String?> projectSite = ValueNotifier(null); // 조사지명
final ValueNotifier<String> projectLocation = ValueNotifier(''); // 위치(주소)
final ValueNotifier<int> treeSeq = ValueNotifier(0); // 마지막 조사목 번호

Project? get activeProject {
  final s = activeSite.value;
  if (s == null) return null;
  for (final p in projects.value) {
    if (p.site == s) return p;
  }
  return null;
}

bool get hasProject => activeProject != null;

void _syncActive() {
  final p = activeProject;
  projectSite.value = p?.site;
  projectLocation.value = p?.location ?? '';
  treeSeq.value = p?.treeSeq ?? 0;
}

// ── Settings ────────────────────────────────────────────────────────
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);
final ValueNotifier<bool> showGuides = ValueNotifier(true);
/// Map basemap: false = 일반(OSM), true = 위성(Esri World Imagery).
final ValueNotifier<bool> satelliteBasemap = ValueNotifier(false);
/// 개발자 모드: 지도의 현재 위치 버튼을 7번 연속 누르면 켜지고/꺼진다.
/// 켜져 있어야만 설정의 시험 섹션(예시 사진 시험·시연 모드)이 보인다.
final ValueNotifier<bool> devMode = ValueNotifier(false);

/// 시연 모드: 조사목 추가 시 예시 사진이 북→동→남→서 순으로 자동 촬영되고
/// 분석 → 판정표 → 저장 → 조사 기록까지 손대지 않고 이어진다(영상 촬영용).
/// 개발자 모드가 꺼지면 함께 꺼진다.
final ValueNotifier<bool> demoMode = ValueNotifier(false);

/// 시연 모드에서 결과가 방금 자동 저장됐다는 1회성 신호. 지도 화면이 읽고
/// 조사 기록 화면을 이어서 연다(popUntil 뒤에는 결과 화면이 열 수 없다).
bool demoTourSaved = false;

/// 마지막으로 선택한 수종 — 같은 조사지는 대개 같은 수종이므로
/// 다음 조사목의 기본값으로 이어진다.
final ValueNotifier<String> lastSpecies = ValueNotifier('소나무');

/// 나침반이 가리키는 북쪽의 기준. 기본은 **진북** — 지도·좌표·야장이 쓰는 기준이다.
/// 촬영 화면의 나침반을 누르면 바뀐다(설정에서도 바꿀 수 있다).
final ValueNotifier<NorthRef> northRef = ValueNotifier(NorthRef.trueNorth);

SharedPreferences? _sp;

Future<void> loadPrefs() async {
  final sp = await SharedPreferences.getInstance();
  _sp = sp;

  // Projects list.
  final raw = sp.getString('projects');
  if (raw != null && raw.isNotEmpty) {
    try {
      projects.value = (jsonDecode(raw) as List)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      projects.value = [];
    }
  }
  activeSite.value = sp.getString('activeSite');

  // One-time migration from the old single-project keys, then drop them (and
  // set a flag) so deleting the last project can't resurrect it on relaunch.
  if (sp.getBool('migratedV2') != true) {
    if (projects.value.isEmpty) {
      final oldSite = sp.getString('projectSite');
      if (oldSite != null && oldSite.trim().isNotEmpty) {
        projects.value = [
          Project(
            site: oldSite,
            location: sp.getString('projectLocation') ?? '',
            treeSeq: sp.getInt('treeSeq') ?? 0,
          )
        ];
        activeSite.value = oldSite;
        _persistProjects();
      }
    }
    await sp.remove('projectSite');
    await sp.remove('projectLocation');
    await sp.remove('treeSeq');
    await sp.setBool('migratedV2', true);
  }
  // Drop a stale active pointer.
  if (activeSite.value != null && activeProject == null) {
    activeSite.value = projects.value.isNotEmpty ? projects.value.first.site : null;
  }
  _syncActive();

  themeMode.value =
      sp.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
  showGuides.value = sp.getBool('showGuides') ?? true;
  satelliteBasemap.value = sp.getBool('satelliteBasemap') ?? false;
  devMode.value = sp.getBool('devMode') ?? false;
  // 개발자 모드가 꺼져 있으면 시연 모드도 반드시 꺼진 상태로 시작한다.
  demoMode.value = devMode.value && (sp.getBool('demoMode') ?? false);
  lastSpecies.value = sp.getString('lastSpecies') ?? '소나무';
  northRef.value = NorthRef.values.firstWhere(
      (r) => r.name == sp.getString('northRef'),
      orElse: () => NorthRef.trueNorth);
  appLang.value = langFromCode(sp.getString('lang'));
}

void setAppLang(AppLang l) {
  appLang.value = l;
  _sp?.setString('lang', l.code);
}

void _persistProjects() {
  _sp?.setString('projects',
      jsonEncode(projects.value.map((p) => p.toJson()).toList()));
  final a = activeSite.value;
  if (a != null) {
    _sp?.setString('activeSite', a);
  } else {
    _sp?.remove('activeSite');
  }
}

/// Create a new project or edit [existing]; makes it the active project.
/// Returns false (no change) if [site] collides with a *different* project —
/// site doubles as the record join key, so it must stay unique.
bool upsertProject({
  Project? existing,
  required String site,
  required String location,
  int treeSeq = 0,
}) {
  site = site.trim();
  location = location.trim();
  final list = List<Project>.from(projects.value);
  if (list.any((p) => p.site == site && !identical(p, existing))) {
    return false; // duplicate 조사지명
  }
  Project target;
  if (existing != null && list.contains(existing)) {
    existing
      ..site = site
      ..location = location
      ..treeSeq = treeSeq;
    target = existing;
  } else {
    target = Project(site: site, location: location, treeSeq: treeSeq);
    list.add(target);
  }
  projects.value = list;
  activeSite.value = target.site;
  _syncActive();
  _persistProjects();
  return true;
}

void selectProject(String site) {
  activeSite.value = site;
  _syncActive();
  _sp?.setString('activeSite', site);
}

void deleteProject(String site) {
  final list = List<Project>.from(projects.value)
    ..removeWhere((p) => p.site == site);
  projects.value = list;
  if (activeSite.value == site) {
    activeSite.value = list.isNotEmpty ? list.first.site : null;
  }
  _syncActive();
  _persistProjects();
}

/// Next auto tree number for the active project (increments and persists).
int nextTreeSeq() {
  final p = activeProject;
  if (p == null) return 0;
  p.treeSeq += 1;
  projects.value = List.from(projects.value); // notify listeners
  treeSeq.value = p.treeSeq;
  _persistProjects();
  return p.treeSeq;
}

void setTreeSeq(int n) {
  final p = activeProject;
  if (p == null) return;
  p.treeSeq = n;
  projects.value = List.from(projects.value);
  treeSeq.value = n;
  _persistProjects();
}

// ── In-progress survey draft (resume after the app is closed/killed) ──
/// The active survey is auto-saved as JSON so a mid-field close/kill can be
/// resumed on next launch. Cleared when the survey is saved or discarded.
void saveDraftJson(String json) => _sp?.setString('activeDraft', json);
String? loadDraftJson() => _sp?.getString('activeDraft');
// Awaitable so the removal is durably flushed before we navigate away after a
// save — otherwise a kill in the flush window could re-arm the resume banner.
Future<void> clearDraft() async => await _sp?.remove('activeDraft');

// ── Settings ────────────────────────────────────────────────────────
void setThemeMode(ThemeMode m) {
  themeMode.value = m;
  _sp?.setString('theme', m == ThemeMode.dark ? 'dark' : 'light');
}

void setShowGuides(bool v) {
  showGuides.value = v;
  _sp?.setBool('showGuides', v);
}

void setSatelliteBasemap(bool v) {
  satelliteBasemap.value = v;
  _sp?.setBool('satelliteBasemap', v);
}

void setDemoMode(bool v) {
  demoMode.value = v;
  _sp?.setBool('demoMode', v);
}

void setDevMode(bool v) {
  devMode.value = v;
  _sp?.setBool('devMode', v);
  if (!v) setDemoMode(false); // 개발자 모드를 끄면 시연 모드도 끈다
}

void setLastSpecies(String s) {
  if (s.isEmpty) return;
  lastSpecies.value = s;
  _sp?.setString('lastSpecies', s);
}

void setNorthRef(NorthRef v) {
  northRef.value = v;
  _sp?.setString('northRef', v.name);
}
