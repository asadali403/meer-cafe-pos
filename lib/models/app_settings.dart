enum PaperSize {
  mm58('58 mm thermal'),
  mm80('80 mm thermal'),
  a4('A4 / standard printer');

  final String label;
  const PaperSize(this.label);
  static PaperSize parse(String s) =>
      PaperSize.values.firstWhere((e) => e.name == s, orElse: () => PaperSize.mm80);
}

/// Typed view over the key/value `settings` table.
class AppSettings {
  final Map<String, String> values;
  const AppSettings(this.values);

  static const defaults = <String, String>{
    'cafe_name': 'Meer Cafe',
    'tagline': 'Our Circle. Your Place.',
    'show_tagline': '1',
    'address': '',
    'phone': '',
    'thank_you': 'Thank you for visiting Meer Cafe!',
    'show_qr': '1',
    'paper': 'mm80',
    'printer_name': '',
    'auto_print': '1',
    'logo_path': '',
    'rounding_step': '0',
    'cashier_max_discount_pct': '10',
    'sync_enabled': '0',
    'sync_url': '',
    'sync_secret': '',
    'invoice_prefix': 'MC',
    'kitchen_ticket': '1',
    'kitchen_printer_name': '',
    'cashier_custom_items': '0',
  };

  String _s(String k) => values[k] ?? defaults[k] ?? '';
  bool _b(String k) => _s(k) == '1';
  int _i(String k) => int.tryParse(_s(k)) ?? int.parse(defaults[k] ?? '0');

  String get cafeName => _s('cafe_name');
  String get tagline => _s('tagline');
  bool get showTagline => _b('show_tagline');
  String get address => _s('address');
  String get phone => _s('phone');
  String get thankYou => _s('thank_you');
  bool get showQr => _b('show_qr');
  PaperSize get paper => PaperSize.parse(_s('paper'));
  String get printerName => _s('printer_name');
  bool get autoPrint => _b('auto_print');
  String get logoPath => _s('logo_path');

  /// Cash rounding step in paisa (0 = no rounding). E.g. 500 = round to nearest Rs. 5.
  int get roundingStep => _i('rounding_step');
  int get cashierMaxDiscountPct => _i('cashier_max_discount_pct');
  bool get syncEnabled => _b('sync_enabled');
  String get syncUrl => _s('sync_url');
  String get syncSecret => _s('sync_secret');
  String get invoicePrefix {
    final p = _s('invoice_prefix').trim().toUpperCase();
    return p.isEmpty ? 'MC' : p;
  }

  /// Print a kitchen ticket (food items, no prices) for the chef with each bill.
  bool get kitchenTicket => _b('kitchen_ticket');

  /// Kitchen printer; empty = use the receipt printer.
  String get kitchenPrinterName => _s('kitchen_printer_name');

  /// Whether cashiers may add hand-typed custom items (admins always can).
  bool get cashierCustomItems => _b('cashier_custom_items');

  bool get syncConfigured => syncEnabled && syncUrl.startsWith('https://') && syncSecret.length >= 16;
}
