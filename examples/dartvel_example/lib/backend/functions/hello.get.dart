// Typed function: declare parameters directly. The generator maps
// query/body/params to these arguments.
Map<String, Object?> hello(String name) {
  return <String, Object?>{'hello': name, 'ts': 123};
}
