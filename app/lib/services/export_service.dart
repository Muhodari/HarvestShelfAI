import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scan.dart';

/// Anonymous test log for evaluation (FR6). Contains no images, names or
/// usernames; `user_id` is only the internal account number, so a
/// participant's scans can be grouped without identifying them.
const csvHeader = [
  'scan_id',
  'user_id',
  'created_at',
  'crop',
  'category',
  'confidence',
  'reason',
  'inference_ms',
  'model_version',
];

String scansToCsv(List<Scan> scans) {
  final b = StringBuffer()..writeln(csvHeader.join(','));
  // Oldest first reads more naturally in a spreadsheet.
  for (final s in scans.reversed) {
    b.writeln(
      [
        s.id,
        s.userId ?? '',
        s.createdAt.toIso8601String(),
        s.crop ?? '',
        s.category.id,
        s.confidence.toStringAsFixed(4),
        s.reason.id,
        s.inferenceMs ?? '',
        _escape(s.modelVersion),
      ].join(','),
    );
  }
  return b.toString();
}

String _escape(String v) =>
    v.contains(RegExp('[,"\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// Writes the log where it can be copied off by USB without extra
/// permissions: Android/data/rw.harvestshelf.harvestshelf/files/exports/.
Future<File> writeCsvExport(List<Scan> scans, {DateTime? now}) async {
  final base =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'exports'));
  await dir.create(recursive: true);
  final stamp = (now ?? DateTime.now())
      .toIso8601String()
      .split('.')
      .first
      .replaceAll(':', '-');
  final file = File(p.join(dir.path, 'harvestshelf_log_$stamp.csv'));
  return file.writeAsString(scansToCsv(scans));
}
