import 'package:flutter/material.dart';

import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('AI 모델'),
          Card(
            child: Column(children: const [
              ListTile(
                leading: Icon(Icons.memory, color: AppColors.navy),
                title: Text('내장 분할 모델'),
                subtitle: Text('YOLO26s-seg @640 (수간/그을음)'),
                trailing: Icon(Icons.check_circle, color: AppColors.green),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          _section('계측'),
          Card(
            child: Column(children: const [
              ListTile(
                leading: Icon(Icons.straighten, color: AppColors.navy),
                title: Text('수고봉 기본 길이'),
                subtitle: Text('3 m (촬영 시 노란 수고봉으로 픽셀 스케일 산정)'),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          _section('정보'),
          Card(
            child: Column(children: const [
              ListTile(
                leading: Icon(Icons.info_outline, color: AppColors.navy),
                title: Text('산불피해목 BSI 자동측정'),
                subtitle: Text('오프라인 현장 모듈 · v0.1'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.school_outlined, color: AppColors.navy),
                title: Text('Oregon State University'),
                subtitle: Text('Advanced Forestry Systems Lab'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}
