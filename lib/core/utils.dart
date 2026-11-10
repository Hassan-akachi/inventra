import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Record ids are made on the phone, so offline records never clash on sync.
String newId() => _uuid.v4();

String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Supported currencies and their symbols.
const supportedCurrencies = <String, String>{
  'NGN': '₦',
  'USD': r'$',
  'GBP': '£',
  'EUR': '€',
  'CNY': '¥',
};

const currencyNames = <String, String>{
  'NGN': 'Nigerian naira',
  'USD': 'US dollar',
  'GBP': 'British pound',
  'EUR': 'Euro',
  'CNY': 'Chinese yuan',
};

/// Money is stored as whole minor units (kobo, cents, fen) to avoid rounding errors.
class Money {
  Money._();

  /// "1,250.50" -> 125050. Returns null for empty or invalid input.
  static int? parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }

  static String format(int? minor, String currency) {
    if (minor == null) return '—';
    final f = NumberFormat.currency(
      symbol: supportedCurrencies[currency] ?? '$currency ',
      decimalDigits: 2,
    );
    return f.format(minor / 100);
  }

  /// For pre-filling a text field.
  static String toInput(int? minor) =>
      minor == null ? '' : (minor / 100).toStringAsFixed(2);
}

/// `yyyy-MM-dd` used for expiry dates.
String dateOnly(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('d MMM yyyy, HH:mm').format(d.toLocal());
}

int? parseInt(String text) => int.tryParse(text.trim());

String? emptyToNull(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}
