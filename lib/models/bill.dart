enum PaymentStatus {
  paid('PAID'),
  partial('PARTIALLY PAID'),
  unpaid('UNPAID');

  final String label;
  const PaymentStatus(this.label);

  String get dbValue => name;
  static PaymentStatus parse(String s) =>
      PaymentStatus.values.firstWhere((e) => e.name == s, orElse: () => PaymentStatus.unpaid);

  static PaymentStatus of(int total, int paid) {
    if (paid >= total) return PaymentStatus.paid;
    if (paid > 0) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }
}

/// What a bill represents. Only [sale] counts as sales revenue; personal food and
/// expenses are tracked separately and never mixed into sales or cash collected.
enum BillType {
  sale('Customer Sale', 'Sale'),
  personal('Personal / Staff Food', 'Personal'),
  expense('Expense', 'Expense');

  final String label;
  final String short;
  const BillType(this.label, this.short);

  static BillType parse(String? s) => BillType.values.firstWhere((e) => e.name == s, orElse: () => BillType.sale);
}

const paymentMethods =['Cash', 'Card', 'Bank Transfer', 'JazzCash', 'Easypaisa', 'Other'];

class BillItem {
  final String id;
  final String billId;
  final int lineNo;
  final int? productId;
  final String productName;
  final String categoryName;
  final int quantity;
  final int unitPrice;
  final int lineTotal;

  /// Typed in by hand (not from the product list).
  final bool isCustom;

  /// Printed on the kitchen ticket.
  final bool kitchen;

  const BillItem({
    required this.id,
    required this.billId,
    required this.lineNo,
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.isCustom = false,
    this.kitchen = true,
  });

  factory BillItem.fromRow(Map<String, Object?> r) => BillItem(
        id: r['id'] as String,
        billId: r['bill_id'] as String,
        lineNo: r['line_no'] as int,
        productId: r['product_id'] as int?,
        productName: r['product_name'] as String,
        categoryName: (r['category_name'] as String?) ?? '',
        quantity: r['quantity'] as int,
        unitPrice: r['unit_price'] as int,
        lineTotal: r['line_total'] as int,
        isCustom: ((r['is_custom'] as int?) ?? 0) == 1,
        kitchen: ((r['kitchen'] as int?) ?? 1) == 1,
      );
}

class Payment {
  final String id;
  final String billId;
  final int amount; // amount applied to the bill (revenue collected)
  final int tendered; // cash handed over by the customer
  final int changeGiven;
  final String method;
  final String receivedByName;
  final String createdAt;
  final String businessDate;

  const Payment({
    required this.id,
    required this.billId,
    required this.amount,
    required this.tendered,
    required this.changeGiven,
    required this.method,
    required this.receivedByName,
    required this.createdAt,
    required this.businessDate,
  });

  factory Payment.fromRow(Map<String, Object?> r) => Payment(
        id: r['id'] as String,
        billId: r['bill_id'] as String,
        amount: r['amount'] as int,
        tendered: r['tendered'] as int,
        changeGiven: r['change_given'] as int,
        method: r['method'] as String,
        receivedByName: r['received_by_name'] as String,
        createdAt: r['created_at'] as String,
        businessDate: r['business_date'] as String,
      );
}

class Bill {
  final String id;
  final String invoiceNo;
  final String businessDate;
  final String createdAt;
  final int cashierId;
  final String cashierName;
  final String customerNote;
  final int subtotal;
  final int discount;
  final int rounding;
  final int total;
  final int amountPaid;
  final int balanceDue;
  final PaymentStatus paymentStatus;
  final int printCount;
  final String syncStatus;
  final BillType billType;
  final List<BillItem> items;
  final List<Payment> payments;

  bool get isSale => billType == BillType.sale;
  List<BillItem> get kitchenItems => items.where((i) => i.kitchen).toList();

  const Bill({
    this.billType = BillType.sale,
    required this.id,
    required this.invoiceNo,
    required this.businessDate,
    required this.createdAt,
    required this.cashierId,
    required this.cashierName,
    required this.customerNote,
    required this.subtotal,
    required this.discount,
    required this.rounding,
    required this.total,
    required this.amountPaid,
    required this.balanceDue,
    required this.paymentStatus,
    required this.printCount,
    required this.syncStatus,
    this.items = const [],
    this.payments = const [],
  });

  /// Total cash handed over across all payments.
  int get totalTendered => payments.fold(0, (s, p) => s + p.tendered);

  /// Total change returned across all payments.
  int get totalChange => payments.fold(0, (s, p) => s + p.changeGiven);

  factory Bill.fromRow(Map<String, Object?> r,
          {List<BillItem> items = const [], List<Payment> payments = const []}) =>
      Bill(
        id: r['id'] as String,
        invoiceNo: r['invoice_no'] as String,
        businessDate: r['business_date'] as String,
        createdAt: r['created_at'] as String,
        cashierId: r['cashier_id'] as int,
        cashierName: r['cashier_name'] as String,
        customerNote: (r['customer_note'] as String?) ?? '',
        subtotal: r['subtotal'] as int,
        discount: r['discount'] as int,
        rounding: r['rounding'] as int,
        total: r['total'] as int,
        amountPaid: r['amount_paid'] as int,
        balanceDue: r['balance_due'] as int,
        paymentStatus: PaymentStatus.parse(r['payment_status'] as String),
        printCount: r['print_count'] as int,
        syncStatus: r['sync_status'] as String,
        billType: BillType.parse(r['bill_type'] as String?),
        items: items,
        payments: payments,
      );
}
