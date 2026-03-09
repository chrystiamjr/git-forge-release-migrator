import 'dart:io';

import 'package:gfrm_dart/gfrm_dart.dart';

Future<void> main(List<String> args) async {
  final int code = await runCli(args);
  exit(code);
}
