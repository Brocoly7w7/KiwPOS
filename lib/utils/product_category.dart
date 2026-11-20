class ProductCategory {
  ProductCategory._();

  static const String groceries = 'abarrotes';
  static const String fresh = 'productos_frescos';

  static String normalize(dynamic value, {dynamic barcode}) {
    final raw = value?.toString().trim().toLowerCase() ?? '';

    if (raw == groceries || raw == fresh) {
      return raw;
    }

    final normalizedBarcode = barcode?.toString().trim() ?? '';
    return normalizedBarcode.isNotEmpty ? groceries : fresh;
  }

  static bool isGrocery(dynamic category) {
    return normalize(category) == groceries;
  }

  static String unit(dynamic category) {
    return isGrocery(category) ? 'pz' : 'kg';
  }

  static String singularUnit(dynamic category) {
    return isGrocery(category) ? 'pieza' : 'kg';
  }

  static String label(dynamic category) {
    return isGrocery(category) ? 'Abarrotes' : 'Productos frescos';
  }

  static String description(dynamic category) {
    return isGrocery(category)
        ? 'Se vende por piezas.'
        : 'Se vende por peso en kilogramos.';
  }

  static double normalizeQuantity(
    dynamic value,
    dynamic category, {
    double fallback = 1.0,
  }) {
    final parsed =
        value is num
            ? value.toDouble()
            : double.tryParse(
                  value?.toString().replaceAll(',', '.').trim() ?? '',
                ) ??
                fallback;

    if (isGrocery(category)) {
      final rounded = parsed.roundToDouble();
      return rounded < 1 ? 1.0 : rounded;
    }

    return parsed <= 0 ? fallback : parsed;
  }

  static String _formatFreshQuantity(dynamic value, {required int decimals}) {
    final quantity =
        value is num
            ? value.toDouble()
            : double.tryParse(
                  value?.toString().replaceAll(',', '.').trim() ?? '',
                ) ??
                0.0;

    var text = quantity.toStringAsFixed(decimals);

    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }

    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }

    return text;
  }

  /// Formato final para tickets, PDF e impresión: máximo 2 decimales.
  static String formatQuantity(dynamic value, dynamic category) {
    final quantity =
        value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;

    if (isGrocery(category)) {
      return '${quantity.round()}pz';
    }

    return '${_formatFreshQuantity(quantity, decimals: 2)}kg';
  }

  /// Formato de trabajo para Caja y modales: máximo 3 decimales.
  static String formatQuantityForCart(dynamic value, dynamic category) {
    final quantity =
        value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;

    if (isGrocery(category)) {
      return '${quantity.round()}pz';
    }

    return '${_formatFreshQuantity(quantity, decimals: 3)}kg';
  }

  /// Solo el número, sin unidad, para rellenar campos editables.
  static String formatEditableQuantity(dynamic value, dynamic category) {
    final formatted = formatQuantityForCart(value, category);
    return formatted.replaceAll('kg', '').replaceAll('pz', '');
  }
}
