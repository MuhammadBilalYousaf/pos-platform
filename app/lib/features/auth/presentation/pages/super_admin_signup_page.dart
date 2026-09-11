import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';

/// Protected Super Admin registration. Requires the platform owner secret code.
class SuperAdminSignupPage extends StatefulWidget {
  const SuperAdminSignupPage({super.key});

  @override
  State<SuperAdminSignupPage> createState() => _SuperAdminSignupPageState();
}

class _SuperAdminSignupPageState extends State<SuperAdminSignupPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _ownerCode = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _ownerCode.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthBloc>().add(
          AuthPlatformSetupRequested(
            name: _name.text.trim().isEmpty ? 'Super Admin' : _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            ownerCode: _ownerCode.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin signup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _submit,
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: BlocConsumer<AuthBloc, AuthState>(
                    listener: (context, state) {
                      if (state is AuthAuthenticated) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                    builder: (context, state) {
                      final loading = state is AuthLoading;
                      final message = state is AuthUnauthenticated ? state.message : null;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Create Super Admin', style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(
                            'Anyone with the secret owner code can create a Super Admin. The code is checked in Firebase and is not stored in this app. Use a new email for each Super Admin.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Your name'),
                            enabled: !loading,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(labelText: 'Email'),
                            enabled: !loading,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _password,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(labelText: 'Password'),
                            enabled: !loading,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _ownerCode,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Secret owner code',
                              hintText: 'Required — stored in Firebase, not in this app',
                            ),
                            enabled: !loading,
                            onSubmitted: (_) => _submit(),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 16),
                            Text(message, style: TextStyle(color: theme.colorScheme.error)),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: loading ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(loading ? 'Creating account…' : 'Create Super Admin'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: loading ? null : () => Navigator.of(context).maybePop(),
                            child: const Text('Back to Sign in'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
