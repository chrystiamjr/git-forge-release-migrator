import 'package:flutter/material.dart';

import 'package:gfrm_gui/src/features/new_migration/domain/migration_provider_option.dart';

extension MigrationProviderOptionIcon on MigrationProviderOption {
  IconData get icon {
    return switch (this) {
      MigrationProviderOption.github => Icons.code,
      MigrationProviderOption.gitlab => Icons.change_history,
      MigrationProviderOption.bitbucket => Icons.diamond_outlined,
    };
  }
}
