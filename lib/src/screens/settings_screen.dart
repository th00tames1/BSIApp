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
import 'manual_screen.dart';

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
        title: Text(tr('수고봉 눈금 간격', 'Pole graduation interval')),
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
                tr('수고봉 색 구간 하나의 실제 길이입니다. 값이 틀리면 모든 높이 계측값이 같은 비율로 달라집니다.',
                    'Actual length of one colour band on the pole. An incorrect value scales every height proportionally.'),
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
            content: Text(tr('0.05 ~ 5 m 범위로 입력하세요',
                'Enter a value from 0.05 to 5 m'))));
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
              Text(tr('완료될 때까지 앱을 종료하지 마세요', 'Do not close the app until finished'),
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
        tr('백업 생성', 'Create backup'),
        tr('조사 기록·사진·설정 전체를 백업 파일로 저장합니다.\n저장 위치: Download/BSI_backup',
            'Saves all survey records, photos and settings to a backup file.\nLocation: Download/BSI_backup'),
        tr('생성', 'Create'));
    if (!ok || !mounted) return;
    final files = await _withProgress(tr('백업 생성 중', 'Creating backup'),
        (cb) => BackupService.exportAll(onProgress: cb));
    if (files == null || !mounted) return;
    final size = files.fold<int>(0, (s, f) => s + f.lengthSync());
    final inDownloads = files.first.path.contains('/Download/');
    final share = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('백업 완료', 'Backup complete')),
        content: Text(
            [
              for (final f in files) '• ${f.uri.pathSegments.last}',
              tr('파일 ${files.length}개 · ${_size(size)}',
                  '${files.length} file(s) · ${_size(size)}'),
              '',
              inDownloads
                  ? tr('저장 위치: Download/BSI_backup', 'Location: Download/BSI_backup')
                  : tr('앱 내부 저장소에 저장되었습니다. 공유 기능으로 외부에 보관하세요.',
                      'Saved to app storage. Use Share to keep an external copy.'),
            ].join('\n'),
            style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('확인', 'OK'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('공유', 'Share'))),
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
        dialogTitle: tr('백업 파일 선택', 'Select backup file(s)'));
    if (res == null || !mounted) return;
    final paths = [
      for (final f in res.files)
        if (f.path != null && f.path!.toLowerCase().endsWith('.zip')) f.path!
    ];
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(tr('BSI 백업 파일(.zip)을 선택하세요', 'Select a BSI backup file (.zip)'))));
      return;
    }
    final ok = await _confirm(
        tr('백업 불러오기', 'Import backup'),
        tr('백업 데이터를 이 기기에 병합합니다. 중복 기록은 제외되며 설정은 백업 값으로 대체됩니다.',
            'Merges the backup into this device. Duplicate records are skipped and settings are replaced by the backup values.'),
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
              tr('기록 ${sum.recordsAdded}건 추가', '${sum.recordsAdded} record(s) added') +
                  (sum.recordsSkipped > 0
                      ? tr(' (중복 ${sum.recordsSkipped}건 제외)',
                          ' (${sum.recordsSkipped} duplicate(s) skipped)')
                      : ''),
              tr('파일 ${sum.filesWritten}개 복원', '${sum.filesWritten} file(s) restored') +
                  (sum.filesSkipped > 0
                      ? tr(' (동일 파일 ${sum.filesSkipped}개 제외)',
                          ' (${sum.filesSkipped} identical file(s) skipped)')
                      : ''),
              if (sum.projectsAdded > 0)
                tr('조사지 ${sum.projectsAdded}개 추가', '${sum.projectsAdded} site(s) added'),
              if (sum.draftRestored)
                tr('작성 중이던 조사를 복원했습니다', 'In-progress survey restored'),
              tr('백업 출처: 앱 ${sum.sourceApp} · ${sum.sourceCreatedAt}',
                  'Source: app ${sum.sourceApp} · ${sum.sourceCreatedAt}'),
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
    if (err is UpdateException && err.noRelease) {
      snack(tr('이미 최신 버전입니다 ($kAppVersion)', 'Already up to date ($kAppVersion)'));
      return;
    }
    if (err != null || r == null) {
      snack(tr('업데이트 확인 실패: $err', 'Update check failed: $err'));
      return;
    }
    if (!r.isNewer) {
      snack(tr('이미 최신 버전입니다 ($kAppVersion)', 'Already up to date ($kAppVersion)'));
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
        title: Text(tr('새 버전 ${rel.version}', 'New version ${rel.version}')),
        content: SingleChildScrollView(
          child: Text(
              [
                [
                  if (date.isNotEmpty) tr('배포일 $date', 'Released $date'),
                  _size(rel.apkBytes),
                  tr('현재 버전 $kAppVersion', 'current version $kAppVersion'),
                ].join(' · '),
                if (notes.isNotEmpty) ...['', notes],
                '',
                tr('업데이트 후에도 조사 기록은 유지됩니다.', 'Survey records are retained after the update.'),
              ].join('\n'),
              style: const TextStyle(height: 1.45)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('나중에', 'Later'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('설치', 'Install'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    String mb(int b) => (b / (1024 * 1024)).toStringAsFixed(1);
    final apk = await _withProgress(
        tr('업데이트 다운로드 중', 'Downloading update'),
        (cb) => UpdateService.download(rel, onProgress: cb),
        label: (got, total) => '${mb(got)} / ${mb(total)} MB');
    if (apk == null || !mounted) return;
    bool started;
    try {
      started = await UpdateService.install(apk);
    } catch (e) {
      if (mounted) snack(tr('설치 화면을 열 수 없습니다: $e', 'Could not open the installer: $e'));
      return;
    }
    if (!started && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tr('설치 권한 필요', 'Install permission required')),
          content: Text(
              tr('설정에서 "이 출처 허용"을 켠 후 다시 시도하세요.',
                  'Enable "Allow from this source" in Settings, then try again.'),
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
            content: Text(tr('예제 데이터를 불러올 수 없습니다: $e',
                'Could not load sample data: $e'))));
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
                        ? tr('이 기기는 진북만 지원합니다',
                            'This device supports true north only')
                        : Geomag.effective(want) != want
                            ? tr('위치 수신 전까지 자북 기준으로 표시', 'Magnetic north until a position fix')
                            : null,
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
                    tr('수고봉 눈금 간격', 'Pole graduation interval'),
                    sub: tr('높이 환산 기준값', 'Reference for height conversion'),
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
                    sub: tr('조사 기록·사진·설정 전체', 'All survey records, photos and settings'),
                    trailing: Icon(Icons.chevron_right, color: p.muted)),
              ),
              Divider(height: 1, color: p.line),
              InkWell(
                onTap: _importBackup,
                child: _row(p, Icons.settings_backup_restore,
                    tr('백업 불러오기', 'Import backup'),
                    sub: tr('백업 파일(.zip)에서 복원', 'Restore from a backup file (.zip)'),
                    trailing: Icon(Icons.chevron_right, color: p.muted)),
              ),
            ]),
          ),
          // 시험 섹션은 개발자 모드(지도의 현재 위치 버튼 7번 탭)에서만 보인다.
          if (devMode.value) ...[
            _section(p, tr('개발자 도구', 'DEVELOPER TOOLS')),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : _runDemo,
                child: _row(p, Icons.science_outlined,
                    tr('예제 데이터 분석', 'Analyse sample data'),
                    sub: tr('내장 4방위 사진으로 분석 실행', 'Run analysis on the bundled four-aspect photos'),
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
                  sub: tr('예제 사진으로 전 과정 자동 실행', 'Runs the full workflow with sample photos'),
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
                    sub: tr('현재 버전 $kAppVersion', 'Current version $kAppVersion'),
                    trailing: _checkingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.chevron_right, color: p.muted)),
              ),
            ),
          ],
          _section(p, tr('도움말', 'HELP')),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ManualScreen())),
              child: _row(p, Icons.menu_book_outlined, tr('사용 설명서', 'User guide'),
                  sub: tr('촬영부터 백업까지 사용 방법', 'How to use the app'),
                  trailing: Icon(Icons.chevron_right, color: p.muted)),
            ),
          ),
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
