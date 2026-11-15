import 'package:material_ui/material_ui.dart';

import 'easypanel_backend.dart';
import 'models.dart';
import 'panel_backend.dart';

/// One input in a provider's connect form.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.hint,
    this.secret = false,
    this.optional = false,
    this.keyboard,
  });
  final String key;
  final String label;
  final String? hint;
  final bool secret;
  final bool optional;
  final TextInputType? keyboard;
}

/// A way to authenticate. [exchange] turns what the user typed into the
/// secrets that are stored (for example email + password into a token).
/// Anything the user typed that is not returned by [exchange] is discarded.
class AuthMode {
  const AuthMode({required this.id, required this.label, required this.fields, required this.exchange});
  final String id;
  final String label;
  final List<FieldSpec> fields;
  final Future<Map<String, String>> Function(String url, Map<String, String> values) exchange;
}

/// Everything the app needs to know about one kind of control panel.
/// Adding a provider = one [PanelKind] value, one backend class, one spec here.
class ProviderSpec {
  const ProviderSpec({
    required this.kind,
    required this.tagline,
    required this.icon,
    required this.urlHint,
    required this.authModes,
    required this.build,
  });
  final PanelKind kind;
  final String tagline;
  final IconData icon;
  final String urlHint;
  final List<AuthMode> authModes;
  final PanelBackend Function(ServerProfile profile, Map<String, String> secrets) build;

  String get name => kind.label;
}

/// Providers on the roadmap. Shown as "soon", never selectable.
const upcomingProviders = ['Coolify', 'Dokploy', 'Portainer', 'CapRover'];

final Map<PanelKind, ProviderSpec> providerSpecs = {
  PanelKind.easypanel: ProviderSpec(
    kind: PanelKind.easypanel,
    tagline: 'Docker apps, databases and compose stacks',
    icon: Icons.layers_rounded,
    urlHint: 'https://panel.example.com',
    authModes: [
      AuthMode(
        id: 'token',
        label: 'API token',
        fields: const [
          FieldSpec('token', 'API token', hint: 'Paste your token', secret: true),
        ],
        exchange: (url, v) async => {'token': v['token']!.trim()},
      ),
      AuthMode(
        id: 'login',
        label: 'Email & password',
        fields: const [
          FieldSpec('email', 'Email', hint: 'you@example.com', keyboard: TextInputType.emailAddress),
          FieldSpec('password', 'Password', secret: true),
          FieldSpec('code', '2FA code', hint: 'Only if enabled', optional: true, keyboard: TextInputType.number),
        ],
        exchange: (url, v) async => {
          'token': await EasypanelBackend.login(
            url: url,
            email: v['email']!.trim(),
            password: v['password']!,
            code: v['code']?.trim(),
          ),
        },
      ),
    ],
    build: (p, secrets) => EasypanelBackend(url: p.url, token: secrets['token'] ?? ''),
  ),
};

ProviderSpec specFor(PanelKind kind) => providerSpecs[kind]!;
