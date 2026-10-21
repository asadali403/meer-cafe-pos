import 'package:flutter_test/flutter_test.dart';
import 'package:meer_cafe_pos/models/bill.dart';
import 'package:meer_cafe_pos/services/billing_calculator.dart';
import 'package:meer_cafe_pos/utils/errors.dart';
import 'package:meer_cafe_pos/utils/money.dart';

void main() {
  group('Money', () {
    test('formats PKR with grouping and 2 decimals', () {
      expect(Money.format(25000), 'Rs. 250.00');
      expect(Money.format(125050), 'Rs. 1,250.50');
      expect(Money.format(123456789), 'Rs. 1,234,567.89');
      expect(Money.format(0), 'Rs. 0.00');
      expect(Money.format(5), 'Rs. 0.05');
    });

    test('parses input without floating point', () {
      expect(Money.parse('250'), 25000);
      expect(Money.parse('250.5'), 25050);
      expect(Money.parse('1,250.75'), 125075);
      expect(Money.parse('Rs. 99'), 9900);
      expect(Money.parse('0.1'), 10);
      expect(Money.parse('-5'), isNull);
      expect(Money.parse('1.234'), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse(''), isNull);
    });
  });

  group('BillingCalculator', () {
    final lines = [const CalcLine(2, 25000), const CalcLine(1, 45000)]; // 500 + 450

    test('subtotal = sum of qty x unit price', () {
      expect(BillingCalculator.subtotal(lines), 95000);
    });

    test('grand total = subtotal - discount', () {
      final t = BillingCalculator.totals(lines, discount: 5000);
      expect(t.subtotal, 95000);
      expect(t.discount, 5000);
      expect(t.rounding, 0);
      expect(t.total, 90000);
    });

    test('rejects invalid discount and quantities', () {
      expect(() => BillingCalculator.totals(lines, discount: 95001), throwsA(isA<ValidationException>()));
      expect(() => BillingCalculator.totals(lines, discount: -1), throwsA(isA<ValidationException>()));
      expect(() => BillingCalculator.subtotal([const CalcLine(0, 100)]), throwsA(isA<ValidationException>()));
      expect(() => BillingCalculator.subtotal([const CalcLine(-1, 100)]), throwsA(isA<ValidationException>()));
      expect(() => BillingCalculator.subtotal([const CalcLine(1, -100)]), throwsA(isA<ValidationException>()));
    });

    test('percent discount rounds to nearest paisa', () {
      expect(BillingCalculator.percentDiscount(95000, 1000), 9500); // 10%
      expect(BillingCalculator.percentDiscount(33333, 1250), 4167); // 12.5% of 333.33 = 41.666
    });

    test('cash rounding is explicit and only when configured', () {
      expect(BillingCalculator.roundingAdjustment(12345, 0), 0);
      expect(BillingCalculator.roundingAdjustment(12345, 500), 155); // 123.45 -> 125.00
      expect(BillingCalculator.roundingAdjustment(12245, 500), -245); // 122.45 -> 120.00
      expect(BillingCalculator.roundingAdjustment(12750, 500), 250); // 127.50 -> 130.00
      final t = BillingCalculator.totals([const CalcLine(1, 12345)], roundingStep: 100);
      expect(t.rounding, -45);
      expect(t.total, 12300);
    });

    test('received >= total: change returned, no balance', () {
      final p = BillingCalculator.payment(due: 90000, received: 100000);
      expect(p.applied, 90000);
      expect(p.changeReturned, 10000);
      expect(p.balanceDue, 0);
    });

    test('received < total: balance due, no change', () {
      final p = BillingCalculator.payment(due: 90000, received: 50000);
      expect(p.applied, 50000);
      expect(p.changeReturned, 0);
      expect(p.balanceDue, 40000);
    });

    test('exact payment', () {
      final p = BillingCalculator.payment(due: 90000, received: 90000);
      expect((p.applied, p.changeReturned, p.balanceDue), (90000, 0, 0));
    });

    test('payment status', () {
      expect(PaymentStatus.of(1000, 1000), PaymentStatus.paid);
      expect(PaymentStatus.of(1000, 400), PaymentStatus.partial);
      expect(PaymentStatus.of(1000, 0), PaymentStatus.unpaid);
    });
  });
}
