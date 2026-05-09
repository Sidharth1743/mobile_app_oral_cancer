import 'package:flutter/material.dart';

import '../components/section_panel.dart';
import 'ngo_dashboard_screen.dart';
import 'role_login_screen.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Staff access',
            subtitle: 'Role permissions come from Firebase user profiles.',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.login),
                title: const Text('Sign in'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RoleLoginScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionPanel(
            title: 'Aggregate dashboard',
            subtitle: 'No patient identity is shown in this view.',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bar_chart_outlined),
                title: const Text('NGO / CSR dashboard'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NgoCsrDashboardScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
