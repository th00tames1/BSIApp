import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import '../models/draft.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'capture_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _site = TextEditingController();
  final _address = TextEditingController();
  final _species = TextEditingController(text: '소나무');
  final _dbh = TextEditingController();
  final _memo = TextEditingController();
  double? _lat, _lon;
  bool _locating = false;

  @override
  void dispose() {
    for (final c in [_id, _site, _address, _species, _dbh, _memo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    final pos = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) {
        _lat = pos.latitude;
        _lon = pos.longitude;
      }
    });
    if (pos == null) {
      final st = await LocationService.ensure();
      if (!mounted) return;
      final msg = st == GpsStatus.ok
          ? '위치 신호를 받지 못했습니다 · 트인 곳에서 다시 시도하세요'
          : LocationService.message(st);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final draft = SurveyDraft()
      ..treeId = _id.text.trim()
      ..site = _site.text.trim()
      ..address = _address.text.trim()
      ..species = _species.text.trim()
      ..dbhCm = double.tryParse(_dbh.text.trim()) ?? 0
      ..memo = _memo.text.trim()
      ..lat = _lat
      ..lon = _lon
      ..poleLengthM = poleLengthM.value;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(draft: draft)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('조사 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            _label(p, '조사목 번호', required: true),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(hintText: 'TA205-001'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null,
            ),
            _label(p, '조사지'),
            TextFormField(
                controller: _site,
                decoration: const InputDecoration(hintText: '예: 인제 남면 3-2 임반')),
            _label(p, '위치'),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(hintText: '강원 인제군 남면'),
            ),
            const SizedBox(height: 12),
            _gpsCard(p),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label(p, '수종'),
                  TextFormField(controller: _species),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label(p, '흉고직경'),
                  TextFormField(
                    controller: _dbh,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(hintText: '28.4', suffixText: 'cm'),
                  ),
                ]),
              ),
            ]),
            _label(p, '메모'),
            TextFormField(
                controller: _memo,
                decoration: const InputDecoration(hintText: '선택 입력')),
            const SizedBox(height: 26),
            ElevatedButton(
              onPressed: _submit,
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Text('촬영 시작'),
                SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 20),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AppPalette p, String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Text(text,
              style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (required)
            Text('  *', style: TextStyle(color: p.ember, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _gpsCard(AppPalette p) {
    final has = _lat != null && _lon != null;
    return Container(
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Icon(Icons.location_on, color: p.green, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GPS · 촬영 시 자동',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: p.muted)),
            const SizedBox(height: 3),
            Text(
              has
                  ? '${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}'
                  : '4방위 촬영 지점 평균으로 기록',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: p.ink),
            ),
          ]),
        ),
        TextButton.icon(
          onPressed: _locating ? null : _getLocation,
          style: TextButton.styleFrom(foregroundColor: p.green),
          icon: _locating
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.green))
              : Icon(has ? Icons.check : Icons.my_location, size: 18),
          label: Text(has ? '기록됨' : '측정'),
        ),
      ]),
    );
  }
}
