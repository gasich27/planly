import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> saveBytesToTempFile(List<int> bytes, {String? fileName}) async {
  final directory = await getTemporaryDirectory();
  final name = fileName ?? 'ai_planner_${DateTime.now().millisecondsSinceEpoch}';
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> copyFileToTemp(File source, {String? fileName}) async {
  final directory = await getTemporaryDirectory();
  final name = fileName ?? source.path.split(RegExp(r'[\\/]' )).last;
  final file = File('${directory.path}/$name');
  await source.copy(file.path);
  return file;
}
