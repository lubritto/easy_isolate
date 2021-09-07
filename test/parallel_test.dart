import 'dart:io';

import 'package:easy_isolate/src/parallel.dart';
import 'package:test/test.dart';

String intToStringAdapter(int i) {
  return i.toString();
}

bool isEven({int? item}) {
  return item != null && item % 2 == 0;
}

void writeFile(String filename) {
  File(filename).createSync();
}

void main() {
  test('Parallel.run', () async {
    final result = await Parallel.run(isEven, entryValue: 1);
    expect(result, false);
  });

  test('Parallel.foreach', () async {
    String filename(String name) {
      return Directory.systemTemp.path + '/$name';
    }

    await Parallel.foreach([filename('test1'), filename('test2')], writeFile);
    expect(File(filename('test1')).existsSync(), true);
    expect(File(filename('test2')).existsSync(), true);
  });

  test('Parallel.map', () async {
    final result = await Parallel.map([1, 2, 3, 4, 5], intToStringAdapter);
    expect(result, ['1', '2', '3', '4', '5']);
  });
}
