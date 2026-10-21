import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/bill.dart';
import '../../models/product.dart';
import '../../repositories/bill_repository.dart';
import '../../services/billing_calculator.dart';
import '../../utils/ids.dart';
import '../../utils/money.dart';

/// One cart line: either a menu product or a hand-typed custom item.
class CartLine {
  final String key;
  final Product? product;
  final String name;
  final int unitPrice;
  final bool kitchen; // custom items only; products use their category setting
  int quantity;

  CartLine.product(Product p, this.quantity)
      : key = 'p${p.id}',
        product = p,
        name = p.name,
        unitPrice = p.pricePaisa,
        kitchen = true;

  CartLine.custom(this.name, this.unitPrice, this.quantity, {this.kitchen = false})
      : key = 'c${Ids.newId()}',
        product = null;

  bool get isCustom => product == null;
  int get lineTotal => unitPrice * quantity;
}

/// In-memory cart for the billing screen. Totals shown here are a preview only —
/// the repository recalculates everything from database prices when saving.
class CartController extends ChangeNotifier {
  final LinkedHashMap<String, CartLine> _lines = LinkedHashMap();
  int roundingStep;

  CartController({this.roundingStep = 0});

  /// Idempotency key for the bill being built; renewed after each completed bill.
  String billId = Ids.newId();

  BillType type = BillType.sale;
  String discountText = '';
  bool discountIsPercent = false;
  String receivedText = '';
  String method = 'Cash';
  String customerNote = '';

  bool get isSale => type == BillType.sale;
  List<CartLine> get lines => _lines.values.toList(growable: false);
  bool get isEmpty => _lines.isEmpty;
  int get itemCount => _lines.values.fold(0, (s, l) => s + l.quantity);
  int quantityOf(int productId) => _lines['p$productId']?.quantity ?? 0;

  void add(Product p) {
    final l = _lines['p${p.id}'];
    if (l == null) {
      _lines['p${p.id}'] = CartLine.product(p, 1);
    } else if (l.quantity < BillingCalculator.maxQuantity) {
      l.quantity++;
    }
    notifyListeners();
  }

  void addCustom(String name, int unitPrice, int quantity, {bool kitchen = false}) {
    final l = CartLine.custom(name.trim(), unitPrice, quantity, kitchen: kitchen);
    _lines[l.key] = l;
    notifyListeners();
  }

  void setQuantity(String key, int q) {
    final l = _lines[key];
    if (l == null) return;
    if (q <= 0) {
      _lines.remove(key);
    } else {
      l.quantity = q.clamp(1, BillingCalculator.maxQuantity);
    }
    notifyListeners();
  }

  void increment(String key) => setQuantity(key, (_lines[key]?.quantity ?? 0) + 1);
  void decrement(String key) => setQuantity(key, (_lines[key]?.quantity ?? 0) - 1);
  void remove(String key) => setQuantity(key, 0);

  void setType(BillType t) {
    type = t;
    if (t != BillType.sale) {
      discountText = '';
      receivedText = '';
    }
    notifyListeners();
  }

  /// Clears the cart. [newBill] starts a fresh idempotency key (after a bill is saved).
  void clear({bool newBill = false}) {
    _lines.clear();
    discountText = '';
    discountIsPercent = false;
    receivedText = '';
    method = 'Cash';
    customerNote = '';
    type = BillType.sale;
    if (newBill) billId = Ids.newId();
    notifyListeners();
  }

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  int get subtotal => _lines.values.fold(0, (s, l) => s + l.lineTotal);

  /// Discount in paisa, or null if the input is invalid.
  int? get discount {
    if (!isSale || discountText.trim().isEmpty) return 0;
    final v = Money.parse(discountText); // percent "10.5" parses to 1050 = basis points
    if (v == null) return null;
    if (discountIsPercent) {
      if (v > 10000) return null;
      return BillingCalculator.percentDiscount(subtotal, v);
    }
    return v;
  }

  String? get discountError {
    final d = discount;
    if (d == null) return discountIsPercent ? 'Enter 0-100%' : 'Invalid amount';
    if (d > subtotal) return 'More than subtotal';
    return null;
  }

  BillTotals get totals {
    final d = discountError == null ? discount! : 0;
    return BillingCalculator.totals(
      _lines.values.map((l) => CalcLine(l.quantity, l.unitPrice)),
      discount: d,
      roundingStep: isSale ? roundingStep : 0,
    );
  }

  int? get received => !isSale || receivedText.trim().isEmpty ? 0 : Money.parse(receivedText);

  PaymentOutcome get payment => isSale
      ? BillingCalculator.payment(due: totals.total, received: received ?? 0)
      : const PaymentOutcome(0, 0, 0);

  List<CartLineInput> toInput() => [
        for (final l in _lines.values)
          if (!l.isCustom) CartLineInput(l.product!.id!, l.quantity)
      ];

  List<CustomLineInput> toCustomInput() => [
        for (final l in _lines.values)
          if (l.isCustom) CustomLineInput(l.name, l.unitPrice, l.quantity, kitchen: l.kitchen)
      ];
}
