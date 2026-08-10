import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as pp;
import 'package:path_provider/path_provider.dart';

import '../l10n.dart';
import '../models/draft.dart';
import '../models/survey.dart';
import '../services/analysis_service.dart';
import '../services/csv_export.dart';
import '../services/db_service.dart';
import '../services/mortality.dart';
import '../services/onnx_service.dart';
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
  late SurveyRecord record = widget.record;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  // ── 계측값: 레코드에 수정값이 있으면 그것을, 없으면 방위별 최대값 ──
  // (같은 규칙을 CSV도 쓰므로 로직은 SurveyRecord에 있다)
  double get _heightM => record.effectiveHeightM;
  double get _sootM => record.effectiveSootMaxM;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 수정값을 DB에 반영하고 화면을 갱신한다.
  Future<void> _apply(SurveyRecord next) async {
    await DbService.instance.update(next);
    if (mounted) setState(() => record = next);
  }

  // ── 이미지 재분석 ────────────────────────────────────────────────
  //
  // BSI는 방위별 Σ(그을음 높이 × 그을음 면적비)라서 저장된 스칼라 하나를 고쳐서는
  // 되돌릴 수 없다. 대신 저장해 둔 사진을 같은 모델로 다시 돌려 방위별 값부터
  // 새로 얻는다. 입력(사진·모델·수고봉 길이)이 같으면 결과도 같다.
  Future<void> _reanalyse() async {
    final shots =
        record.faces.where((f) => f.imagePath != null).toList(growable: false);
    if (shots.isEmpty) {
      _snack(tr('저장된 촬영 사진이 없어 다시 분석할 수 없습니다',
          'No stored photos to re-analyse'));
      return;
    }
    final missing =
        shots.where((f) => !File(f.imagePath!).existsSync()).toList();
    if (missing.isNotEmpty) {
      _snack(tr('사진 파일 ${missing.length}장을 찾을 수 없어 다시 분석할 수 없습니다',
          '${missing.length} photo file(s) missing — cannot re-analyse'));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('이미지 다시 분석', 'Re-analyse images')),
        content: Text(tr(
            '저장된 ${shots.length}장을 같은 모델로 다시 분석해 방위별 계측값과 통합 BSI를 '
                '새로 계산합니다.\n\n손으로 고친 수고·그을음 높이는 분석값으로 되돌아갑니다. '
                '흉고직경은 그대로 두고 고사 확률만 다시 판정합니다.',
            'Re-runs the same model on the ${shots.length} stored photos and '
                'recomputes the per-azimuth measurements and the integrated BSI.\n\n'
                'Manually edited tree/char heights revert to the analysed values. '
                'DBH is kept; only the mortality verdict is recomputed.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('취소', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('다시 분석', 'Re-analyse'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final progress = ValueNotifier<String>(tr('모델 불러오는 중', 'Loading model'));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(message: progress),
    );

    String? err;
    SurveyRecord? next;
    try {
      await OnnxService.instance.load(SurveyDraft.defaultModelAsset);
      // 수고봉 모델은 있으면 쓰고 없으면 휴리스틱으로 내려간다(분석 화면과 동일).
      await OnnxService.pole.tryLoad(SurveyDraft.defaultPoleModelAsset);
      final dir = await getApplicationDocumentsDirectory();
      final overlayDir = Directory(pp.join(dir.path, 'overlays'));
      if (!overlayDir.existsSync()) overlayDir.createSync(recursive: true);

      final fresh = <AzimuthResult>[];
      for (int i = 0; i < shots.length; i++) {
        final f = shots[i];
        progress.value = tr(
            '${azimuthLabelFromCode(f.azimuth)} 분석 중 · ${i + 1}/${shots.length}',
            'Analyzing ${azimuthLabelFromCode(f.azimuth)} · ${i + 1}/${shots.length}');
        final outPath = pp.join(
            overlayDir.path, '${record.treeId}_${f.azimuth}_overlay.png');
        fresh.add(await AnalysisService.instance.analyzeFace(
          f.azimuth,
          f.imagePath!,
          poleLengthM: record.poleLengthM,
          overlayOutPath: outPath,
        ));
        // 같은 경로에 덮어쓰므로 캐시를 비워야 새 오버레이가 보인다.
        await FileImage(File(outPath)).evict();
      }

      final integ = AnalysisService.instance.integrate(fresh, record.dbhCm);
      next = record.copyWith(
        faces: fresh,
        bsi: integ.bsi,
        mortalityProb: integ.mortality,
        verdict: integ.verdict,
        // 손으로 고친 값은 버리고 분석값이 다시 보이게 한다.
        heightM: double.nan,
        sootMaxM: double.nan,
      );
    } catch (e) {
      err = '$e';
    }

    if (!mounted) return;
    Navigator.pop(context); // 진행 다이얼로그
    progress.dispose();
    if (err != null) {
      _snack(tr('다시 분석 실패: $err', 'Re-analysis failed: $err'));
      return;
    }
    await _apply(next!);
    if (!mounted) return;
    setState(() {
      _page = 0;
      if (_pager.hasClients) _pager.jumpToPage(0);
    });
    _snack(tr('다시 분석했습니다', 'Re-analysed'));
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

  // ── 항목 수정 ────────────────────────────────────────────────────
  Future<void> _editSpecies() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final s in majorSpecies)
            ListTile(
              dense: true,
              leading: Icon(
                  s == record.species
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20),
              title: Text(speciesLabel(s)),
              onTap: () => Navigator.pop(context, s),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.edit_outlined, size: 20),
            title: Text(tr('직접 입력', 'Enter manually')),
            onTap: () => Navigator.pop(context, '__custom__'),
          ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    var species = v;
    if (v == '__custom__') {
      final t = await _askText(tr('수종 입력', 'Species'), record.species);
      if (t == null || t.isEmpty) return;
      species = t;
    }
    await _apply(record.copyWith(species: species));
  }

  /// 숫자 항목 수정. [onValue]가 새 레코드를 만든다.
  /// [decimals]는 화면 표시 자릿수와 맞춰야 한다 — 프리필이 더 짧으면
  /// 값을 안 바꾸고 확인만 눌러도 반올림된 값이 저장된다.
  Future<void> _editNumber(String title, double current, String unit,
      SurveyRecord Function(double v) onValue,
      {int decimals = 1, String? note}) async {
    final t = await _askText(
        title, current.isNaN ? '' : current.toStringAsFixed(decimals),
        number: true, unit: unit, note: note);
    if (t == null) return;
    final v = double.tryParse(t);
    if (v == null || v < 0) return;
    await _apply(onValue(v));
  }

  /// GPS 좌표 수정 — 위도·경도를 함께 입력받는다. 수정하면 지도 핀도
  /// 이 좌표로 옮겨진다(지도는 기록을 다시 읽어 그린다).
  /// 두 칸을 모두 비우면 좌표를 지운다(핀 제거).
  Future<void> _editGps() async {
    final res = await showDialog<({String lat, String lon})>(
      context: context,
      builder: (_) => _GpsDialog(lat: record.lat, lon: record.lon),
    );
    if (res == null || !mounted) return;
    if (res.lat.isEmpty && res.lon.isEmpty) {
      await _apply(record.copyWith(clearGps: true));
      return;
    }
    final lat = double.tryParse(res.lat);
    final lon = double.tryParse(res.lon);
    if (lat == null || lon == null) {
      _snack(tr('위도·경도를 모두 숫자로 입력하세요 (두 칸을 비우면 좌표 삭제)',
          'Enter both latitude and longitude as numbers (clear both to remove)'));
      return;
    }
    if (lat.abs() > 90 || lon.abs() > 180) {
      _snack(tr('좌표 범위가 올바르지 않습니다 (위도 ±90, 경도 ±180)',
          'Out of range (lat ±90, lon ±180)'));
      return;
    }
    await _apply(record.copyWith(lat: lat, lon: lon));
  }

  // 다이얼로그가 컨트롤러를 소유해야 닫힘 애니메이션 중 참조·누수가 없다.
  Future<String?> _askText(String title, String initial,
          {bool number = false, String? unit, String? note}) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TextInputDialog(
            title: title, initial: initial, number: number, unit: unit, note: note),
      );

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
            tooltip: tr('이미지 다시 분석', 'Re-analyse images'),
            onPressed: _reanalyse,
            icon: const Icon(Icons.refresh),
          ),
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
      // 앱이 화면 전체를 쓰므로 SafeArea가 없으면 마지막 행(GPS 좌표)이
      // 네비게이션 바 뒤에 깔려 눌리지 않는다.
      body: SafeArea(
        top: false,
        child: ListView(
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
          // 판정 결과 — 분석에서 나온 값이라 수정하지 않는다.
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
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // 조사 정보 — 항목을 누르면 수정할 수 있다.
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _row(p, Icons.forest_outlined, tr('수종', 'Species'),
                    record.species.isEmpty ? '–' : speciesLabel(record.species),
                    onTap: _editSpecies),
                Divider(height: 1, color: p.line),
                _row(p, Icons.straighten, tr('흉고직경', 'DBH'),
                    record.dbhCm == 0
                        ? '–'
                        : '${record.dbhCm.toStringAsFixed(1)} cm', onTap: () {
                  _editNumber(tr('흉고직경', 'DBH'), record.dbhCm, 'cm', (v) {
                    // DBH가 바뀌면 판정표에서 고사 확률·판정을 다시 읽는다.
                    return record.copyWith(
                      dbhCm: v,
                      mortalityProb: Mortality.probability(record.bsi, v),
                      verdict: Mortality.verdict(record.bsi, v),
                    );
                  });
                }),
                Divider(height: 1, color: p.line),
                _row(p, Icons.height, tr('수고', 'Tree height'),
                    _heightM.isNaN ? '–' : '${_heightM.toStringAsFixed(2)} m',
                    onTap: () {
                  _editNumber(tr('수고', 'Tree height'), _heightM, 'm',
                      (v) => record.copyWith(heightM: v),
                      decimals: 2,
                      note: tr('기록·CSV용 값으로, 통합 BSI에는 반영되지 않습니다. '
                          'BSI까지 새로 계산하려면 상단의 다시 분석을 쓰세요.',
                          'Stored for the record and CSV; does not change the BSI. '
                              'Use Re-analyse above to recompute the BSI.'));
                }),
                Divider(height: 1, color: p.line),
                _row(p, Icons.local_fire_department_outlined,
                    tr('그을음 높이', 'Char height'),
                    _sootM.isNaN ? '–' : '${_sootM.toStringAsFixed(2)} m',
                    onTap: () {
                  _editNumber(tr('그을음 높이', 'Char height'), _sootM, 'm',
                      (v) => record.copyWith(sootMaxM: v),
                      decimals: 2,
                      note: tr('기록·CSV용 값으로, 통합 BSI에는 반영되지 않습니다. '
                          'BSI까지 새로 계산하려면 상단의 다시 분석을 쓰세요.',
                          'Stored for the record and CSV; does not change the BSI. '
                              'Use Re-analyse above to recompute the BSI.'));
                }),
                Divider(height: 1, color: p.line),
                _row(
                    p,
                    Icons.place_outlined,
                    tr('GPS 좌표', 'GPS'),
                    (record.lat == null || record.lon == null)
                        ? '–'
                        : '${record.lat!.toStringAsFixed(5)}, ${record.lon!.toStringAsFixed(5)}',
                    onTap: _editGps),
              ]),
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// 결과 사진을 표 위에 바로 띄우고 옆으로 넘겨 본다.
  /// 각 장에 방위와 그을음 비율을 함께 표시한다.
  Widget _photoPager(AppPalette p, List<AzimuthResult> faces) {
    final h = math.min(math.max(
        MediaQuery.of(context).size.height * 0.38, 240.0), 420.0);
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
                // 페이저는 cover라 위아래가 잘린다 — 탭하면 전체 프레임(contain)
                // + 핀치 줌으로 본다.
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _FullPhotoScreen(faces: faces, initial: i))),
                  child: Image.file(File(path), fit: BoxFit.cover),
                ),
                // 배지가 탭을 삼키면 그 자리만 전체 보기가 안 열린다 — 표시 전용.
                Positioned(
                  left: 10,
                  top: 10,
                  child: IgnorePointer(
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
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IgnorePointer(
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
  // 수정 가능한 행도 연필 표시 없이 값만 둔다 — 행을 누르면 편집된다.
  Widget _row(AppPalette p, IconData ic, String label, String value,
      {VoidCallback? onTap}) {
    final row = Padding(
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
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 재분석 진행 표시. 뒤로 가기로 닫히지 않게 PopScope로 막는다.
class _ProgressDialog extends StatelessWidget {
  final ValueListenable<String> message;
  const _ProgressDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: message,
              builder: (_, m, __) =>
                  Text(m, style: TextStyle(fontSize: 14, color: p.ink)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 한 줄 입력 다이얼로그. 컨트롤러를 State가 소유해 닫힐 때 확실히 해제한다.
class _TextInputDialog extends StatefulWidget {
  final String title;
  final String initial;
  final bool number;
  final String? unit;
  final String? note;
  const _TextInputDialog(
      {required this.title,
      required this.initial,
      this.number = false,
      this.unit,
      this.note});
  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      // 가로 화면에서 키보드가 올라오면 남는 높이가 모자라 넘친다 — 스크롤시킨다.
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            keyboardType: widget.number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(suffixText: widget.unit),
          ),
          if (widget.note != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.note!,
                  style: TextStyle(fontSize: 12, height: 1.4, color: p.muted)),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('취소', 'Cancel'))),
        TextButton(
            onPressed: () => Navigator.pop(context, _ctl.text.trim()),
            child: Text(tr('확인', 'OK'))),
      ],
    );
  }
}

/// GPS 입력 다이얼로그. 입력 문자열을 그대로 돌려주고 검증은 호출부가 한다.
class _GpsDialog extends StatefulWidget {
  final double? lat;
  final double? lon;
  const _GpsDialog({required this.lat, required this.lon});
  @override
  State<_GpsDialog> createState() => _GpsDialogState();
}

class _GpsDialogState extends State<_GpsDialog> {
  late final TextEditingController _latCtl =
      TextEditingController(text: widget.lat?.toStringAsFixed(6) ?? '');
  late final TextEditingController _lonCtl =
      TextEditingController(text: widget.lon?.toStringAsFixed(6) ?? '');

  @override
  void dispose() {
    _latCtl.dispose();
    _lonCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      title: Text(tr('GPS 좌표', 'GPS coordinates')),
      // 가로 화면에서 키보드가 올라오면 남는 높이가 모자라 넘친다 — 스크롤시킨다.
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _latCtl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('위도', 'Latitude')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lonCtl,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('경도', 'Longitude')),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                tr('두 칸을 모두 비우면 좌표를 지웁니다 (지도 핀 제거)',
                    'Clear both fields to remove the coordinates (map pin)'),
                style: TextStyle(fontSize: 12, height: 1.4, color: p.muted)),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('취소', 'Cancel'))),
        TextButton(
            onPressed: () => Navigator.pop(
                context, (lat: _latCtl.text.trim(), lon: _lonCtl.text.trim())),
            child: Text(tr('확인', 'OK'))),
      ],
    );
  }
}

/// 사진 전체 프레임 보기 — 페이저는 cover로 잘라 보여주므로
/// 원본 비율(contain) + 핀치 줌 경로를 따로 둔다.
class _FullPhotoScreen extends StatefulWidget {
  final List<AzimuthResult> faces;
  final int initial;
  const _FullPhotoScreen({required this.faces, required this.initial});
  @override
  State<_FullPhotoScreen> createState() => _FullPhotoScreenState();
}

class _FullPhotoScreenState extends State<_FullPhotoScreen> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  // 확대 상태에서는 페이지 스와이프를 꺼야 한 손가락 가로 끌기가 사진 이동이
  // 된다(켜두면 가로 제스처를 PageView가 항상 먼저 가져간다).
  final _tc = TransformationController();
  late int _i = widget.initial;
  bool _zoomed = false;

  @override
  void dispose() {
    _pc.dispose();
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.faces[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
            '${azimuthLabelFromCode(f.azimuth)} · ${_i + 1}/${widget.faces.length}',
            style: const TextStyle(fontSize: 15)),
      ),
      body: PageView.builder(
        controller: _pc,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        itemCount: widget.faces.length,
        onPageChanged: (i) => setState(() {
          _i = i;
          _tc.value = Matrix4.identity(); // 새 페이지는 원래 배율에서 시작
          _zoomed = false;
        }),
        itemBuilder: (_, i) {
          final face = widget.faces[i];
          final path = face.overlayPath ?? face.imagePath!;
          return InteractiveViewer(
            transformationController: _tc,
            maxScale: 6,
            onInteractionEnd: (_) {
              final z = _tc.value.getMaxScaleOnAxis() > 1.01;
              if (z != _zoomed) setState(() => _zoomed = z);
            },
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
