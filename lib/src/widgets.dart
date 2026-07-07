import 'package:flutter/material.dart';

import 'theme.dart';

/// Bottom navigation matching the mock-ups: 홈 · 조사 · 기록 · 설정.
class AppBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const AppBottomNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _item(0, Icons.home_rounded, Icons.home_outlined, '홈'),
              _item(1, Icons.park_rounded, Icons.park_outlined, '조사'),
              _item(2, Icons.access_time_rounded, Icons.access_time, '기록'),
              _item(3, Icons.settings_rounded, Icons.settings_outlined, '설정'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData active, IconData inactive, String label) {
    final sel = i == index;
    final color = sel ? AppColors.green : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(sel ? active : inactive, color: color, size: 24),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// A labelled read-only value row used in cards.
class MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const MetricRow(this.icon, this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Section label above a form field.
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
