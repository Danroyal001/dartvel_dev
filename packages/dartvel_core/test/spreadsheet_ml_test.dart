// Reading the Excel file a data model exports.
//
// exportExcel writes SpreadsheetML (XML Spreadsheet 2003), which Excel,
// LibreOffice and Numbers open, and importExcel read only tab-separated text,
// so an exported workbook could not be imported back. One reader here, which
// the generated importer calls.
import 'package:dartvel_core/src/data/spreadsheet_ml.dart';
import 'package:test/test.dart';

void main() {
  test('rows and cells come back with entities decoded', () {
    const String workbook = '''<?xml version="1.0"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Worksheet ss:Name="Note">
<Table>
<Row>
<Cell><Data ss:Type="String">id</Data></Cell>
<Cell><Data ss:Type="String">title</Data></Cell>
</Row>
<Row>
<Cell><Data ss:Type="String">n1</Data></Cell>
<Cell><Data ss:Type="String">Fish &amp; chips &lt;b&gt; &quot;hot&quot; it&apos;s</Data></Cell>
</Row>
</Table>
</Worksheet>
</Workbook>
''';
    expect(dvParseSpreadsheetMl(workbook), <List<String>>[
      <String>['id', 'title'],
      <String>['n1', 'Fish & chips <b> "hot" it\'s'],
    ]);
  });

  test('a skipped cell, an empty cell and a line break keep their places', () {
    // Excel itself writes ss:Index for a cell after a gap and drops empty
    // cells, so a reader that only counts cells shifts every later column.
    const String workbook = '''<Workbook><Worksheet><Table>
<Row><Cell><Data ss:Type="String">a</Data></Cell><Cell><Data ss:Type="String">b</Data></Cell><Cell><Data ss:Type="String">c</Data></Cell></Row>
<Row><Cell ss:Index="3"><Data ss:Type="Number">3</Data></Cell></Row>
<Row><Cell/><Cell><Data ss:Type="String">line&#10;two</Data></Cell></Row>
</Table></Worksheet></Workbook>''';
    expect(dvParseSpreadsheetMl(workbook), <List<String>>[
      <String>['a', 'b', 'c'],
      <String>['', '', '3'],
      <String>['', 'line\ntwo'],
    ]);
  });

  test('only the first worksheet is read', () {
    const String workbook = '''<Workbook>
<Worksheet ss:Name="One"><Table><Row><Cell><Data>first</Data></Cell></Row></Table></Worksheet>
<Worksheet ss:Name="Two"><Table><Row><Cell><Data>second</Data></Cell></Row></Table></Worksheet>
</Workbook>''';
    expect(dvParseSpreadsheetMl(workbook), <List<String>>[
      <String>['first'],
    ]);
  });

  test('a file that is not a SpreadsheetML workbook is refused', () {
    expect(() => dvParseSpreadsheetMl('id\ttitle\n1\tA'),
        throwsA(isA<FormatException>()));
  });
}
