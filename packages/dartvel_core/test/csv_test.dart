import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('dvParseCsv', () {
    test('a quoted comma stays inside its field', () {
      expect(dvParseCsv('name,note\nAda,"first, second"\n'), <List<String>>[
        <String>['name', 'note'],
        <String>['Ada', 'first, second'],
      ]);
    });

    test('a doubled quote is one quote', () {
      expect(dvParseCsv('note\n"she said ""hi"""')[1], <String>['she said "hi"']);
    });

    test('a line break inside quotes belongs to the field, in any line ending', () {
      expect(dvParseCsv('id,body\r\n1,"line one\r\nline two"\r\n2,x\r\n'), <List<String>>[
        <String>['id', 'body'],
        <String>['1', 'line one\r\nline two'],
        <String>['2', 'x'],
      ]);
      expect(dvParseCsv('id,body\n1,"a\nb"')[1], <String>['1', 'a\nb']);
    });

    test('a byte-order mark is not part of the first header', () {
      expect(dvParseCsv('﻿id,name\n1,Ada').first, <String>['id', 'name']);
    });

    test('blank lines are skipped; an empty quoted field is kept', () {
      expect(dvParseCsv('id,note\n\n1,""\n   \n2,x\n'), <List<String>>[
        <String>['id', 'note'],
        <String>['1', ''],
        <String>['2', 'x'],
      ]);
    });

    test('unquoted fields are trimmed as before; quoted ones are kept exactly', () {
      expect(dvParseCsv('a, b ," c "')[0], <String>['a', 'b', ' c ']);
    });

    test('what the generated exporter writes reads back unchanged', () {
      const values = <String>['plain', 'comma, inside', 'quote " inside', 'multi\nline', ''];
      final line = values.map((v) => v.contains(',') || v.contains('"') || v.contains('\n') ? '"${v.replaceAll('"', '""')}"' : v).join(',');
      expect(dvParseCsv('a,b,c,d,e\n$line').last, values);
    });
  });

  group('dvChunkImportRows keeps a CSV record whole', () {
    test('a record with a quoted line break is one row, and rows still count from the file', () {
      final chunks = dvChunkImportRows('id,body\n1,"a\nb"\n2,c\n3,d\n', chunkSize: 2, hasHeader: true);
      expect(chunks.map((c) => c.rows).toList(), <List<String>>[
        <String>['1,"a\nb"', '2,c'],
        <String>['3,d'],
      ]);
      expect(chunks.first.header, 'id,body');
      expect(chunks.map((c) => c.startRow).toList(), <int>[2, 5]);
    });
  });
}
