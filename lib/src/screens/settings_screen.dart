import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../services/backup_service.dart';
import '../services/demo_sample.dart';
import '../services/geomag.dart';
import '../services/raw_archive.dart' show kAppVersion;
import '../services/update_service.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'analysis_screen.dart';
import 'bsi_table_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _checkingUpdate = false;

  static String _fmtGap(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  Future<void> _editPoleGap() async {
    final ctl = TextEditingController(text: _fmtGap(poleGapM.value));
    final t = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('수고봉 경계 간격', 'Pole band spacing')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'm'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                tr('수고봉의 인접 경계(색 띠) 사이 실제 거리입니다. 잘못 넣으면 모든 높이가 그 배율로 틀어집니다.',
                    'Real distance between adjacent bands on the pole. A wrong value scales every height by that factor.'),
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: context.palette.muted)),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('취소', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, ctl.text.trim()),
              child: Text(tr('확인', 'OK'))),
        ],
      ),
    );
    if (t == null || !mounted) return;
    final v = double.tryParse(t);
    if (v == null || v < 0.05 || v > 5) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(tr('0.05 ~ 5 m 사이로 입력하세요',
                'Enter a value between 0.05 and 5 m'))));
      return;
    }
    setState(() => setPoleGapM(v));
  }

  static String _size(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  /// 오래 걸리는 백업 작업을 진행률 창과 함께 돌린다. 실패하면 이유를 알린다.
  Future<T?> _withProgress<T>(
      String title, Future<T> Function(void Function(int, int)) job,
      {String Function(int done, int total)? label}) async {
    final prog = ValueNotifier<(int, int)>((0, 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: prog,
            builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: v.$2 == 0 ? null : v.$1 / v.$2),
              const SizedBox(height: 12),
              Text(v.$2 == 0
                  ? tr('준비 중…', 'Preparing…')
                  : label?.call(v.$1, v.$2) ??
                      tr('파일 ${v.$1} / ${v.$2}', 'File ${v.$1} / ${v.$2}')),
              const SizedBox(height: 6),
              Text(tr('앱을 닫지 마세요', 'Keep the app open'),
                  style: TextStyle(fontSize: 12, color: context.palette.muted)),
            ]),
          ),
        ),
      ),
    );
    T? result;
    Object? err;
    try {
      result = await job((d, t) => prog.value = (d, t));
    } catch (e) {
      err = e;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (err != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tr('실패', 'Failed')),
          content: Text('$err'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('확인', 'OK'))),
          ],
        ),
      );
    }
    return err == null ? result : null;
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body, style: const TextStyle(height: 1.45)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('취소', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  /// 이 폰의 전부(기록·사진·원시 데이터·조사지·설정)를 파일로 만든다.
  /// 안드로이드는 다운로드/BSI_backup에 바로 만들고(앱을 지워도 남는다), 원하면
  /// 공유 창으로 드라이브·Quick Share 등에 보낸다.
  Future<void> _exportBackup() async {
    final ok = await _confirm(
        tr('전체 백업 만들기', 'Create full backup'),
        tr('조사 기록 전부와 사진·원시 데이터(분석용 사진·촬영/분석 메타)·조사지·설정을 파일로 만듭니다.\n\n'
            '파일은 내장 저장공간 → Download → BSI_backup 에 생기고, 공유로 드라이브·다른 폰에 보낼 수도 있습니다. '
            '새 폰에서 설정 → 백업 불러오기를 누르면 그대로 이어서 조사할 수 있습니다.\n\n'
            '사진이 많으면 수 GB가 될 수 있고, 3.5 GB를 넘으면 여러 파일로 나뉩니다(모두 옮기세요).',
            'Packs every record, photo, raw data (analysis photos, capture/analysis metadata), site and setting into a file.\n\n'
            'Save it to Drive/Files or send it to the new phone, then use Settings → Import backup there.\n\n'
            'Large surveys can be several GB; above 3.5 GB the backup is split into parts — move all of them.'),
        tr('만들기', 'Create'));
    if (!ok || !mounted) return;
    final files = await _withProgress(tr('백업 만드는 중', 'Creating backup'),
        (cb) => BackupService.exportAll(onProgress: cb));
    if (files == null || !mounted) return;
    final size = files.fold<int>(0, (s, f) => s + f.lengthSync());
    final inDownloads = files.first.path.contains('/Download/');
    final share = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('백업 완료', 'Backup ready')),
        content: Text(
            [
              for (final f in files) '• ${f.uri.pathSegments.last}',
              tr('파일 ${files.length}개 · ${_size(size)}',
                  '${files.length} file(s) · ${_size(size)}'),
              '',
              inDownloads
                  ? tr('내장 저장공간 → Download → BSI_backup 에 저장했습니다. 앱을 지워도 남습니다(이전 백업도 그대로 둡니다).\n'
                      '새 폰으로는 이 파일을 옮긴 뒤 설정 → 백업 불러오기를 누르세요.',
                      'Saved to internal storage → Download → BSI_backup (kept even if the app is removed; older backups are left in place).\n'
                          'Move it to the new phone and use Settings → Import backup.')
                  : tr('앱 안에 만들었습니다. 공유로 드라이브·다른 폰에 꼭 옮겨 두세요 — 앱을 지우면 함께 지워집니다.',
                      'Created inside the app. Share it to Drive or another phone — it is deleted with the app.'),
            ].join('\n'),
            style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('확인', 'OK'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('공유하기', 'Share'))),
        ],
      ),
    );
    if (share != true || !mounted) return;
    await SharePlus.instance.share(ShareParams(
      text: tr('BSI 전체 백업 · 파일 ${files.length}개 · ${_size(size)}',
          'BSI full backup · ${files.length} file(s) · ${_size(size)}'),
      files: [for (final f in files) XFile(f.path)],
    ));
  }

  /// 다른 폰에서 만든 백업을 이 폰에 합친다. 이미 있는 기록·파일은 건너뛴다.
  Future<void> _importBackup() async {
    final res = await FilePicker.pickFiles(
        allowMultiple: true,
        dialogTitle: tr('백업 파일 선택 — 내장 저장공간 › Download › BSI_backup (조각이면 모두)',
            'Select backup file(s) (.zip — all parts)'));
    if (res == null || !mounted) return;
    final paths = [
      for (final f in res.files)
        if (f.path != null && f.path!.toLowerCase().endsWith('.zip')) f.path!
    ];
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(tr('BSI 백업 파일(.zip)을 고르세요', 'Pick a BSI backup (.zip)'))));
      return;
    }
    final ok = await _confirm(
        tr('백업 불러오기', 'Import backup'),
        tr('고른 백업을 이 폰에 합칩니다. 이 폰의 기록은 지우지 않고, 이미 있는 기록·사진은 건너뜁니다.\n\n'
            '설정(수고봉 간격·나침반 기준·언어 등)은 백업 값으로 바뀝니다.',
            'Merges the backup into this phone. Nothing here is deleted; records and photos already present are skipped.\n\n'
            'Settings (pole spacing, compass north, language…) take the backup values.'),
        tr('불러오기', 'Import'));
    if (!ok || !mounted) return;
    final sum = await _withProgress(tr('백업 불러오는 중', 'Importing backup'),
        (cb) => BackupService.importFiles(paths, onProgress: cb));
    try {
      await FilePicker.clearTemporaryFiles(); // 선택하며 캐시에 복사된 백업 파일
    } catch (_) {}
    if (sum == null || !mounted) return;
    setState(() {}); // 바뀐 설정 값을 다시 그린다
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('불러오기 완료', 'Import complete')),
        content: Text(
            [
              tr('기록 ${sum.recordsAdded}개 추가', '${sum.recordsAdded} record(s) added') +
                  (sum.recordsSkipped > 0
                      ? tr(' (이미 있던 ${sum.recordsSkipped}개 건너뜀)',
                          ' (${sum.recordsSkipped} already here, skipped)')
                      : ''),
              tr('파일 ${sum.filesWritten}개 복원', '${sum.filesWritten} file(s) restored') +
                  (sum.filesSkipped > 0
                      ? tr(' (같은 파일 ${sum.filesSkipped}개 건너뜀)',
                          ' (${sum.filesSkipped} identical, skipped)')
                      : ''),
              if (sum.projectsAdded > 0)
                tr('조사지 ${sum.projectsAdded}개 추가', '${sum.projectsAdded} site(s) added'),
              if (sum.draftRestored)
                tr('진행 중이던 조사를 되살렸습니다 — 지도에서 이어서 하세요',
                    'The in-progress survey was restored — resume it from the map'),
              tr('백업: 앱 ${sum.sourceApp} · ${sum.sourceCreatedAt}',
                  'Backup: app ${sum.sourceApp} · ${sum.sourceCreatedAt}'),
            ].join('\n'),
            style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(tr('확인', 'OK'))),
        ],
      ),
    );
  }

  /// GitHub 릴리스의 새 버전을 확인하고, 있으면 받아서 설치 화면을 연다(안드로이드).
  /// 같은 키로 서명된 배포본끼리는 덮어 설치되어 기록이 그대로 남는다.
  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    ReleaseInfo? r;
    Object? err;
    try {
      r = await UpdateService.latest();
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    void snack(String m) => ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
    if (err != null || r == null) {
      snack(tr('업데이트를 확인하지 못했습니다: $err', 'Could not check for updates: $err'));
      return;
    }
    if (!r.isNewer) {
      snack(tr('최신 버전입니다 (v$kAppVersion)', 'You are up to date (v$kAppVersion)'));
      return;
    }
    final rel = r;
    final notes = rel.notes.length > 700 ? '${rel.notes.substring(0, 700)}…' : rel.notes;
    final d = rel.publishedAt;
    final date = d == null
        ? ''
        : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('새 버전 v${rel.version}', 'New version v${rel.version}')),
        content: SingleChildScrollView(
          child: Text(
              [
                [
                  if (date.isNotEmpty) tr('게시 $date', 'Released $date'),
                  _size(rel.apkBytes),
                  tr('지금 v$kAppVersion', 'installed v$kAppVersion'),
                ].join(' · '),
                if (notes.isNotEmpty) ...['', notes],
                '',
                tr('업데이트해도 기록은 그대로 남습니다. 먼저 백업 내보내기를 해 두면 더 안전합니다.',
                    'Your records stay. Exporting a backup first is safer.'),
              ].join('\n'),
              style: const TextStyle(height: 1.45)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('나중에', 'Later'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('받아서 설치', 'Download & install'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
    final apk = await _withProgress(
        tr('새 버전 내려받는 중', 'Downloading update'),
        (cb) => UpdateService.download(rel, onProgress: cb),
        label: (got, total) => '${mb(got)} / ${mb(total)} MB');
    if (apk == null || !mounted) return;
    bool started;
    try {
      started = await UpdateService.install(apk);
    } catch (e) {
      if (mounted) snack(tr('설치 화면을 열지 못했습니다: $e', 'Could not open the installer: $e'));
      return;
    }
    if (!started && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tr('설치 허용이 필요합니다', 'Allow installs')),
          content: Text(
              tr('방금 열린 설정에서 "이 출처 허용"을 켜고 돌아와 앱 업데이트를 다시 누르세요 (한 번만).',
                  'Turn on "Allow from this source" in the screen that just opened, then tap App update again (once).'),
              style: const TextStyle(height: 1.45)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text(tr('확인', 'OK'))),
          ],
        ),
      );
    }
  }

  /// 내장 예시 사진 4장을 불러와 바로 AI 분석을 실행한다. 촬영 화면을 거치지
  /// 않으므로 카메라 권한 없이도 전체 분석 파이프라인을 시험할 수 있다.
  Future<void> _runDemo() async {
    setState(() => _busy = true);
    try {
      final draft = await DemoSample.createDraft();
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnalysisScreen(draft: draft)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(tr('예시 데이터를 불러오지 못했습니다: $e',
                'Could not load the sample data: $e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('설정', 'Settings'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 6, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _section(p, tr('일반', 'GENERAL')),
          Card(
            child: Column(children: [
              _row(p, Icons.brightness_6_outlined, tr('테마', 'Theme'),
                  trailing: _Segmented(
                    options: [tr('라이트', 'Light'), tr('다크', 'Dark')],
                    index: themeMode.value == ThemeMode.dark ? 1 : 0,
                    onSelect: (i) => setState(() =>
                        setThemeMode(i == 0 ? ThemeMode.light : ThemeMode.dark)),
                  )),
              Divider(height: 1, color: p.line),
              _row(p, Icons.language, tr('언어', 'Language'),
                  trailing: _Segmented(
                    options: const ['한국어', 'English'],
                    index: appLang.value == AppLang.en ? 1 : 0,
                    onSelect: (i) => setState(
                        () => setAppLang(i == 0 ? AppLang.ko : AppLang.en)),
                  )),
            ]),
          ),
          _section(p, tr('촬영', 'CAPTURE')),
          Card(
            child: Column(children: [
              // 촬영 화면의 나침반을 눌러도 같은 값이 바뀐다.
              // 선택은 **저장된 설정**을 그대로 보여 준다. 편각을 아직 몰라
              // 표시가 다른 상황은 선택값이 아니라 부제로 알린다(선택을 흔들면
              // 진북을 눌러도 아무 일이 없는 것처럼 보인다).
              ValueListenableBuilder<NorthRef>(
                valueListenable: northRef,
                builder: (_, want, __) => _row(
                    p, Icons.explore_outlined, tr('나침반 기준', 'Compass north'),
                    sub: !Geomag.canResolveDeclination
                        ? tr('이 기기에서는 진북만 제공됩니다',
                            'This device provides true north only')
                        : Geomag.effective(want) != want
                            ? tr('편각을 아직 몰라 지금은 자북으로 표시됩니다 (촬영 화면에서 위치를 잡으면 적용)',
                                'Declination unknown yet — showing magnetic for now; applies once a position is fixed')
                            : tr('진북은 지도·좌표 기준, 자북은 자기 나침반 기준',
                                'True north matches maps; magnetic matches a needle compass'),
                    trailing: SegmentedButton<NorthRef>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: NorthRef.trueNorth,
                            label: Text(tr('진북', 'True'))),
                        ButtonSegment(
                            value: NorthRef.magnetic,
                            label: Text(tr('자북', 'Mag')),
                            enabled: Geomag.canResolveDeclination),
                      ],
                      selected: {want},
                      onSelectionChanged: (s) => setNorthRef(s.first),
                    )),
              ),
              Divider(height: 1, color: p.line),
              // 봉마다 띠 간격이 다르다 — 스케일(px/m)이 이 값으로 환산된다.
              InkWell(
                onTap: _editPoleGap,
                child: _row(p, Icons.linear_scale,
                    tr('수고봉 경계 간격', 'Pole band spacing'),
                    sub: tr('인접 경계(띠) 사이 실제 거리 — 새 조사부터 적용',
                        'Distance between adjacent bands — applies to new surveys'),
                    trailing: Text('${_fmtGap(poleGapM.value)} m',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 15,
                            fontWeight: FontWeight.w700))),
              ),
            ]),
          ),
          _section(p, tr('데이터', 'DATA')),
          Card(
            child: Column(children: [
              InkWell(
                onTap: _exportBackup,
                child: _row(p, Icons.backup_outlined, tr('백업 내보내기', 'Export backup'),
                    sub: tr('기록·사진·원시 데이터·조사지·설정 전부를 파일로 — 폰을 바꿀 때',
                        'All records, photos, raw data, sites and settings — for a new phone'),
                    trailing: Icon(Icons.chevron_right, color: p.muted)),
              ),
              Divider(height: 1, color: p.line),
              InkWell(
                onTap: _importBackup,
                child: _row(p, Icons.settings_backup_restore,
                    tr('백업 불러오기', 'Import backup'),
                    sub: tr('내장 저장공간 › Download › BSI_backup 의 파일을 이 폰에 합침 — 이미 있는 기록은 건너뜀',
                        'Merge a backup from another phone — existing records are kept'),
                    trailing: Icon(Icons.chevron_right, color: p.muted)),
              ),
            ]),
          ),
          // 시험 섹션은 개발자 모드(지도의 현재 위치 버튼 7번 탭)에서만 보인다.
          if (devMode.value) ...[
            _section(p, tr('시험 (개발자)', 'TRY IT (DEVELOPER)')),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : _runDemo,
                child: _row(p, Icons.science_outlined,
                    tr('예시 사진으로 시험', 'Try with sample photos'),
                    sub: tr('내장된 4방위 사진으로 분석 전체를 실행',
                        'Run the full analysis on the four bundled photos'),
                    trailing: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.chevron_right, color: p.muted)),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: _row(p, Icons.smart_display_outlined, tr('시연 모드', 'Demo mode'),
                  sub: tr('조사목 추가 시 예시 사진으로 촬영→분석→판정표→기록까지 자동 진행',
                      'New tree auto-runs capture→analysis→table→records with sample photos'),
                  trailing: Switch(
                    value: demoMode.value,
                    onChanged: (v) => setState(() => setDemoMode(v)),
                  )),
            ),
          ],
          // 앱 안 업데이트는 안드로이드만(iOS는 스토어·TestFlight로 배포)
          if (Platform.isAndroid) ...[
            _section(p, tr('앱', 'APP')),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _checkingUpdate ? null : _checkUpdate,
                child: _row(p, Icons.system_update_outlined, tr('앱 업데이트', 'App update'),
                    sub: tr('지금 v$kAppVersion — 새 버전이 있으면 받아서 설치 (기록 유지)',
                        'Installed v$kAppVersion — download and install a newer one (records kept)'),
                    trailing: _checkingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.chevron_right, color: p.muted)),
              ),
            ),
          ],
          _section(p, tr('판정 기준', 'DECISION CRITERIA')),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BsiTableScreen())),
              child: _row(p, Icons.grid_on, tr('존치·벌채 판정표', 'Retain / fell table'),
                  sub: tr('BSI × 흉고직경 고사 확률표', 'Mortality probability by BSI × DBH'),
                  trailing: Icon(Icons.chevron_right, color: p.muted)),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AboutScreen())),
              child: _row(p, Icons.info_outline, tr('정보', 'About'),
                  trailing: Icon(Icons.chevron_right, color: p.muted)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(AppPalette p, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                color: p.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 1.0)),
      );

  Widget _row(AppPalette p, IconData ic, String title,
      {String? sub, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(ic, size: 22, color: p.navy),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
            ],
          ]),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onSelect;
  const _Segmented({required this.options, required this.index, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration:
          BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < options.length; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: i == index ? p.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: i == index
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)]
                    : null,
              ),
              child: Text(options[i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: i == index ? p.ink : p.muted)),
            ),
          ),
      ]),
    );
  }
}
