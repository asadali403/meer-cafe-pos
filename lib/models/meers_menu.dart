/// Meer's Cafe real menu (from the printed menu cards). Prices in rupees.
/// Names are spelled exactly as printed on the menu. Loaded on first-time setup
/// ("Load Meer's Cafe menu") or from Products when the product list is empty.
class MenuItemSeed {
  final String category;
  final String name;
  final int rupees;
  final String description;
  const MenuItemSeed(this.category, this.name, this.rupees, [this.description = '']);
}

/// Categories in menu order. `kitchen` = printed on the chef's kitchen ticket.
const meersCategories = <(String name, bool kitchen)>[
  ('Deals', true),
  ('Burgers', true),
  ('Wraps & Shawarmas', true),
  ('Rolls', true),
  ('Crispy Broast', true),
  ('Pizza', true),
  ('Special Pizza', true),
  ('Fries', true),
  ('Appetizers', true),
  ('Dips', true),
  ('Tea & Coffee', true),
  ('Drinks', false),
  ('Other', true),
];

const _special = 'Special Pizza - not included in deals';

const meersMenu = <MenuItemSeed>[
  // Deals
  MenuItemSeed('Deals', 'Deal 1', 649, '1 Tikka Patty Burger, 3 Pcs Nuggets, Fries, 345 ml Drink'),
  MenuItemSeed('Deals', 'Deal 2', 549, '1 Zingister Burger, 1 Fries, 345 ml Drink'),
  MenuItemSeed('Deals', 'Deal 3', 1100, '2 Small Pizza, 1 Ltr Drink'),
  MenuItemSeed('Deals', 'Deal 4', 1950, '2 Medium Pizza, 1.5 Ltr Drink'),
  MenuItemSeed('Deals', 'Deal 5', 2900, '2 Large Pizza, 1.5 Ltr Drink'),
  MenuItemSeed('Deals', 'Deal 6', 2100, '4 Zingister Burger, 1 Large Fries, 1.5 Ltr Drink'),

  // Burgers
  MenuItemSeed('Burgers', 'Zingister Burger', 450),
  MenuItemSeed('Burgers', 'Crispo Burger', 500),
  MenuItemSeed('Burgers', 'Grill Burger', 550),
  MenuItemSeed('Burgers', 'Double Decker Burger', 700),
  MenuItemSeed('Burgers', 'Tikka Patty Burger', 350),
  MenuItemSeed('Burgers', 'Pizza Burger', 600),

  // Wraps & Shawarmas
  MenuItemSeed('Wraps & Shawarmas', 'Chicken Shawarma', 300),
  MenuItemSeed('Wraps & Shawarmas', 'Arabian Shawarma', 450),
  MenuItemSeed('Wraps & Shawarmas', 'Malai Botti Shawarma', 350),
  MenuItemSeed('Wraps & Shawarmas', 'Hot Grill Shawarma', 450),
  MenuItemSeed('Wraps & Shawarmas', "Meer's Special Platter", 850),
  MenuItemSeed('Wraps & Shawarmas', 'Zingister Wrap', 650),
  MenuItemSeed('Wraps & Shawarmas', 'Tortilla Wrap', 650),
  MenuItemSeed('Wraps & Shawarmas', 'Grill Wrap', 650),
  MenuItemSeed('Wraps & Shawarmas', 'Zinger Shawarma', 450),

  // Rolls (Meer's Special)
  MenuItemSeed('Rolls', 'Chicken Bihari Roll', 650),
  MenuItemSeed('Rolls', 'Chicken Kabab Roll', 350),
  MenuItemSeed('Rolls', 'Chicken Malai Botti Roll', 390),
  MenuItemSeed('Rolls', 'Zingister Roll', 450),
  MenuItemSeed('Rolls', "Meer's Special Roll", 580),
  MenuItemSeed('Rolls', 'Chicken Grill Roll', 450),

  // Crispy Broast (Meer's Special)
  MenuItemSeed('Crispy Broast', 'Quater Broast', 750,
      'Thigh + Chest + Fries + Garlic Sauce + Dinner Roll + 345ml Drink'),
  MenuItemSeed('Crispy Broast', 'Half Broast', 1200,
      'Thigh + Chest + Leg + Wing + Fries + Garlic Sauce + Dinner Roll + 1 Liter Coke'),
  MenuItemSeed('Crispy Broast', 'Full Broast', 2300,
      '2 Thigh + 2 Chest + 2 Leg + 2 Wing + Large Fries + 2 Garlic Sauce + 2 Dinner Roll + 1.5 Liter Coke'),

  // Pizza (Small / Medium / Large)
  MenuItemSeed('Pizza', 'Tikka Pizza (Small)', 499),
  MenuItemSeed('Pizza', 'Tikka Pizza (Medium)', 899),
  MenuItemSeed('Pizza', 'Tikka Pizza (Large)', 1399),
  MenuItemSeed('Pizza', 'Fajita Pizza (Small)', 499),
  MenuItemSeed('Pizza', 'Fajita Pizza (Medium)', 899),
  MenuItemSeed('Pizza', 'Fajita Pizza (Large)', 1399),
  MenuItemSeed('Pizza', 'Cheese Lover (Small)', 499),
  MenuItemSeed('Pizza', 'Cheese Lover (Medium)', 899),
  MenuItemSeed('Pizza', 'Cheese Lover (Large)', 1399),

  // Special Pizza (Medium / Large) - not included in deals
  MenuItemSeed('Special Pizza', 'Creamy Pizza (Medium)', 1199, _special),
  MenuItemSeed('Special Pizza', 'Creamy Pizza (Large)', 1699, _special),
  MenuItemSeed('Special Pizza', 'Beef Pepproani (Medium)', 1199, _special),
  MenuItemSeed('Special Pizza', 'Beef Pepproani (Large)', 1699, _special),
  MenuItemSeed('Special Pizza', 'Lasagna Pizza (Medium)', 1199, _special),
  MenuItemSeed('Special Pizza', 'Lasagna Pizza (Large)', 1699, _special),
  MenuItemSeed('Special Pizza', 'Kabab Stuff (Large)', 1699, _special),
  MenuItemSeed('Special Pizza', 'Crave Crown Pizza (Large)', 1699, _special),

  // Fries
  MenuItemSeed('Fries', 'Simple Fries', 200),
  MenuItemSeed('Fries', 'Loaded Fries', 550),
  MenuItemSeed('Fries', 'Pizza Fries', 750),

  // Appetizers (Pizza Fries is listed under Fries)
  MenuItemSeed('Appetizers', 'Hot Wings', 450),
  MenuItemSeed('Appetizers', 'Nuggets', 350),
  MenuItemSeed('Appetizers', 'Cheese Pasta', 850),
  MenuItemSeed('Appetizers', 'Chicken Sandwich', 550),
  MenuItemSeed('Appetizers', 'Grill Sandwich', 650),

  // Dips
  MenuItemSeed('Dips', 'Cold Garlic', 80),
  MenuItemSeed('Dips', 'Chipotle', 80),
  MenuItemSeed('Dips', 'Mint Sauce', 80),
  MenuItemSeed('Dips', 'Honey Mustard', 80),
  MenuItemSeed('Dips', 'BBQ Sauce', 80),
  MenuItemSeed('Dips', 'Shawarma Sauce', 80),

  // Tea & Coffee
  MenuItemSeed('Tea & Coffee', 'Tea', 70),
  MenuItemSeed('Tea & Coffee', 'Special Tea', 120),
  MenuItemSeed('Tea & Coffee', 'Hot Coffee', 200),
];
