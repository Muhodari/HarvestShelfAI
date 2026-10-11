import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../app_services.dart';
import '../core/theme.dart';
import '../models/category.dart';
import '../models/scan.dart';
import '../services/auth/session.dart';
import '../widgets/common.dart';

/// The signed-in user's past scans (FR5), grouped by day and filterable.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  TriageCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final services = Services.of(context);
    final user = SessionScope.userOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.history)),
      body: ValueListenableBuilder<int>(
        valueListenable: services.triage.changes,
        builder: (context, _, __) => FutureBuilder<List<Scan>>(
          future: services.scans.forUser(user.id),
          builder: (context, snap) {
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.error_outline_rounded,
                title: t.couldNotLoadHistory,
                message: '${snap.error}',
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!;
            if (all.isEmpty) {
              return EmptyState(
                icon: Icons.history_rounded,
                title: t.noScansYet,
                message: t.scansAppearHere,
              );
            }
            final scans = _filter == null
                ? all
                : all.where((s) => s.category == _filter).toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    children: [
                      _Filter(
                        label: t.all,
                        selected: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final c in TriageCategory.values)
                        if (all.any((s) => s.category == c))
                          _Filter(
                            label: t.category(c),
                            selected: _filter == c,
                            onTap: () => setState(
                              () => _filter = _filter == c ? null : c,
                            ),
                          ),
                    ],
                  ),
                ),
                for (final group in _byDay(scans)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                      t.formatDay(group.first.createdAt),
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (var i = 0; i < group.length; i++) ...[
                    if (i > 0) const Divider(indent: 82, endIndent: 20),
                    ScanTile(scan: group[i]),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static List<List<Scan>> _byDay(List<Scan> scans) {
    final groups = <List<Scan>>[];
    for (final s in scans) {
      final d = s.createdAt;
      if (groups.isEmpty || !_sameDay(groups.last.first.createdAt, d)) {
        groups.add([s]);
      } else {
        groups.last.add(s);
      }
    }
    return groups;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: selected ? Brand.ink : Brand.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: selected ? Colors.white : Brand.ink,
            ),
          ),
        ),
      ),
    ),
  );
}
