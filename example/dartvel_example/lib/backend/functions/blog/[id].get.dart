// Dynamic typed backend function example: /api/blog/<id>
Map<String, dynamic> id(String id) => {'id': id, 'title': 'Post $id'};
