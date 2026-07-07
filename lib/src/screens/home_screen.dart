import 'package:flutter/material.dart';

import '../services/db_service.dart';
import '../theme.dart';
import 'register_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await DbService.instance.count();
    if (mounted) setState(() => _count = c);
  }

  Future<void> _startSurvey() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('산불피해목 BSI',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 4),
            const Text('자동측정 현장 모듈',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _startSurvey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                      colors: [AppColors.navy, Color(0xFF2A4373)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.park_rounded, color: Colors.white, size: 34),
                    const SizedBox(height: 14),
                    const Text('새 조사 시작',
                        style: TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('조사목 등록 → 4방위 촬영 → AI 분석 → 저장',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('조사 시작하기',
                            style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, color: AppColors.navy, size: 18),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.folder_rounded, color: AppColors.green),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                      child: Text('저장된 조사목',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  Text('$_count',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  const Text('  건', style: TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const _InfoCard(),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('오프라인 우선', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          SizedBox(height: 8),
          Text('네트워크 없이 현장에서 촬영 · AI 분석 · 저장이 모두 동작합니다. AI 모델은 앱에 내장되어 있습니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ]),
      ),
    );
  }
}
