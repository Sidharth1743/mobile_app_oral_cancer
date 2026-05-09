import 'package:flutter/material.dart';

import '../../data/local_database.dart';
import '../components/empty_state.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';

typedef SyncQueueLoader = Future<List<SyncQueueItem>> Function();

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({
    super.key,
    LocalDatabase? database,
    SyncQueueLoader? loadItems,
  }) : _database = database,
       _loadItems = loadItems;

  final LocalDatabase? _database;
  final SyncQueueLoader? _loadItems;

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> {
  late final LocalDatabase _database = widget._database ?? LocalDatabase();
  late Future<List<SyncQueueItem>> _future = _loadItems();

  void _refresh() {
    setState(() {
      _future = _loadItems();
    });
  }

  Future<List<SyncQueueItem>> _loadItems() {
    final injected = widget._loadItems;
    if (injected != null) {
      return injected();
    }
    return _database.queuedSyncItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<SyncQueueItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorBody(message: snapshot.error.toString());
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Nothing queued',
              message:
                  'Sharing requests appear here only after a completed result and consent.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return SectionPanel(
                title: item.kind.replaceAll('_', ' '),
                subtitle: item.createdAt.toLocal().toString(),
                trailing: StatusBadge(
                  label: item.status,
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.schedule,
                ),
                children: [
                  Text(
                    'Visit ${item.visitId}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Queue unavailable',
      message: message,
    );
  }
}
