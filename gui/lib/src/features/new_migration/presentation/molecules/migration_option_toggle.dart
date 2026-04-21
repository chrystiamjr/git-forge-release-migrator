import 'package:flutter/material.dart';

final class MigrationOptionToggle extends StatelessWidget {
  const MigrationOptionToggle({required this.title, required this.value, required this.onChanged, super.key});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(title), value: value, onChanged: onChanged);
  }
}
