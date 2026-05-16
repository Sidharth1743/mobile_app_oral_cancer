import 'package:flutter/material.dart';

import '../../auth/role_auth.dart';
import '../../cloud/firebase_role_auth.dart';
import '../components/section_panel.dart';
import '../components/status_badge.dart';
import 'role_home_screen.dart';

typedef RoleSignIn =
    Future<FirebaseUserProfile> Function({
      required String email,
      required String password,
    });

class RoleLoginScreen extends StatefulWidget {
  const RoleLoginScreen({super.key, RoleSignIn? signIn}) : _signIn = signIn;

  final RoleSignIn? _signIn;

  @override
  State<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends State<RoleLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  FirebaseUserProfile? _profile;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signIn =
          widget._signIn ??
          FirebaseRoleAuthService().signInWithEmailAndPassword;
      final profile = await signIn(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) {
        return;
      }
      setState(() => _profile = profile);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff login')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Role account',
            subtitle: 'Use the Firebase account assigned to this device user.',
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('role-email-field'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('role-password-field'),
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('role-login-button'),
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_busy ? 'Signing in' : 'Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          if (profile != null) ...[
            const SizedBox(height: 12),
            SectionPanel(
              title: profile.displayName.isEmpty
                  ? 'Signed in'
                  : profile.displayName,
              subtitle: profile.email ?? profile.mobile ?? profile.uid,
              trailing: StatusBadge(
                label: profile.role.name,
                color: Theme.of(context).colorScheme.primary,
                icon: Icons.verified_user_outlined,
              ),
              children: [
                Text(
                  [profile.state, profile.district]
                      .whereType<String>()
                      .where((value) => value.trim().isNotEmpty)
                      .join(' / '),
                ),
                if (profile.role == AppRole.doctor) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'Doctor Firebase UID (paste into Prepare doctor package):\n${profile.uid}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('open-role-home-button'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoleHomeScreen(profile: profile),
                        ),
                      );
                    },
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Open home'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}
