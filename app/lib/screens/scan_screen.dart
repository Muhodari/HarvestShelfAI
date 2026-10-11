import 'package:flutter/material.dart';
import '../l10n/app_text.dart';
import 'package:image_picker/image_picker.dart';

import '../app_services.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/scan.dart';
import '../services/auth/session.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

/// Home tab: one main action (scan), today's tally and recent scans.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.onOpenHistory, this.onOpenProfile});

  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenProfile;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _scan(ImageSource source) async {
    final t = AppText.of(context);
    final services = Services.of(context);
    final user = SessionScope.userOf(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Downscale at capture: decoding a full 12 MP photo in Dart is slow.
    // No imageQuality: re-compressing the JPEG measurably shifts model
    // probabilities (0.20 -> 0.15 spoilage on a borderline test photo).
    final file = await _picker.pickImage(source: source, maxWidth: 1280);
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final outcome = await services.triage.triage(
        await file.readAsBytes(),
        userId: user.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final again = await navigator.push<ImageSource>(
        MaterialPageRoute(builder: (_) => ResultScreen(outcome: outcome)),
      );
      if (again != null) await _scan(again);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.scanFailed(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final services = Services.of(context);
    final user = SessionScope.userOf(context);
    final text = Theme.of(context).textTheme;
    final meta = services.meta;

    return Stack(
      children: [
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.greeting(DateTime.now()), style: text.bodySmall),
                        const SizedBox(height: 2),
                        Text(
                          user.firstName,
                          style: text.headlineMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: t.profile,
                    child: GestureDetector(
                      onTap: widget.onOpenProfile,
                      child: UserAvatar(user: user),
                    ),
                  ),
                ],
              ),
              if (meta.isDemo || meta.notice != null) ...[
                const SizedBox(height: 12),
                DemoBanner(
                  text: meta.isDemo ? t.demoWarning : meta.notice!,
                  short: meta.isDemo ? t.demoShort : t.interimShort,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                key: const Key('scan_camera'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.photo_camera_rounded, size: 24),
                label: Text(t.scanProduce, style: TextStyle(fontSize: 18)),
                onPressed: _busy ? null : () => _scan(ImageSource.camera),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: Text(t.chooseFromGallery),
                onPressed: _busy ? null : () => _scan(ImageSource.gallery),
              ),
              const SizedBox(height: 4),
              Text(
                t.scanHint,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              SectionLabel(t.today),
              _TodayTally(userId: user.id),
              SectionLabel(
                t.recent,
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: widget.onOpenHistory,
                  child: Text(t.seeAll, style: const TextStyle(fontSize: 15)),
                ),
              ),
              _Recent(userId: user.id),
            ],
          ),
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.white.withValues(alpha: 0.92),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(t.checking, style: text.titleMedium),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Today's counts per action, as plain numbers.
class _TodayTally extends StatelessWidget {
  const _TodayTally({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final services = Services.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: services.triage.changes,
      builder: (context, _, __) {
        final now = DateTime.now();
        return FutureBuilder<Map<TriageCategory, int>>(
          future: services.scans.countsByCategory(
            userId,
            since: DateTime(now.year, now.month, now.day),
          ),
          builder: (context, snap) {
            final counts = snap.data ?? const {};
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 6,
                ),
                child: Row(
                  children: [
                    for (final c in const [
                      TriageCategory.fresh,
                      TriageCategory.sellSoon,
                      TriageCategory.discountToday,
                      TriageCategory.spoilageRisk,
                    ])
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${counts[c] ?? 0}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t.categoryShort(c),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: categoryColor(c),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The last three scans.
class _Recent extends StatelessWidget {
  const _Recent({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final services = Services.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: services.triage.changes,
      builder: (context, _, __) => FutureBuilder<List<Scan>>(
        future: services.scans.forUser(userId),
        builder: (context, snap) {
          final scans = (snap.data ?? const <Scan>[]).take(3).toList();
          if (scans.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                t.noScansHome,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < scans.length; i++) ...[
                if (i > 0) const Divider(indent: 62),
                ScanTile(
                  scan: scans[i],
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
