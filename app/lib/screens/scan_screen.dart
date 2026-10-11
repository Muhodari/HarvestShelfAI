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
              const SizedBox(height: 24),
              _ScanCard(busy: _busy, onTap: () => _scan(ImageSource.camera)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: Text(t.chooseFromGallery),
                onPressed: _busy ? null : () => _scan(ImageSource.gallery),
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
            return Row(
              children: [
                for (final (i, c) in const [
                  TriageCategory.fresh,
                  TriageCategory.sellSoon,
                  TriageCategory.discountToday,
                  TriageCategory.spoilageRisk,
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Stat(
                      count: counts[c] ?? 0,
                      label: t.categoryShort(c),
                      color: categoryColor(c),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.count, required this.label, required this.color});

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    decoration: BoxDecoration(
      color: count > 0 ? color.withValues(alpha: 0.08) : Brand.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: count > 0 ? color : Brand.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12.5,
              color: Brand.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The main action: a large green card with the photo tip under the label.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Semantics(
      button: true,
      enabled: !busy,
      child: Material(
        color: busy ? Brand.green.withValues(alpha: 0.5) : Brand.green,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('scan_camera'),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.scanProduce,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.scanHint,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
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
          return GroupCard(
            indent: 82,
            children: [for (final s in scans) ScanTile(scan: s)],
          );
        },
      ),
    );
  }
}
