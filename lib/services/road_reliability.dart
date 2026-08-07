import 'dart:math' as math;

/// Internal road reliability calculator.
///
/// This is NOT user-facing. Reliability is used only by:
/// - Route recommendation
/// - Navigation
/// - Road colouring
/// - AI route ranking
///
/// Users must NEVER see reliability/confidence in the UI.
class RoadReliability {
  RoadReliability._();

  /// Calculate reliability from community review evidence.
  ///
  /// Returns a value between 0.0 (no evidence) and 1.0 (highly reliable).
  ///
  /// Factors:
  /// - Number of reviews (more reviews → higher base reliability)
  /// - Agreement between reviews (stddev of ratings → lower is better)
  /// - Time weighting (newer reviews matter more)
  /// - Confidence based on review volume
  static double calculate({
    required int reviewCount,
    required List<int> safetyRatings,
    List<DateTime>? reviewDates,
  }) {
    if (reviewCount == 0 || safetyRatings.isEmpty) return 0.0;

    final volumeScore = _volumeFactor(reviewCount);
    final agreementScore = _agreementFactor(safetyRatings);
    final timeScore = reviewDates != null && reviewDates.isNotEmpty
        ? _timeWeightedScore(reviewDates)
        : 1.0;

    // Weighted combination: 30% volume, 50% agreement, 20% time recency
    final raw = (volumeScore * 0.3) + (agreementScore * 0.5) + (timeScore * 0.2);

    return raw.clamp(0.0, 1.0);
  }

  /// Calculate weighted safety rating from reviews.
  ///
  /// Newer reviews are weighted more heavily.
  /// Returns a value between 1 (safest) and 5 (most dangerous).
  static double calculateWeightedRating({
    required List<int> safetyRatings,
    List<DateTime>? reviewDates,
  }) {
    if (safetyRatings.isEmpty) return 3.0;

    if (reviewDates == null || reviewDates.length != safetyRatings.length) {
      // No dates available, simple average
      return safetyRatings.reduce((a, b) => a + b) / safetyRatings.length;
    }

    final now = DateTime.now();
    double weightedSum = 0;
    double totalWeight = 0;

    for (int i = 0; i < safetyRatings.length; i++) {
      final age = now.difference(reviewDates[i]).inDays;
      // Exponential decay: newer reviews matter more
      // 1 day old → weight ~1.0, 30 days → ~0.74, 90 days → ~0.40, 365 days → ~0.04
      final weight = math.exp(-0.01 * age);
      weightedSum += safetyRatings[i] * weight;
      totalWeight += weight;
    }

    if (totalWeight == 0) return 3.0;
    return (weightedSum / totalWeight).clamp(1.0, 5.0);
  }

  /// Get confidence level based on review count.
  ///
  /// Returns a value between 0.0 (no confidence) and 1.0 (high confidence).
  static double getConfidence(int reviewCount) {
    if (reviewCount == 0) return 0.0;
    if (reviewCount == 1) return 0.15;
    if (reviewCount == 2) return 0.30;
    if (reviewCount <= 5) return 0.50;
    if (reviewCount <= 10) return 0.70;
    if (reviewCount <= 20) return 0.85;
    if (reviewCount <= 50) return 0.92;
    return 0.97;
  }

  /// Review count → volume factor (diminishing returns curve).
  ///
  /// 1 review  → 0.20
  /// 3 reviews → 0.38
  /// 5 reviews → 0.50
  /// 10 reviews → 0.67
  /// 20 reviews → 0.82
  /// 40+ reviews → 0.92+
  static double _volumeFactor(int count) {
    if (count <= 0) return 0.0;
    return 0.95 * (1 - math.exp(-0.12 * count));
  }

  /// Rating agreement → agreement factor.
  ///
  /// All same rating → 1.0
  /// Wide spread → lower value
  /// Uses normalized standard deviation.
  static double _agreementFactor(List<int> ratings) {
    if (ratings.length <= 1) return 0.5;

    final mean = ratings.reduce((a, b) => a + b) / ratings.length;
    final variance = ratings
        .map((r) => (r - mean) * (r - mean))
        .reduce((a, b) => a + b) /
        ratings.length;
    final stddev = math.sqrt(variance);

    // Max possible stddev for 1-5 range is ~1.41 (half range)
    // Normalize: 0 stddev → 1.0, 2.0 stddev → 0.0
    final normalized = (stddev / 2.0).clamp(0.0, 1.0);

    return 1.0 - normalized;
  }

  /// Time-weighted score based on recency of reviews.
  ///
  /// More recent reviews contribute more to the score.
  /// Returns a value between 0.0 (all old) and 1.0 (all recent).
  static double _timeWeightedScore(List<DateTime> dates) {
    if (dates.isEmpty) return 0.5;

    final now = DateTime.now();
    double totalWeight = 0;
    double recentWeight = 0;

    for (final date in dates) {
      final ageDays = now.difference(date).inDays;
      // Weight: 1.0 for today, decays to ~0.04 at 1 year
      final weight = math.exp(-0.01 * ageDays);
      totalWeight += weight;

      // Count "recent" reviews (within 30 days) separately
      if (ageDays <= 30) {
        recentWeight += weight;
      }
    }

    if (totalWeight == 0) return 0.0;

    // Blend: overall recency + proportion of recent reviews
    final recencyScore = recentWeight / totalWeight;
    return recencyScore.clamp(0.0, 1.0);
  }
}
