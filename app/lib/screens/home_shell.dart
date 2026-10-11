import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../core/theme.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';

/// Main screen after sign-in: Scan, History and Profile tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ScanScreen(
            onOpenHistory: () => setState(() => _tab = 1),
            onOpenProfile: () => setState(() => _tab = 2),
          ),
          const HistoryScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Brand.line)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.document_scanner_outlined),
              selectedIcon: const Icon(Icons.document_scanner_rounded),
              label: t.scan,
              tooltip: t.scan,
            ),
            NavigationDestination(
              icon: const Icon(Icons.history_rounded),
              selectedIcon: const Icon(Icons.history_rounded),
              label: t.history,
              tooltip: t.history,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: t.profile,
              tooltip: t.profile,
            ),
          ],
        ),
      ),
    );
  }
}
