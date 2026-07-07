import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/draft.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 가져올 수 없습니다 (권한/GPS 확인)')));
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
      ..lon = _lon;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => CaptureScreen(draft: draft)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('조사목 등록')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const FieldLabel('조사목 ID'),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(hintText: 'TA205-001'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '필수 항목입니다' : null,
            ),
            const FieldLabel('조사지'),
            TextFormField(controller: _site, decoration: const InputDecoration(hintText: '예: 홍길동')),
            const FieldLabel('조사 위치'),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(hintText: '강원특별자치도 인제군 남면'),
            ),
            const SizedBox(height: 10),
            _mapCard(),
            const FieldLabel('수종'),
            TextFormField(controller: _species),
            const FieldLabel('흉고직경(DBH)'),
            TextFormField(
              controller: _dbh,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(hintText: '28.4', suffixText: 'cm'),
            ),
            const FieldLabel('메모'),
            TextFormField(
                controller: _memo,
                maxLines: 2,
                decoration: const InputDecoration(hintText: '메모 입력 (선택)')),
            const SizedBox(height: 28),
            ElevatedButton(onPressed: _submit, child: const Text('등록 완료')),
          ],
        ),
      ),
    );
  }

  Widget _mapCard() {
    final has = _lat != null && _lon != null;
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const SizedBox(width: 16),
        const Icon(Icons.location_on, color: AppColors.green, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            has
                ? '${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}'
                : '현재 위치 좌표를 기록합니다',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
        TextButton.icon(
          onPressed: _locating ? null : _getLocation,
          icon: _locating
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 18),
          label: const Text('현재 위치'),
        ),
        const SizedBox(width: 6),
      ]),
    );
  }
}
