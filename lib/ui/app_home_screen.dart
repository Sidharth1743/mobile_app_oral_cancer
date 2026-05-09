import 'package:flutter/material.dart';

import '../data/local_database.dart';
import 'screens/operations_screen.dart';
import 'screens/sync_queue_screen.dart';

class AppHomeScreen extends StatefulWidget {
  const AppHomeScreen({
    super.key,
    required this.screening,
    LocalDatabase? database,
  }) : _database = database;

  final Widget screening;
  final LocalDatabase? _database;

  @override
  State<AppHomeScreen> createState() => _AppHomeScreenState();
}

class _AppHomeScreenState extends State<AppHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Screening',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Operations',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Queue',
          ),
        ],
      ),
    );
  }
}
