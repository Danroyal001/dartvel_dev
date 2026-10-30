// An empty simple string neither starts nor ends with whitespace; an empty
// leading or trailing piece of an interpolation does.
void f(int x) {
  print(
    'The key is usually the same, '
    'but it can be different.'
    ''
    'For example this.',
  );
  print('a b' '' 'c');
  print('a b' '$x c');
  print('a b$x' 'c');
  print('a b' '$x');
}
