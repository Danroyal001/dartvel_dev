// The first line of a multiline string, when it is only whitespace possibly
// after a `\`, is not part of the contents (`contentsOffset`,
// `StringLexemeHelper._trimInitialWhitespace`).
void f(int x) {
  print('''\
simple
''');
  print('''\
interpolation $x
''');
  print("""  \
d $x""");
  print('''
plain $x \a
''');
  print('''\a
x $x''');
  print('''\
raw \$x
''');
  print('''\
not raw \$x \n
''');
}
