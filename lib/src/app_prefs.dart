import 'package:flutter/material.dart';

/// App-wide preferences, driven from 설정. Simple in-memory notifiers
/// (persist to disk later if needed).
final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

/// Show the vertical plumb line + crosshair on the capture screen.
final ValueNotifier<bool> showGuides = ValueNotifier(true);

/// Default flash mode when the camera opens (false = off, true = auto).
final ValueNotifier<bool> defaultFlashAuto = ValueNotifier(false);

/// Coordinate display format (false = WGS84 lat/lon, true = UTM).
final ValueNotifier<bool> coordUtm = ValueNotifier(false);

/// 수고봉 전체 길이 (m) — 촬영 사진의 픽셀→미터 스케일 기준.
final ValueNotifier<double> poleLengthM = ValueNotifier(3.0);
