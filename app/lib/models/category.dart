/// The five triage actions shown to a seller.
enum TriageCategory {
  fresh('fresh', 'Fresh'),
  sellSoon('sell_soon', 'Sell Soon'),
  discountToday('discount_today', 'Discount Today'),
  spoilageRisk('spoilage_risk', 'Spoilage Risk'),
  uncertain('uncertain', 'Uncertain');

  const TriageCategory(this.id, this.label);

  /// Stable identifier used in JSON assets, SQLite and CSV exports.
  final String id;

  /// Text shown on screen.
  final String label;

  static TriageCategory fromId(String id) => TriageCategory.values.firstWhere(
    (c) => c.id == id,
    orElse: () => throw ArgumentError('Unknown category id: $id'),
  );
}

/// Why the decision mapper produced a category.
enum DecisionReason {
  /// The top model class was used directly.
  model('model'),

  /// Spoilage probability passed t_spoil although another class was on top.
  spoilageOverride('spoilage_override'),

  /// The top class was below t_conf.
  lowConfidence('low_confidence'),

  /// The model judged the image as not a supported crop.
  unsupported('unsupported'),

  /// The photo failed the brightness check before inference.
  tooDark('too_dark'),

  /// The photo failed the overexposure check before inference.
  tooBright('too_bright'),

  /// The photo failed the sharpness check before inference.
  blurry('blurry');

  const DecisionReason(this.id);

  final String id;

  static DecisionReason fromId(String id) =>
      DecisionReason.values.firstWhere((r) => r.id == id);
}
