import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/services/movein_generator.dart';

class MoveinExportPackage {
  final Directory directory;
  final File documentFile;
  final File parameterFile;
  final int recordCount;

  const MoveinExportPackage({
    required this.directory,
    required this.documentFile,
    required this.parameterFile,
    required this.recordCount,
  });
}

class MoveinExportService {
  static const _supportedBuckets = <String>[
    'invoices',
    'invoice_tax_receipt',
    'receipts',
    'credit_notes',
  ];

  static Future<MoveinExportPackage> exportForUser({
    required FirebaseFirestore firestore,
    required String userId,
    required String fromDate,
    required String toDate,
    required MoveinAccountingSettings settings,
    required Directory rootDirectory,
  }) async {
    final snapshot = await firestore
        .collectionGroup('files')
        .where('bucket', whereIn: _supportedBuckets)
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: fromDate)
        .where('date', isLessThanOrEqualTo: toDate)
        .orderBy('date')
        .orderBy('timestamp')
        .get();

    final logs = _deduplicate(snapshot.docs);
    final invoiceData = await _loadInvoices(
      firestore: firestore,
      userId: userId,
      logs: logs,
    );
    final documents = logs
        .map((log) => _sourceDocument(log.data(), invoiceData))
        .whereType<MoveinSourceDocument>()
        .toList(growable: false);

    final generated = MoveinGenerator.generate(
      documents: documents,
      settings: settings,
    );
    final now = DateTime.now();
    final stamp =
        '${_compactDate(now)}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final directory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}MOVEIN_$stamp',
    );
    await directory.create(recursive: true);

    final documentFile = File(
      '${directory.path}${Platform.pathSeparator}MOVEIN.doc',
    );
    final parameterFile = File(
      '${directory.path}${Platform.pathSeparator}MOVEIN.prm',
    );
    await documentFile.writeAsBytes(generated.documentBytes, flush: true);
    await parameterFile.writeAsBytes(generated.parameterBytes, flush: true);

    return MoveinExportPackage(
      directory: directory,
      documentFile: documentFile,
      parameterFile: parameterFile,
      recordCount: generated.recordCount,
    );
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _deduplicate(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
  ) {
    final result = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final log in logs) {
      final data = log.data();
      final key = (data['invoiceDocId'] ?? log.reference.path).toString();
      result[key] = log;
    }
    final sorted = result.values.toList();
    sorted.sort((left, right) {
      final leftData = left.data();
      final rightData = right.data();
      final dateComparison = (leftData['date'] ?? '').toString().compareTo(
        (rightData['date'] ?? '').toString(),
      );
      if (dateComparison != 0) return dateComparison;
      final leftTime = leftData['timestamp'];
      final rightTime = rightData['timestamp'];
      if (leftTime is Timestamp && rightTime is Timestamp) {
        return leftTime.compareTo(rightTime);
      }
      return 0;
    });
    return sorted;
  }

  static Future<Map<String, Map<String, dynamic>>> _loadInvoices({
    required FirebaseFirestore firestore,
    required String userId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
  }) async {
    final ids = logs
        .map((log) => (log.data()['invoiceDocId'] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final snapshots = await Future.wait(
      ids.map(
        (id) => firestore
            .collection('users')
            .doc(userId)
            .collection('invoices')
            .doc(id)
            .get(),
      ),
    );
    return {
      for (final snapshot in snapshots)
        if (snapshot.exists && snapshot.data() != null)
          snapshot.id: snapshot.data()!,
    };
  }

  static MoveinSourceDocument? _sourceDocument(
    Map<String, dynamic> log,
    Map<String, Map<String, dynamic>> invoices,
  ) {
    final invoiceId = (log['invoiceDocId'] ?? '').toString();
    final invoice = invoices[invoiceId] ?? const <String, dynamic>{};
    final type = (invoice['type'] ?? invoice['docType'] ?? log['docType'] ?? '')
        .toString();
    if (!const <String>{
      'invoice',
      'credit_note',
      'invoice_receipt',
      'receipt',
    }.contains(type)) {
      return null;
    }

    final issueDate = _date(log['issueDate'] ?? log['date'] ?? invoice['date']);
    final dueDate = _date(
      log['paymentDueDate'] ?? invoice['paymentDueDate'] ?? issueDate,
    );
    final clientDetails = log['clientDetails'] is Map
        ? Map<String, dynamic>.from(log['clientDetails'] as Map)
        : const <String, dynamic>{};
    final clientTaxId = _nineDigitTaxId(
      invoice['clientTaxId'] ??
          log['clientTaxId'] ??
          clientDetails['taxId'] ??
          clientDetails['id'],
    );
    final externalClientNumber =
        (invoice['externalClientNumber'] ?? log['externalClientNumber'] ?? '')
            .toString()
            .trim();
    final accountKey = externalClientNumber.isNotEmpty
        ? externalClientNumber
        : clientTaxId;
    final total = _number(
      log['grandTotal'] ??
          log['subtotalAfterTax'] ??
          invoice['amount'] ??
          log['amount'],
    );
    final vat = _number(log['vatAmount'] ?? invoice['vatAmount']);
    final allocation =
        (invoice['allocationNumber'] ??
                invoice['taxAuthorityAllocationNumber'] ??
                log['allocationNumber'] ??
                log['taxAuthorityAllocationNumber'] ??
                '')
            .toString();
    final reference = _digits(
      log['documentNumber'] ??
          log['sequenceNumber'] ??
          invoice['sequenceNumber'] ??
          invoice['invoiceNumber'],
    );
    if (reference.isEmpty || issueDate.isEmpty || total.abs() < 0.005) {
      return null;
    }

    return MoveinSourceDocument(
      documentType: type,
      reference: reference,
      issueDate: issueDate,
      dueDate: dueDate,
      clientAccountKey: accountKey,
      clientTaxId: clientTaxId,
      totalAmount: total,
      vatAmount: vat,
      allocationNumber: allocation,
      payments: _payments(log, invoice, total),
    );
  }

  static List<MoveinPayment> _payments(
    Map<String, dynamic> log,
    Map<String, dynamic> invoice,
    double total,
  ) {
    final raw = log['paymentMethods'] ?? invoice['paymentMethods'];
    if (raw is List) {
      final payments = raw.whereType<Map>().map((item) {
        return MoveinPayment(
          method: (item['method'] ?? 'cash').toString(),
          amount: _number(item['amount'], fallback: total),
        );
      }).toList();
      if (payments.isNotEmpty) return payments;
    }
    return [
      MoveinPayment(
        method: (invoice['paymentMethod'] ?? log['paymentMethod'] ?? 'cash')
            .toString(),
        amount: total,
      ),
    ];
  }

  static String _date(Object? value) {
    if (value is Timestamp) return _compactDate(value.toDate());
    final digits = _digits(value);
    return digits.length == 8 ? digits : '';
  }

  static String _nineDigitTaxId(Object? value) {
    final digits = _digits(value);
    return digits.length == 9 ? digits : '';
  }

  static String _digits(Object? value) =>
      (value ?? '').toString().replaceAll(RegExp(r'\D'), '');

  static double _number(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ??
        fallback;
  }

  static String _compactDate(DateTime value) {
    return '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
  }
}
