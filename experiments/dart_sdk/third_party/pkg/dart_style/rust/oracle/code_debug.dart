// Oracle for the two debug traversals in lib/src/back_end/code.dart.
import '../../lib/src/back_end/code.dart';

String hex(String text) => text.codeUnits.map((c) => c.toRadixString(16).padLeft(4, '0')).join();
void main() {
  for (var seed = 0; seed < 128; seed++) {
    var root = GroupCode(seed % 140);
    root.newline(blank: true, indent: 99);
    root.write('α😀\n`');
    root.startSelection(-2);
    root.newline(blank: seed % 2 == 0, indent: seed % 5);
    var child = GroupCode(seed % 9);
    child.write(String.fromCharCode(0xd800));
    child.endSelection(-1);
    root.group(child);
    root.setFormattingEnabled(false, seed);
    root.write('hidden');
    root.newline(blank: true, indent: 4);
    root.setFormattingEnabled(true, seed + 3);
    print('$seed:${hex(root.toDebugString())}:${hex(root.toCodeTree())}');
  }
}
