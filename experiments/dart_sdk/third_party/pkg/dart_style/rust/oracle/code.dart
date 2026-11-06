// Oracle driver for lib/src/back_end/code.dart; runs upstream code unchanged.
import '../../lib/src/back_end/code.dart';
import '../../lib/src/source_code.dart';

void main() {
  for (var seed = 0; seed < 256; seed++) {
    var root = GroupCode(seed % 5);
    root.newline(blank: true, indent: 99); // Suppressed on an empty group.
    root.write('α😀'); // Selection offsets are UTF-16 code units.
    root.startSelection(1);
    root.write('x');
    root.newline(blank: seed % 2 == 0, indent: seed % 140);
    var child = GroupCode(seed % 7);
    child.write('nested');
    child.endSelection(0);
    root.group(child);
    if (seed % 3 == 0) {
      root.setFormattingEnabled(false, 2);
      root.write('discarded');
      root.startSelection(0);
      root.newline(blank: true, indent: 100);
      root.setFormattingEnabled(false, 5); // Does not nest.
      if (seed % 6 == 0) root.setFormattingEnabled(true, 9);
    }
    root.write('end');
    root.endSelection(0);
    var result = root.build(
      SourceCode(
        'ab😀efghijk',
        isCompilationUnit: seed % 2 == 0,
        selectionStart: 4,
        selectionLength: 3,
      ),
      seed % 4 == 0 ? '\r\n' : '\n',
    );
    var hex = result.text.codeUnits
        .map((c) => c.toRadixString(16).padLeft(4, '0'))
        .join();
    print('$seed:$hex:${result.selectionStart}:${result.selectionLength}');
  }
  for (var mode = 0; mode < 4; mode++) {
    var root = GroupCode(4);
    root.newline(blank: true, indent: 9);
    if (mode > 1) root.write('tail');
    var result = root.build(SourceCode('', isCompilationUnit: mode % 2 == 0));
    var hex = result.text.codeUnits
        .map((c) => c.toRadixString(16).padLeft(4, '0'))
        .join();
    print('empty$mode:$hex:${result.selectionStart}:${result.selectionLength}');
  }
}
