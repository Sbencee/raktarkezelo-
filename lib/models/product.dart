class Product {
  final String id;
  final String name;
  final int quantity;
  final String category;

  Product({
    required this.id,
    required this.name,
    required this.quantity,
    required this.category,
  });

  // 1. Átalakítás JSON (szótár) formátummá - MENTÉSHEZ
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'quantity': quantity, 'category': category};
  }

  // 2. Létrehozás JSON-ból - BETÖLTÉSHEZ
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'],
      category: json['category'],
    );
  }
}
