class Category {
  final int id;
  final String name;
  final int sortOrder;
  final bool active;

  /// Items of this category are printed on the kitchen ticket for the chef.
  final bool kitchen;

  const Category(
      {required this.id, required this.name, required this.sortOrder, required this.active, this.kitchen = true});

  factory Category.fromRow(Map<String, Object?> r) => Category(
        id: r['id'] as int,
        name: r['name'] as String,
        sortOrder: r['sort_order'] as int,
        active: (r['active'] as int) == 1,
        kitchen: ((r['kitchen'] as int?) ?? 1) == 1,
      );
}

class Product {
  final int? id;
  final String name;
  final int categoryId;
  final String categoryName;
  final int pricePaisa;
  final String description;
  final bool active;
  final String createdAt;
  final String updatedAt;

  const Product({
    this.id,
    required this.name,
    required this.categoryId,
    this.categoryName = '',
    required this.pricePaisa,
    this.description = '',
    this.active = true,
    this.createdAt = '',
    this.updatedAt = '',
  });

  /// Display code, e.g. P0007.
  String get code => id == null ? 'NEW' : 'P${id.toString().padLeft(4, '0')}';

  factory Product.fromRow(Map<String, Object?> r) => Product(
        id: r['id'] as int,
        name: r['name'] as String,
        categoryId: r['category_id'] as int,
        categoryName: (r['category_name'] as String?) ?? '',
        pricePaisa: r['price'] as int,
        description: (r['description'] as String?) ?? '',
        active: (r['active'] as int) == 1,
        createdAt: r['created_at'] as String,
        updatedAt: r['updated_at'] as String,
      );

  Product copyWith({
    String? name,
    int? categoryId,
    int? pricePaisa,
    String? description,
    bool? active,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName,
        pricePaisa: pricePaisa ?? this.pricePaisa,
        description: description ?? this.description,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
