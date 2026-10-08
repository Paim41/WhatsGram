import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/controller.dart';
import '../../ui/shared/branding.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.app});
  final AppController app;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final input = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final state = app.authorization;
    final kind = state['@type'];
    final label = switch (kind) {
      'authorizationStateWaitPhoneNumber' => 'Phone number with country code',
      'authorizationStateWaitCode' => 'Verification code',
      'authorizationStateWaitPassword' => 'Two-step verification password',
      'authorizationStateWaitEmailAddress' => 'Email address',
      'authorizationStateWaitEmailCode' => 'Email verification code',
      _ => null,
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Brand(size: 88)),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to WhatsGram',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your Telegram conversations. A familiar space.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (app.error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(app.error!),
                      ),
                    ),
                  if (label != null) ...[
                    if (kind == 'authorizationStateWaitCode')
                      Text(
                        'Delivery: ${(state['code_info']?['type']?['@type'] as String? ?? 'Telegram').replaceFirst('authenticationCodeType', '')}',
                      ),
                    if (kind == 'authorizationStateWaitPassword')
                      Text('Hint: ${state['password_hint'] ?? ''}'),
                    if (kind == 'authorizationStateWaitEmailCode')
                      Text(
                        'Sent to ${state['code_info']?['email_address_pattern'] ?? 'your email'}',
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      key: ValueKey(kind),
                      controller: input,
                      obscureText: kind == 'authorizationStateWaitPassword',
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(labelText: label),
                      onSubmitted: busy ? null : (_) => submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(busy ? 'Checking…' : 'Continue'),
                    ),
                    if (kind == 'authorizationStateWaitPhoneNumber')
                      TextButton(
                        onPressed: () => runAction(context, () async {
                          await app.client!.call(
                            'requestQrCodeAuthentication',
                            {'other_user_ids': <int>[]},
                          );
                        }),
                        child: const Text('Sign in with a QR code'),
                      ),
                  ] else if (kind ==
                      'authorizationStateWaitOtherDeviceConfirmation') ...[
                    Center(
                      child: ColoredBox(
                        color: Colors.white,
                        child: QrImageView(data: state['link'], size: 240),
                      ),
                    ),
                    const Text(
                      'Open Telegram on your phone → Settings → Devices → Link Desktop Device.',
                    ),
                  ] else if (kind == 'authorizationStateWaitRegistration' ||
                      kind == 'authorizationStateWaitPremiumPurchase') ...[
                    const Text(
                      'Complete account creation or the required purchase in an official Telegram app, then return here to sign in.',
                    ),
                  ] else if (app.client == null && !app.starting)
                    FilledButton(
                      onPressed: app.start,
                      child: const Text('Connect Telegram'),
                    )
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'WhatsGram is an unofficial client using the Telegram API.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your account stays yours. Each person signs in separately.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> submit() async {
    setState(() => busy = true);
    final value = input.text;
    input.clear();
    await runAction(context, () => widget.app.authenticate(value));
    if (mounted) setState(() => busy = false);
  }
}
