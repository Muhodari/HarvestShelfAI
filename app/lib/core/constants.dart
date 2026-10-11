/// Asset paths bundled with the app. Model files are copied here from
/// `training/exports/` by `scripts/copy_model_to_app.sh`.
abstract final class Assets {
  static const model = 'assets/model/model.tflite';
  static const modelMeta = 'assets/model/model_meta.json';
  static const labels = 'assets/model/labels.json';
  static const guidanceRules = 'assets/guidance_rules.json';
  static const logoMark = 'assets/brand/mark.png';
  static const logoIcon = 'assets/brand/icon.png';
}
