import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/draft.dart';
import '../models/geo_shape.dart';
import '../models/survey.dart';
import '../services/db_service.dart';
import '../services/geo_import.dart';
import '../services/location_service.dart';
import '../services/overlay_store.dart';
import '../services/tile_cache.dart';
import '../theme.dart';
import 'capture_screen.dart';
import 'projects_screen.dart';
import 'records_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

/// Map home: basemap (일반/위성) with verdict-coloured survey pins for the
/// active project, plus optional imported boundary overlays (SHP/KML/GeoJSON).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  // Modifiable headers: flutter_map calls headers.putIfAbsent() which throws on
  // a const/unmodifiable map. Kept as a field so it isn't rebuilt each frame.
  final _tiles =
      CachedTileProvider(headers: {'User-Agent': 'edu.oregonstate.afs.bsi_field'});
  // Separate providers for the hybrid reference layers (flutter_map mutates
  // each provider's header map).
  final _roadTiles =
      CachedTileProvider(headers: {'User-Agent': 'edu.oregonstate.afs.bsi_field'});
  final _labelTiles =
      CachedTileProvider(headers: {'User-Agent': 'edu.oregonstate.afs.bsi_field'});
  List<SurveyRecord> _records = [];
  List<GeoShape> _overlays = [];
  LatLng? _here; // last "my location" fix
  SurveyDraft? _resume; // in-progress survey to continue

  // 국립산림과학원(서울 동대문구) — 좌표 없는 기본 중심.
  static const _fallback = LatLng(37.5936, 127.0400);

  /// 최초 1회 현재 위치로 이동했는지.
  bool _didInitialLocate = false;

  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  // Hybrid = imagery + transparent reference layers (roads, then place labels).
  static const _satUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _satRoadsUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';
  static const _satLabelsUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  String get _overlayKey => hasProject ? projectSite.value! : '_global';

  @override
  void initState() {
    super.initState();
    _refreshResume();
    _load();
    _loadOverlays();
    _initialLocate();
  }

  /// 앱을 열면 기본 중심(국립산림과학원)에서 시작하되, 위치가 잡히면
  /// **한 번만** 현재 위치로 옮긴다. 이후에는 사용자가 움직인 화면을 지킨다.
  Future<void> _initialLocate() async {
    if (_didInitialLocate) return;
    final pos = await LocationService.current();
    if (!mounted || pos == null) return;
    _didInitialLocate = true;
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _here = here);
    _map.move(here, 16);
  }

  void _refreshResume() {
    final j = loadDraftJson();
    final d = j == null ? null : SurveyDraft.fromJsonString(j);
    _resume = (d != null && d.isInProgress) ? d : null;
  }

  Future<void> _loadOverlays() async {
    final o = await OverlayStore.load(_overlayKey);
    if (mounted) setState(() => _overlays = o);
  }

  Future<void> _load() async {
    final r = await DbService.instance.all();
    if (!mounted) return;
    setState(() => _records = r);
    final pts = _coords(_visible);
    if (pts.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _map.fitCamera(
          CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(64)),
        );
      });
    } else if (pts.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _map.move(pts.first, 15);
      });
    }
  }

  // Only the active project's trees (all trees when no project is active).
  List<SurveyRecord> get _visible => hasProject
      ? _records.where((r) => r.site == projectSite.value).toList()
      : _records;

  List<LatLng> _coords(List<SurveyRecord> rs) => [
        for (final r in rs)
          if (r.lat != null && r.lon != null) LatLng(r.lat!, r.lon!)
      ];

  bool _isCut(SurveyRecord r) => r.verdict == '벌채';

  String? _thumbPath(SurveyRecord r) {
    for (final f in r.faces) {
      final path = f.overlayPath ?? f.imagePath;
      if (path != null && File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _openProjects() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ProjectsScreen()));
    if (!mounted) return;
    setState(() {});
    _load();
    _loadOverlays();
  }

  Future<void> _newTree() async {
    final draft = SurveyDraft()
      ..treeId = nextTreeSeq().toString().padLeft(3, '0')
      ..site = projectSite.value ?? ''
      ..address = projectLocation.value;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(draft: draft)));
    if (!mounted) return;
    _refreshResume();
    _load(); // refresh pins after a tree is saved
    // 시연 모드의 마지막 단계: 방금 자동 저장된 조사를 기록 리스트로 보여준다.
    if (demoTourSaved) {
      demoTourSaved = false;
      await Future.delayed(const Duration(milliseconds: 1100));
      if (mounted) _openRecords();
    }
  }

  Future<void> _resumeSurvey() async {
    final d = _resume;
    if (d == null) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(draft: d)));
    if (!mounted) return;
    _refreshResume();
    _load();
  }

  void _discardResume() {
    clearDraft();
    setState(() => _resume = null);
  }

  Future<void> _locate() async {
    _didInitialLocate = true;   // 수동으로 눌렀으면 자동 이동은 더 필요 없다
    final pos = await LocationService.current();
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(
                tr('현재 위치를 가져올 수 없습니다', 'Cannot get current location'))));
      return;
    }
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _here = here);
    _map.move(here, 16);
  }

  void _openRecords() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RecordsScreen()));
    if (mounted) _load();
  }

  void _openSettings() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SettingsScreen()));

  // ---- basemap / boundary overlays ----
  void _openLayers() {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('지도 유형', 'Map type'),
                  style: TextStyle(
                      color: p.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _MapTypeCard(
                  label: tr('일반', 'Standard'),
                  icon: Icons.map_outlined,
                  selected: !satelliteBasemap.value,
                  onTap: () {
                    setSatelliteBasemap(false);
                    setSheet(() {});
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MapTypeCard(
                  label: tr('위성', 'Satellite'),
                  icon: Icons.satellite_alt_outlined,
                  selected: satelliteBasemap.value,
                  onTap: () {
                    setSatelliteBasemap(true);
                    setSheet(() {});
                    setState(() {});
                  },
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('조사지 경계', 'Site boundary'),
                  style: TextStyle(
                      color: p.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Icon(Icons.layers_outlined, size: 20, color: p.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _overlays.isEmpty
                          ? tr('불러온 경계 없음', 'No boundary loaded')
                          : tr('${_overlays.length}개 도형',
                              '${_overlays.length} shapes'),
                      style: TextStyle(fontSize: 13.5, color: p.muted),
                    ),
                  ),
                  if (_overlays.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await OverlayStore.clear(_overlayKey);
                        if (!mounted) return;
                        setState(() => _overlays = []);
                        setSheet(() {});
                      },
                      child:
                          Text(tr('지우기', 'Clear'), style: TextStyle(color: p.danger)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _importBoundary();
                },
                icon: const Icon(Icons.upload_file, size: 20),
                label: Text(tr('경계 파일 불러오기', 'Import boundary file')),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                tr('SHP(.shp+.prj 또는 .zip) · KML/KMZ · GeoJSON',
                    'SHP (.shp+.prj or .zip) · KML/KMZ · GeoJSON'),
                style: TextStyle(fontSize: 11.5, color: p.muted)),
          ]),
        ),
      ),
    );
  }

  Future<void> _importBoundary() async {
    final res = await FilePicker.pickFiles(
        allowMultiple: true,
        dialogTitle: tr('조사지 경계 파일 선택', 'Select site boundary files'));
    if (res == null || !mounted) return;
    final paths = res.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    List<GeoShape> shapes;
    try {
      shapes = await GeoImport.load(paths);
    } on NeedsCrsException {
      if (!mounted) return;
      final crs = await _askCrs();
      if (crs == null || !mounted) return;
      try {
        shapes = await GeoImport.load(paths, crsOverride: crs);
      } catch (e) {
        _toast(tr('불러오기 실패: $e', 'Import failed: $e'));
        return;
      }
    } catch (e) {
      _toast(tr('불러오기 실패: $e', 'Import failed: $e'));
      return;
    }

    if (shapes.isEmpty) {
      _toast(tr('도형을 찾지 못했습니다', 'No shapes found'));
      return;
    }
    final merged = [..._overlays, ...shapes];
    await OverlayStore.save(_overlayKey, merged);
    if (!mounted) return;
    setState(() => _overlays = merged);
    _toast(tr('경계 ${shapes.length}개를 불러왔습니다',
        'Imported ${shapes.length} boundaries'));

    final pts = [for (final s in shapes) ...s.points];
    if (pts.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _map.fitCamera(
            CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48)));
      });
    }
  }

  /// Shapefiles without a readable .prj need the surveyor to name the CRS.
  Future<String?> _askCrs() {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(tr('좌표계를 선택하세요', 'Select a coordinate system')),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
                tr('.prj 파일이 없거나 인식할 수 없습니다.',
                    'No .prj file, or it could not be read.'),
                style: TextStyle(fontSize: 12.5, color: context.palette.muted)),
          ),
          for (final e in GeoImport.crsLabels.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.key),
              child: Text(e.value, style: const TextStyle(fontSize: 13.5)),
            ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openSheet(SurveyRecord r) {
    final p = context.palette;
    final cut = _isCut(r);
    final thumb = _thumbPath(r);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            // 예시 이미지(썸네일) — 없으면 아이콘
            if (thumb != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(thumb),
                    width: 58, height: 58, fit: BoxFit.cover),
              )
            else
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                    color: (cut ? p.danger : p.green).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.park_outlined, color: cut ? p.danger : p.green),
              ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('조사목 ${r.treeId}', 'Tree ${r.treeId}'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(r.site.isEmpty ? '—' : r.site,
                    style: TextStyle(fontSize: 12.5, color: p.muted)),
              ]),
            ),
            _Verdict(r.verdict),
          ]),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _sheetRow(
                    Icons.local_fire_department_outlined,
                    tr('통합 BSI', 'Overall BSI'),
                    r.bsi.isNaN ? '–' : r.bsi.toStringAsFixed(2),
                    p),
                Divider(height: 1, color: p.line),
                _sheetRow(Icons.warning_amber_rounded, tr('고사 확률', 'Mortality'),
                    r.mortalityProb.isNaN ? '–' : '${(r.mortalityProb * 100).round()}%', p),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SavedScreen(record: r)));
                if (mounted) _load();
              },
              child: Text(tr('상세 보기', 'View details')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sheetRow(IconData ic, String label, String value, AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Icon(ic, size: 20, color: p.green),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: p.muted))),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 15.5, fontWeight: FontWeight.w700)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    // The map outlives a language switch (설정 is pushed on top of it), so it
    // has to rebuild its own strings when the language changes.
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLang,
      builder: (context, _, __) => _buildMap(context),
    );
  }

  Widget _buildMap(BuildContext context) {
    final p = context.palette;
    final visible = _visible;
    final pins = visible.where((r) => r.lat != null && r.lon != null).toList();
    final cutCount = visible.where(_isCut).length;
    // With no project yet, the header is the call to action, not a map label.
    final title = hasProject ? projectSite.value! : tr('새 프로젝트', 'New project');
    final sat = satelliteBasemap.value;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _coords(visible).isNotEmpty ? _coords(visible).first : _fallback,
            initialZoom: 14,
            minZoom: 3,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              key: ValueKey(sat), // force a reload when the basemap switches
              urlTemplate: sat ? _satUrl : _osmUrl,
              userAgentPackageName: 'edu.oregonstate.afs.bsi_field',
              tileProvider: _tiles,
              maxNativeZoom: 19,
            ),
            // Hybrid: roads + place names over the imagery.
            if (sat) ...[
              TileLayer(
                urlTemplate: _satRoadsUrl,
                userAgentPackageName: 'edu.oregonstate.afs.bsi_field',
                tileProvider: _roadTiles,
                maxNativeZoom: 19,
              ),
              TileLayer(
                urlTemplate: _satLabelsUrl,
                userAgentPackageName: 'edu.oregonstate.afs.bsi_field',
                tileProvider: _labelTiles,
                maxNativeZoom: 19,
              ),
            ],
            if (_overlays.any((s) => s.polygon))
              PolygonLayer(
                polygons: [
                  for (final s in _overlays.where((s) => s.polygon))
                    Polygon(
                      points: s.points,
                      color: p.ember.withValues(alpha: 0.12),
                      borderColor: p.ember,
                      borderStrokeWidth: 2.2,
                    ),
                ],
              ),
            if (_overlays.any((s) => !s.polygon))
              PolylineLayer(
                polylines: [
                  for (final s in _overlays.where((s) => !s.polygon))
                    Polyline(points: s.points, color: p.ember, strokeWidth: 2.6),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final r in pins)
                  Marker(
                    point: LatLng(r.lat!, r.lon!),
                    width: 96,
                    height: 62,
                    alignment: Alignment.bottomCenter,
                    child: _Pin(
                        cut: _isCut(r),
                        label: r.treeId,
                        onTap: () => _openSheet(r)),
                  ),
                if (_here != null)
                  Marker(
                    point: _here!,
                    width: 24,
                    height: 24,
                    child: const _HereDot(),
                  ),
              ],
            ),
            // 거리 범례 — 좌하단, 출처 표기 위에 겹치지 않게 작게
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 34),
              child: Scalebar(
                alignment: Alignment.bottomLeft,
                length: ScalebarLength.s,
                strokeWidth: 2,
                lineHeight: 5,
                lineColor: sat ? Colors.white : const Color(0xFF3C4655),
                textStyle: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: sat ? Colors.white : const Color(0xFF3C4655),
                  shadows: sat
                      ? const [Shadow(color: Colors.black54, blurRadius: 3)]
                      : null,
                ),
              ),
            ),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution(sat
                    ? 'Esri, Maxar, Earthstar Geographics'
                    : 'OpenStreetMap contributors'),
              ],
            ),
          ],
        ),

        // ---- top: 조사지명 (tap → 프로젝트 목록) + 기록·설정 + 이어서 조사 ----
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _openProjects,
                    child: _Glass(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(
                              child: Text(title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.unfold_more, size: 16, color: p.muted),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                              hasProject
                                  ? tr('조사목 ${visible.length} · 벌채 $cutCount',
                                      'Trees ${visible.length} · Fell $cutCount')
                                  : tr('탭하여 조사지를 등록하세요', 'Tap to add a site'),
                              style: TextStyle(
                                  fontFamily: 'monospace', fontSize: 11.5, color: p.muted)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                _TopBtn(icon: Icons.history, onTap: _openRecords),
                const SizedBox(width: 9),
                _TopBtn(icon: Icons.tune, onTap: _openSettings),
              ]),
              if (_resume != null) ...[
                const SizedBox(height: 10),
                _ResumeBanner(
                  draft: _resume!,
                  onResume: _resumeSurvey,
                  onDiscard: _discardResume,
                ),
              ],
            ]),
          ),
        ),

        // ---- right rail: 레이어 · 내 위치 ----
        SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _TopBtn(icon: Icons.layers_outlined, onTap: _openLayers),
                const SizedBox(height: 10),
                _TopBtn(icon: Icons.my_location, onTap: _locate),
              ]),
            ),
          ),
        ),

        // ---- bottom: + (no project) / tree (project set) ----
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _Fab(
                icon: hasProject ? Icons.park : Icons.add,
                label: hasProject
                    ? tr('조사목 추가', 'Add tree')
                    : tr('새 프로젝트', 'New project'),
                onTap: hasProject ? _newTree : _openProjects,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- pieces ----------

class _MapTypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _MapTypeCard(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? p.navy.withValues(alpha: 0.10) : p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? p.navy : p.line, width: selected ? 1.8 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? p.navy : p.muted),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? p.navy : p.muted)),
        ]),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  final bool cut;
  final String label;
  final VoidCallback onTap;
  const _Pin({required this.cut, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = cut ? p.danger : p.green;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withValues(alpha: 0.6)),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: p.ink)),
        ),
        const SizedBox(height: 1),
        Icon(Icons.location_on,
            size: 38,
            color: c,
            shadows: const [
              Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 2))
            ]),
      ]),
    );
  }
}

class _HereDot extends StatelessWidget {
  const _HereDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2F7DF6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  final SurveyDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  const _ResumeBanner(
      {required this.draft, required this.onResume, required this.onDiscard});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.ember.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(children: [
        Icon(Icons.play_circle_outline, color: p.ember, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('이어서 조사', 'Resume survey'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 1),
            Text(
                tr('조사목 ${draft.treeId} · ${draft.photos.length}/4 촬영',
                    'Tree ${draft.treeId} · ${draft.photos.length}/4 captured'),
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: p.muted)),
          ]),
        ),
        TextButton(onPressed: onDiscard, child: Text(tr('삭제', 'Delete'))),
        FilledButton(
          onPressed: onResume,
          style: FilledButton.styleFrom(
              backgroundColor: p.navy,
              foregroundColor: p.onNavy,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38)),
          child: Text(tr('이어하기', 'Resume')),
        ),
      ]),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

class _TopBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface.withValues(alpha: 0.9),
      shape: CircleBorder(side: BorderSide(color: p.line)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black45,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 22, color: p.ink)),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Fab({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: p.navy,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        elevation: 6,
        shadowColor: p.navy.withValues(alpha: 0.6),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 66, height: 66, child: Icon(icon, size: 32, color: p.onNavy)),
        ),
      ),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line)),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
      ),
    ]);
  }
}

class _Verdict extends StatelessWidget {
  final String verdict;
  const _Verdict(this.verdict);
  @override
  Widget build(BuildContext context) {
    if (verdict.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final cut = verdict == '벌채';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
          color: (cut ? p.danger : p.green).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(verdictLabel(verdict),
          style: TextStyle(
              color: cut ? p.danger : p.green,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }
}
