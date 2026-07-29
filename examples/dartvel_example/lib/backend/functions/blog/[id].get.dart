// Dynamic typed backend function example: /api/blog/<id>
Map<String, Object?> id(String id) =>
    <String, Object?>{'id': id, 'title': 'Post $id'};
