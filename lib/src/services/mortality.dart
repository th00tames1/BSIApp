import 'dart:math' as math;

/// Post-fire mortality probability from the integrated BSI and DBH.
///
/// The kickoff report (p.20) shows a BSI(1–25) × DBH(cm) probability table used to
/// classify 존치(retain) vs 벌채(cut). Until that exact calibrated table is supplied as
/// data, this uses a logistic model with the published Kwon et al. (2021) odds ratios
/// (BSI 1.45, DBH 0.91) and an intercept fitted to the table's extremes. Replace
/// [logit] with the client's exact coefficients / lookup table for production.
class Mortality {
  // ln(oddsRatio)
  static const double bBsi = 0.3716; // ln(1.45)
  static const double bDbh = -0.0943; // ln(0.91)
  static const double b0 = -0.683; // intercept fitted so extremes match the report table
  static const double retainThreshold = 0.5; // < threshold -> 존치, else 벌채

  static double logit(double bsi, double dbhCm) => b0 + bBsi * bsi + bDbh * dbhCm;

  /// Probability of mortality in [0,1].
  static double probability(double bsi, double dbhCm) {
    if (bsi.isNaN || dbhCm.isNaN) return double.nan;
    final z = logit(bsi, dbhCm);
    return 1.0 / (1.0 + math.exp(-z));
  }

  /// '존치' (retain) or '벌채' (cut).
  static String verdict(double bsi, double dbhCm) {
    final p = probability(bsi, dbhCm);
    if (p.isNaN) return '';
    return p < retainThreshold ? '존치' : '벌채';
  }
}
