import '../utils/errors.dart';

/// One cart line used for calculation (all money in paisa).
class CalcLine {
  final int quantity;
  final int unitPrice;
  const CalcLine(this.quantity, this.unitPrice);
  int get lineTotal => quantity * unitPrice;
}

class BillTotals {
  final int subtotal;
  final int discount;

  /// Explicit cash-rounding adjustment (can be negative). Shown on screen and receipt.
  final int rounding;
  final int total;
  const BillTotals(this.subtotal, this.discount, this.rounding, this.total);
}

class PaymentOutcome {
  /// Portion of the tendered cash applied to the bill (counts as revenue collected).
  final int applied;
  final int changeReturned;
  final int balanceDue;
  const PaymentOutcome(this.applied, this.changeReturned, this.balanceDue);
}

/// Pure, side-effect-free bill maths. Integer paisa only.
class BillingCalculator {
  BillingCalculator._();

  static const maxQuantity = 9999;

  static int subtotal(Iterable<CalcLine> lines) {
    var sum = 0;
    for (final l in lines) {
      if (l.quantity <= 0 || l.quantity > maxQuantity) {
        throw ValidationException('Quantity must be between 1 and $maxQuantity.');
      }
      if (l.unitPrice < 0) throw ValidationException('Price cannot be negative.');
      sum += l.lineTotal;
    }
    return sum;
  }

  /// Subtotal − Discount (+ explicit rounding adjustment when [roundingStep] > 0).
  static BillTotals totals(Iterable<CalcLine> lines, {int discount = 0, int roundingStep = 0}) {
    final sub = subtotal(lines);
    if (discount < 0) throw ValidationException('Discount cannot be negative.');
    if (discount > sub) throw ValidationException('Discount cannot be more than the subtotal.');
    final afterDiscount = sub - discount;
    final adj = roundingAdjustment(afterDiscount, roundingStep);
    return BillTotals(sub, discount, adj, afterDiscount + adj);
  }

  /// Rounds half-up to the nearest [step] paisa. Returns the adjustment (rounded − amount).
  static int roundingAdjustment(int amount, int step) {
    if (step <= 0 || amount <= 0) return 0;
    final rounded = ((amount + step ~/ 2) ~/ step) * step;
    return rounded - amount;
  }

  /// Percentage discount (supports up to 2 decimals via basis points) rounded to paisa.
  static int percentDiscount(int subtotal, int basisPoints) {
    if (basisPoints < 0 || basisPoints > 10000) {
      throw ValidationException('Discount percent must be between 0 and 100.');
    }
    return (subtotal * basisPoints + 5000) ~/ 10000;
  }

  /// If received >= due: change = received − due, balance = 0.
  /// If received < due: change = 0, balance = due − received.
  static PaymentOutcome payment({required int due, required int received}) {
    if (received < 0) throw ValidationException('Amount received cannot be negative.');
    if (due < 0) throw ValidationException('Amount due cannot be negative.');
    if (received >= due) return PaymentOutcome(due, received - due, 0);
    return PaymentOutcome(received, 0, due - received);
  }
}
