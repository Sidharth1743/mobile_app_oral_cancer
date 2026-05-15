import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../l10n/generated/app_localizations.dart';
import 'screens/operations_screen.dart';
import 'screens/sync_queue_screen.dart';

class AppHomeScreen extends StatefulWidget {
  const AppHomeScreen({
    super.key,
    required this.screening,
    this.onChangeLanguage,
    LocalDatabase? database,
  }) : _database = database;

  final Widget screening;
  final VoidCallback? onChangeLanguage;
  final LocalDatabase? _database;

  @override
  State<AppHomeScreen> createState() => _AppHomeScreenState();
}

class _AppHomeScreenState extends State<AppHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = [
      widget.screening,
      const OperationsScreen(),
      SyncQueueScreen(database: widget._database),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.medical_services_outlined),
            selectedIcon: const Icon(Icons.medical_services),
            label: l10n.screeningNav,
          ),
          NavigationDestination(
            icon: const Icon(Icons.badge_outlined),
            selectedIcon: const Icon(Icons.badge),
            label: l10n.operationsNav,
          ),
          NavigationDestination(
            icon: const Icon(Icons.sync_outlined),
            selectedIcon: const Icon(Icons.sync),
            label: l10n.queueNav,
          ),
        ],
      ),
      floatingActionButton: widget.onChangeLanguage == null
          ? null
          : FloatingActionButton.small(
              onPressed: widget.onChangeLanguage,
              tooltip: l10n.changeLanguage,
              child: const Icon(Icons.translate),
            ),
    );
  }
}
