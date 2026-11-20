import 'dart:typed_data';

import 'package:flutter_file_saver/flutter_file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/product_category.dart';

class TicketPdfService {
  TicketPdfService._();

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _money(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  static String _safeText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _shortText(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}…';
  }

  static String fileNameFor(Map<String, dynamic> ticket) {
    final rawId = _safeText(ticket['id'], fallback: 'sin_folio');
    final safeId = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'Ticket_$safeId.pdf';
  }

  static Future<Uint8List> buildTicket({
    required Map<String, dynamic> ticket,
    required String businessName,
    required String businessAddress,
  }) async {
    final document = pw.Document();

    final rawItems = ticket['items'];
    final items = rawItems is List ? List<dynamic>.from(rawItems) : <dynamic>[];

    final subtotal = _toDouble(ticket['subtotal'] ?? ticket['total']);
    final total = _toDouble(ticket['total'] ?? subtotal);
    final paid = _toDouble(ticket['pago'] ?? ticket['pagoCon']);
    final change = _toDouble(ticket['cambio']);

    final itemCount = items.isEmpty
        ? _toInt(ticket['articulos'], fallback: 1)
        : items.length;

    final estimatedHeightMm = 135.0 + (items.length * 9.0);
    final pageHeightMm = estimatedHeightMm.clamp(150.0, 900.0).toDouble();

    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      pageHeightMm * PdfPageFormat.mm,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final normalStyle = pw.TextStyle(
      font: pw.Font.helvetica(),
      fontSize: 8,
      color: PdfColors.black,
    );

    final boldStyle = pw.TextStyle(
      font: pw.Font.helveticaBold(),
      fontSize: 8,
      color: PdfColors.black,
    );

    pw.Widget divider() {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(thickness: 0.6, color: PdfColors.grey600),
      );
    }

    pw.Widget summaryRow(
      String label,
      double value, {
      bool bold = false,
    }) {
      final style = bold ? boldStyle : normalStyle;

      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: style),
            pw.Text('\$${_money(value)}', style: style),
          ],
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('CANT', style: boldStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('PRECIO', style: boldStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('DESCRIPCIÓN', style: boldStyle),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              'IMPORTE',
              textAlign: pw.TextAlign.right,
              style: boldStyle,
            ),
          ),
        ],
      ),
    ];

    for (final rawItem in items) {
      final item = rawItem is Map
          ? Map<String, dynamic>.from(rawItem)
          : <String, dynamic>{};

      final quantity = _toDouble(item['kg']);
      final price = _toDouble(item['precio']);
      final amount = quantity * price;
      final category = ProductCategory.normalize(
        item['categoria'],
        barcode: item['codigoBarras'],
      );
      final name = _shortText(
        _safeText(item['nombre'], fallback: 'Producto'),
        22,
      );

      tableRows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(
                ProductCategory.formatQuantity(quantity, category),
                style: normalStyle,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text('\$${_money(price)}', style: normalStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(name, style: normalStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(
                '\$${_money(amount)}',
                textAlign: pw.TextAlign.right,
                style: normalStyle,
              ),
            ),
          ],
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                _safeText(businessName, fallback: 'NEGOCIO').toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                _safeText(businessAddress),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'FOLIO: ${_safeText(ticket['id'], fallback: 'SIN FOLIO')}',
                style: normalStyle,
              ),
              pw.Text(
                'FECHA: ${_safeText(ticket['fecha'])}   '
                'HORA: ${_safeText(ticket['hora'])}',
                style: normalStyle,
              ),
              pw.Text(
                'CLIENTE: ${_safeText(ticket['cliente'], fallback: 'Cliente Gral')}',
                style: normalStyle,
              ),
              divider(),
              pw.Table(
                columnWidths: const {
                  0: pw.FlexColumnWidth(1.2),
                  1: pw.FlexColumnWidth(1.2),
                  2: pw.FlexColumnWidth(2.2),
                  3: pw.FlexColumnWidth(1.4),
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: tableRows,
              ),
              divider(),
              pw.Text('No. de productos: $itemCount', style: boldStyle),
              divider(),
              summaryRow('SUBTOTAL', subtotal),
              summaryRow('Pago con', paid),
              summaryRow('Cambio', change),
              divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(
                      font: pw.Font.helveticaBold(),
                      fontSize: 12,
                    ),
                  ),
                  pw.Text(
                    '\$${_money(total)}',
                    style: pw.TextStyle(
                      font: pw.Font.helveticaBold(),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                '*** GRACIAS POR SU COMPRA ***',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: pw.Font.helveticaOblique(),
                  fontSize: 8,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          );
        },
      ),
    );

    return document.save();
  }

  static Future<void> shareTicket({
    required Map<String, dynamic> ticket,
    required String businessName,
    required String businessAddress,
  }) async {
    final bytes = await buildTicket(
      ticket: ticket,
      businessName: businessName,
      businessAddress: businessAddress,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: fileNameFor(ticket),
    );
  }

  static Future<String> saveTicket({
    required Map<String, dynamic> ticket,
    required String businessName,
    required String businessAddress,
  }) async {
    final bytes = await buildTicket(
      ticket: ticket,
      businessName: businessName,
      businessAddress: businessAddress,
    );

    return FlutterFileSaver().writeFileAsBytes(
      fileName: fileNameFor(ticket),
      bytes: bytes,
    );
  }
}
