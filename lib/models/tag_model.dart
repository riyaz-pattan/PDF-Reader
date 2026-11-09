class TagModel {
  final int? id;
  final String name;
  final int colorValue;

  TagModel({this.id, required this.name, required this.colorValue});

  factory TagModel.fromMap(Map<String, dynamic> map) {
    return TagModel(
      id: map['id'],
      name: map['name'],
      colorValue: map['color'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'color': colorValue,
    };
  }
}
