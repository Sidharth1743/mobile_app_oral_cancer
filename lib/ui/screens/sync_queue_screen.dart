import 'package:flutter/material.dart';

import '../../cloud/firebase_role_auth.dart';
import '../../data/local_database.dart';
import '../../sync/cloud_sync_runner.dart';
import '../../sync/sync_worker.dart';
import '../components/empty_state.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';
import 'role_login_screen.dart';

typedef SyncQueueLoader = Future<List<SyncQueueItem>> Function();

class SyncQueueScreen extends StatefulWidget {
  const SyncQueueScreen({
    super.key,
    LocalDatabase? database,
    SyncQueueLoader? loadItems,
    FirebaseRoleAuthService? authService,
  }) : _database = database,
       _loadItems = loadItems,
       _authService = authService;

  final LocalDatabase? _database;
  final SyncQueueLoader? _loadItems;
  final FirebaseRoleAuthService? _authService;

  @override
  State<SyncQueueScreen> createState() => _SyncQueueScreenState();
}

class _SyncQueueScreenState extends State<SyncQueueScreen> {
  late final LocalDatabase _database = widget._database ?? LocalDatabase();
  late final FirebaseRoleAuthService _authService =
      widget._authService ?? FirebaseRoleAuthService();
  late Future<List<SyncQueueItem>> _future = _loadItems();
  bool _syncing = false;
  String? _syncMessage;
  String? _syncError;

  void _refresh() {
    setState(() {
      _future = _loadItems();
      _syncMessage = null;
      _syncError = null;
    });
  }

  Future<List<SyncQueueItem>> _loadItems() {
    final injected = widget._loadItems;
    if (injected != null) {
      return injected();
    }
    return _database.pendingSyncItems();
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _syncError = null;
    });
    try {
      final profile = await _authService.currentProfile();
      final result = await CloudSyncRunner(
        database: _database,
        actor: profile,
      ).run();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncMessage =
            'Sync finished: ${result.synced} uploaded, ${result.failed} failed.';
      });
      _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString();
      if (message.contains('No Firebase user')) {
        setState(() {
          _syncError =
              'Sign in under Operations → Staff login (ASHA account) before syncing.';
        });
      } else {
        setState(() => _syncError = message);
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _openStaffLogin() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RoleLoginScreen()));
    _refresh();
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SectionPanel(
              title: 'Upload to cloud',
              subtitle:
                  'Doctor cases and research exports upload only from full queue rows. '
                  'Sign in as ASHA, then tap Sync now.',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(_syncing ? 'Syncing…' : 'Sync now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _openStaffLogin,
                      child: const Text('Staff login'),
                    ),
                  ],
                ),
                if (_syncMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_syncMessage!),
                ],
                if (_syncError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _syncError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<SyncQueueItem>>(
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
                        'After consent, use Prepare doctor package and Create research export, then sync here.',
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
                        if (item.lastError != null &&
                            item.lastError!.trim().isNotEmpty)
                          Text(
                            item.lastError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
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
