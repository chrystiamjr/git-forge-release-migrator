import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/new_migration_section_card.dart';
import 'package:gfrm_gui/src/features/new_migration/presentation/molecules/migration_provider_option_icon.dart';
import 'package:gfrm_gui/src/theme/gfrm_app_theme.dart';

final class MigrationEndpointSection extends StatelessWidget {
  const MigrationEndpointSection({
    required this.title,
    required this.selectedProvider,
    required this.urlKey,
    required this.tokenKey,
    required this.url,
    required this.token,
    required this.isValidated,
    required this.onProviderChanged,
    required this.onUrlChanged,
    required this.onTokenChanged,
    super.key,
  });

  final String title;
  final MigrationProviderOption selectedProvider;
  final Key urlKey;
  final Key tokenKey;
  final String url;
  final String token;
  final bool isValidated;
  final ValueChanged<MigrationProviderOption> onProviderChanged;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onTokenChanged;

  @override
  Widget build(BuildContext context) {
    final unit = GfrmAppTheme.unit;

    return NewMigrationSectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonFormField<MigrationProviderOption>(
            initialValue: selectedProvider,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: MigrationProviderOption.values
                .map((MigrationProviderOption provider) {
                  return DropdownMenuItem<MigrationProviderOption>(
                    value: provider,
                    child: Row(
                      children: <Widget>[
                        Icon(provider.icon, size: 18),
                        SizedBox(width: unit.s2),
                        Text(provider.label),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
            onChanged: (MigrationProviderOption? provider) {
              if (provider != null) {
                onProviderChanged(provider);
              }
            },
          ),
          SizedBox(height: unit.s4),
          TextFormField(
            key: urlKey,
            initialValue: url,
            decoration: const InputDecoration(labelText: 'Repository URL'),
            onChanged: onUrlChanged,
          ),
          SizedBox(height: unit.s4),
          TextFormField(
            key: tokenKey,
            initialValue: token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Token override'),
            onChanged: onTokenChanged,
          ),
          SizedBox(height: unit.s4),
          Row(
            children: <Widget>[
              Icon(
                isValidated ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isValidated ? GfrmAppTheme.colors.success : GfrmAppTheme.colors.textMuted,
                size: 18,
              ),
              SizedBox(width: unit.s2),
              Text(isValidated ? 'Connection validated' : 'Waiting for validation'),
            ],
          ),
        ],
      ),
    );
  }
}
