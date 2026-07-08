import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/survey.dart';
import '../services/db_service.dart';
import '../services/tile_cache.dart';
import '../theme.dart';
import 'records_screen.dart';
import 'register_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

/// Scanniverse-style map home: real basemap with verdict-coloured survey pins,
/// a centre "+" to start a survey flanked by 기록 · 설정.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  List<SurveyRecord> _records = [];

  // 인제 남면 인근(좌표 없는 기록만 있을 때의 기본 중심)
  static const _fallback = LatLng(38.0612, 128.1705);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await DbService.instance.all();
    if (!mounted) return;
    setState(() => _records = r);
    final pts = _coords(r);
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

  List<LatLng> _coords(List<SurveyRecord> rs) => [
        for (final r in rs)
          if (r.lat != null && r.lon != null) LatLng(r.lat!, r.lon!)
      ];

  bool _isCut(SurveyRecord r) => r.verdict == '벌채';

  Future<void> _startSurvey() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
    _load(); // 새 조사 저장 시 핀 갱신
  }

  void _openSheet(SurveyRecord r) {
    final p = context.palette;
    final cut = _isCut(r);
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: (cut ? p.danger : p.green).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(Icons.park_outlined, color: cut ? p.danger : p.green),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.treeId,
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
                _sheetRow(Icons.local_fire_department_outlined, '통합 BSI',
                    r.bsi.isNaN ? '–' : r.bsi.toStringAsFixed(2), p),
                Divider(height: 1, color: p.line),
                _sheetRow(Icons.warning_amber_rounded, '고사 확률',
                    r.mortalityProb.isNaN ? '–' : '${(r.mortalityProb * 100).round()}%', p),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SavedScreen(record: r)));
              },
              child: const Text('상세 보기'),
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
    final p = context.palette;
    final pins = _records.where((r) => r.lat != null && r.lon != null).toList();
    final cutCount = _records.where(_isCut).length;
    final site = _records.isNotEmpty && _records.first.site.isNotEmpty
        ? _records.first.site
        : '조사 지도';

    return Scaffold(
      body: Stack(children: [
        // ---- basemap ----
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _coords(_records).isNotEmpty ? _coords(_records).first : _fallback,
            initialZoom: 14,
            minZoom: 3,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'edu.oregonstate.afs.bsi_field',
              tileProvider: CachedTileProvider(
                  headers: const {'User-Agent': 'edu.oregonstate.afs.bsi_field'}),
            ),
            MarkerLayer(
              markers: [
                for (final r in pins)
                  Marker(
                    point: LatLng(r.lat!, r.lon!),
                    width: 44,
                    height: 46,
                    // pin tip (bottom-centre of the icon) sits on the coordinate
                    alignment: Alignment.bottomCenter,
                    child: _Pin(cut: _isCut(r), onTap: () => _openSheet(r)),
                  ),
              ],
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),

        // ---- floating title ----
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: _Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_fire_department_outlined,
                          size: 17, color: p.ember),
                      const SizedBox(width: 7),
                      Text(site,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 3),
                    Text('조사목 ${_records.length} · 벌채 $cutCount',
                        style: TextStyle(
                            fontFamily: 'monospace', fontSize: 11.5, color: p.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ---- bottom dock: 기록 · + · 설정 ----
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _DockButton(
                    icon: Icons.history,
                    label: '기록',
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const RecordsScreen()));
                      _load();
                    },
                  ),
                  const SizedBox(width: 26),
                  _Fab(onTap: _startSurvey),
                  const SizedBox(width: 26),
                  _DockButton(
                    icon: Icons.tune,
                    label: '설정',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- pieces ----------

class _Pin extends StatelessWidget {
  final bool cut;
  final VoidCallback onTap;
  const _Pin({required this.cut, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Icon(Icons.location_on,
          size: 42,
          color: cut ? p.danger : p.green,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 2))]),
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

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DockButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: p.surface.withValues(alpha: 0.9),
        shape: CircleBorder(side: BorderSide(color: p.line)),
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: Colors.black45,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 24, color: p.ink)),
        ),
      ),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line)),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink)),
      ),
    ]);
  }
}

class _Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});
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
          child: SizedBox(width: 66, height: 66, child: Icon(Icons.add, size: 32, color: p.onNavy)),
        ),
      ),
      const SizedBox(height: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line)),
        child: Text('새 조사',
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
      child: Text(verdict,
          style: TextStyle(
              color: cut ? p.danger : p.green,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }
}
