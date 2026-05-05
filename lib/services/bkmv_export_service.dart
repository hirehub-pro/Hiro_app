import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

class BkmvExportPackage {
  final String userId;
  final String businessName;
  final String businessNumber;
  final Directory directory;
  final File bkmvFile;
  final File iniFile;

  const BkmvExportPackage({
    required this.userId,
    required this.businessName,
    required this.businessNumber,
    required this.directory,
    required this.bkmvFile,
    required this.iniFile,
  });
}

class BkmvExportResult {
  final List<BkmvExportPackage> packages;
  final List<String> warnings;

  const BkmvExportResult({required this.packages, required this.warnings});

  bool get hasFiles => packages.isNotEmpty;
}

class _BusinessContext {
  final String userId;
  final String businessNumber;
  final String businessName;
  final String address;
  final String softwareName;
  final String softwareVersion;
  final String softwareRegistrationNumber;
  final String softwareMakerVatNumber;
  final String softwareMakerName;

  const _BusinessContext({
    required this.userId,
    required this.businessNumber,
    required this.businessName,
    required this.address,
    required this.softwareName,
    required this.softwareVersion,
    required this.softwareRegistrationNumber,
    required this.softwareMakerVatNumber,
    required this.softwareMakerName,
  });
}

class _InvoiceItemRecord {
  final String description;
  final double quantity;
  final double unitPrice;

  const _InvoiceItemRecord({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });
}

class BkmvExportService {
  static const _bucketNames = ['invoices', 'receipts', 'credit_notes'];

  static Future<BkmvExportResult> exportForUser({
    required FirebaseFirestore firestore,
    required String userId,
    required String fromDate,
    required String toDate,
    required Directory rootDirectory,
  }) async {
    final snapshots = await Future.wait(
      _bucketNames.map(
        (bucket) => firestore
            .collection('logs')
            .doc(bucket)
            .collection('files')
            .where('userId', isEqualTo: userId)
            .where('date', isGreaterThanOrEqualTo: fromDate)
            .where('date', isLessThanOrEqualTo: toDate)
            .orderBy('date')
            .orderBy('timestamp')
            .get(),
      ),
    );

    final logDocs = snapshots.expand((snapshot) => snapshot.docs).toList();
    if (logDocs.isEmpty) {
      return BkmvExportResult(
        packages: const [],
        warnings: ['No documents found for the selected range.'],
      );
    }

    final metadata = await _loadSystemMetadata(firestore);
    final context = await _loadBusinessContext(
      firestore: firestore,
      userId: userId,
      metadata: metadata,
    );

    if (context == null) {
      return BkmvExportResult(
        packages: const [],
        warnings: ['Missing business export details for user $userId.'],
      );
    }

    final package = await _buildPackage(
      firestore: firestore,
      context: context,
      logDocs: logDocs,
      fromDate: fromDate,
      toDate: toDate,
      rootDirectory: rootDirectory,
    );

    return BkmvExportResult(
      packages: package == null ? const [] : [package],
      warnings: package == null
          ? ['No valid records were generated for user $userId.']
          : const [],
    );
  }

  static Future<BkmvExportResult> exportForAllUsers({
    required FirebaseFirestore firestore,
    required String fromDate,
    required String toDate,
    required Directory rootDirectory,
  }) async {
    final snapshots = await Future.wait(
      _bucketNames.map(
        (bucket) => firestore
            .collection('logs')
            .doc(bucket)
            .collection('files')
            .where('date', isGreaterThanOrEqualTo: fromDate)
            .where('date', isLessThanOrEqualTo: toDate)
            .orderBy('date')
            .orderBy('timestamp')
            .get(),
      ),
    );

    final allDocs = snapshots.expand((snapshot) => snapshot.docs).toList();
    if (allDocs.isEmpty) {
      return BkmvExportResult(
        packages: const [],
        warnings: ['No documents found for the selected range.'],
      );
    }

    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in allDocs) {
      final userId = (doc.data()['userId'] ?? '').toString().trim();
      if (userId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(userId, () => []).add(doc);
    }

    final metadata = await _loadSystemMetadata(firestore);
    final packages = <BkmvExportPackage>[];
    final warnings = <String>[];

    for (final entry in grouped.entries) {
      final context = await _loadBusinessContext(
        firestore: firestore,
        userId: entry.key,
        metadata: metadata,
      );
      if (context == null) {
        warnings.add('Skipped ${entry.key}: missing business export details.');
        continue;
      }

      final package = await _buildPackage(
        firestore: firestore,
        context: context,
        logDocs: entry.value,
        fromDate: fromDate,
        toDate: toDate,
        rootDirectory: rootDirectory,
      );

      if (package == null) {
        warnings.add('Skipped ${entry.key}: no valid records were generated.');
        continue;
      }

      packages.add(package);
    }

    return BkmvExportResult(packages: packages, warnings: warnings);
  }

  static Future<BkmvExportPackage?> _buildPackage({
    required FirebaseFirestore firestore,
    required _BusinessContext context,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> logDocs,
    required String fromDate,
    required String toDate,
    required Directory rootDirectory,
  }) async {
    final sortedLogs = [...logDocs]..sort(_compareLogDocs);
    final invoiceMap = await _loadInvoicesForLogs(
      firestore: firestore,
      userId: context.userId,
      logDocs: sortedLogs,
    );

    final mainId = _randomDigits(15);
    final exportTimestamp = DateTime.now();
    final exportDate = _formatCompactDate(exportTimestamp);
    final exportTime = _formatTime(exportTimestamp);
    final exportDirectory = await _createExportDirectory(
      rootDirectory: rootDirectory,
      businessNumber: context.businessNumber,
      exportTimestamp: exportTimestamp,
    );

    final records = <String>[];
    final recordCounts = <String, int>{};
    var recordNumber = 1;
    var linkNumber = 1;
    final documentLinkIds = <String, int>{};

    void addRecord(String code, String line) {
      records.add(line);
      recordCounts.update(
        code,
        (currentCount) => currentCount + 1,
        ifAbsent: () => 1,
      );
      recordNumber += 1;
    }

    addRecord(
      'A100',
      _buildA100(
        recordNumber: recordNumber,
        businessNumber: context.businessNumber,
        mainId: mainId,
      ),
    );

    for (final logDoc in sortedLogs) {
      final logData = logDoc.data();
      final documentNumber = (logData['documentNumber'] ?? '').toString();
      if (documentNumber.isEmpty) {
        continue;
      }

      final invoiceData = invoiceMap[documentNumber] ?? logData;
      final docType = (invoiceData['type'] ?? logData['docType'] ?? '')
          .toString();
      final bucket = (logData['bucket'] ?? '').toString();
      final docTypeCode = _mapDocumentType(docType);
      if (docTypeCode == null) {
        continue;
      }

      final amount = _num(invoiceData['amount'] ?? logData['amount']);
      final vatAmount = _num(invoiceData['vatAmount'] ?? logData['vatAmount']);
      final subtotal = amount;
      final discount = _num(invoiceData['discountAmount'] ?? 0);

      final documentDate = _normalizeDate(
        (invoiceData['date'] ?? logData['date']).toString(),
      );
      final documentTime = _timestampToTime(
        invoiceData['createdAt'] ?? logData['timestamp'],
      );
      final clientName =
          (invoiceData['clientName'] ?? logData['clientName'] ?? '').toString();
      final clientAddress =
          (invoiceData['clientAddress'] ?? logData['clientAddress'] ?? '')
              .toString();
      final clientPhone = _normalizeIsraeliPhone(
        (invoiceData['clientPhone'] ?? logData['clientPhone'] ?? '').toString(),
      );
      final customerKey =
          (logData['customerId'] ?? invoiceData['customerId'] ?? clientName)
              .toString();
      final linkKey = '$documentNumber|$documentDate';
      final linkId = documentLinkIds.putIfAbsent(linkKey, () => linkNumber++);

      final includesHeader =
          bucket == 'invoices' ||
          bucket == 'credit_notes' ||
          (bucket == 'receipts' && docType == 'receipt');

      if (includesHeader) {
        addRecord(
          'C100',
          _buildC100(
            recordNumber: recordNumber,
            businessNumber: context.businessNumber,
            documentType: docTypeCode,
            documentNumber: documentNumber,
            issueDate: documentDate,
            issueTime: documentTime,
            clientName: clientName,
            clientAddress: clientAddress,
            clientPhone: clientPhone,
            clientVatNumber: (invoiceData['customerVatNumber'] ?? '')
                .toString(),
            valueDate: documentDate,
            subtotal: subtotal, 
            discount: discount,
            vatAmount: vatAmount,
            totalAmount: amount,
            customerKey: customerKey,
            documentDate: documentDate,
            linkId: linkId,
          ),
        );
      }

      if (bucket == 'invoices' || bucket == 'credit_notes') {
        final items = _extractItems(invoiceData, subtotal, vatAmount);
        final discountAmount = _num(invoiceData['discountAmount']);
        var detailLine = 1;
        for (final item in items) {
          addRecord(
            'D110',
            _buildD110(
              recordNumber: recordNumber,
              businessNumber: context.businessNumber,
              documentType: docTypeCode,
              documentNumber: documentNumber,
              lineNumber: detailLine,
              baseDocumentType: docType == 'credit_note' ? 305 : null,
              baseDocumentNumber: _creditOriginalNumber(invoiceData),
              description: item.description,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              discountAmount: detailLine == 1 ? discountAmount : 0,
              lineTotal:
                  (item.quantity * item.unitPrice) -
                  (detailLine == 1 ? discountAmount : 0),
              vatRate: vatAmount > 0 ? 17 : 0,
              documentDate: documentDate,
              linkId: linkId,
            ),
          );
          detailLine += 1;
        }
      }

      if (bucket == 'receipts') {
        final paymentDetails = _paymentDetails(invoiceData);
        addRecord(
          'D120',
          _buildD120(
            recordNumber: recordNumber,
            businessNumber: context.businessNumber,
            documentType: docTypeCode,
            documentNumber: documentNumber,
            lineNumber: 1,
            paymentType: paymentDetails.typeCode,
            bankNumber: paymentDetails.bankNumber,
            branchNumber: paymentDetails.branchNumber,
            accountNumber: paymentDetails.accountNumber,
            chequeNumber: paymentDetails.chequeNumber,
            paymentDate: paymentDetails.paymentDate.isEmpty
                ? documentDate
                : paymentDetails.paymentDate,
            amount: amount,
            creditCompany: paymentDetails.creditCompanyCode,
            cardName: paymentDetails.cardName,
            creditDealType: paymentDetails.creditDealType,
            documentDate: documentDate,
            linkId: linkId,
          ),
        );
      }
    }

    final totalRecords = records.length + 1;
    records.add(
      _buildZ900(
        recordNumber: totalRecords,
        businessNumber: context.businessNumber,
        mainId: mainId,
        totalRecords: totalRecords,
      ),
    );

    if (records.length < 2) {
      return null;
    }

    final iniLines = <String>[
      _buildA000(
        totalBkmvRecords: records.length,
        context: context,
        mainId: mainId,
        exportDirectory: exportDirectory.path,
        fromDate: fromDate,
        toDate: toDate,
        exportDate: exportDate,
        exportTime: exportTime,
      ),
    ];

    for (final code in ['C100', 'D110', 'D120']) {
      final count = recordCounts[code];
      if (count != null && count > 0) {
        iniLines.add(_fitAlpha(code, 4) + _fitNumeric(count.toString(), 15));
      }
    }

    final bkmvFile = File(
      '${exportDirectory.path}${Platform.pathSeparator}BKMVDATA.txt',
    );
    final iniFile = File(
      '${exportDirectory.path}${Platform.pathSeparator}INI.txt',
    );

    await bkmvFile.writeAsString('${records.join('\r\n')}\r\n');
    await iniFile.writeAsString('${iniLines.join('\r\n')}\r\n');

    return BkmvExportPackage(
      userId: context.userId,
      businessName: context.businessName,
      businessNumber: context.businessNumber,
      directory: exportDirectory,
      bkmvFile: bkmvFile,
      iniFile: iniFile,
    );
  }

  static Future<Map<String, dynamic>> _loadSystemMetadata(
    FirebaseFirestore firestore,
  ) async {
    final systemDoc = await firestore
        .collection('metadata')
        .doc('system')
        .get();
    return systemDoc.data() ?? <String, dynamic>{};
  }

  static Future<_BusinessContext?> _loadBusinessContext({
    required FirebaseFirestore firestore,
    required String userId,
    required Map<String, dynamic> metadata,
  }) async {
    final verificationDoc = await firestore
        .collection('users')
        .doc(userId)
        .collection('verification_info')
        .doc('latest')
        .get();
    final verificationData = verificationDoc.data() ?? <String, dynamic>{};

    final userDoc = await firestore.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? <String, dynamic>{};

    final businessNumber = _digitsOnly(
      (verificationData['businessId'] ??
              verificationData['businessNumber'] ??
              userData['businessNumber'])
          .toString(),
    );
    final businessName =
        (verificationData['businessName'] ?? userData['businessName'] ?? '')
            .toString()
            .trim();

    if (businessNumber.isEmpty || businessName.isEmpty) {
      return null;
    }

    return _BusinessContext(
      userId: userId,
      businessNumber: businessNumber,
      businessName: businessName,
      address: (verificationData['address'] ?? userData['address'] ?? '')
          .toString(),
      softwareName: (metadata['appName'] ?? 'hiro').toString(),
      softwareVersion: (metadata['minRequiredVersion'] ?? '1.0.0').toString(),
      softwareRegistrationNumber: _digitsOnly(
        (metadata['softwareRegistrationNumber'] ?? '').toString(),
      ),
      softwareMakerVatNumber: _digitsOnly(
        (metadata['softwareMakerVatNumber'] ?? '').toString(),
      ),
      softwareMakerName:
          (metadata['softwareMakerName'] ?? metadata['appName'] ?? 'hiro')
              .toString(),
    );
  }

  static Future<Map<String, Map<String, dynamic>>> _loadInvoicesForLogs({
    required FirebaseFirestore firestore,
    required String userId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> logDocs,
  }) async {
    final numbers = <String>{
      for (final doc in logDocs)
        (doc.data()['documentNumber'] ?? '').toString().trim(),
    }..remove('');

    if (numbers.isEmpty) {
      return const {};
    }

    final snapshots = await Future.wait(
      numbers.map(
        (number) => firestore
            .collection('users')
            .doc(userId)
            .collection('invoices')
            .doc(number)
            .get(),
      ),
    );

    final result = <String, Map<String, dynamic>>{};
    for (final snapshot in snapshots) {
      if (snapshot.exists && snapshot.data() != null) {
        result[snapshot.id] = snapshot.data()!;
      }
    }
    return result;
  }

  static Future<Directory> _createExportDirectory({
    required Directory rootDirectory,
    required String businessNumber,
    required DateTime exportTimestamp,
  }) async {
    final businessKey = _fitNumeric(businessNumber, 8);
    final yearKey = exportTimestamp.year.toString().substring(2);
    final timestampKey =
        '${exportTimestamp.month.toString().padLeft(2, '0')}${exportTimestamp.day.toString().padLeft(2, '0')}${exportTimestamp.hour.toString().padLeft(2, '0')}${exportTimestamp.minute.toString().padLeft(2, '0')}';
    final path =
        '${rootDirectory.path}${Platform.pathSeparator}$businessKey.$yearKey${Platform.pathSeparator}$timestampKey';
    final directory = Directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  static String _buildA000({
    required int totalBkmvRecords,
    required _BusinessContext context,
    required String mainId,
    required String exportDirectory,
    required String fromDate,
    required String toDate,
    required String exportDate,
    required String exportTime,
  }) {
    final address = _splitAddress(context.address);
    return _joinFixed([
      _fitAlpha('A000', 4),
      _fitAlpha('', 5),
      _fitNumeric(totalBkmvRecords.toString(), 15),
      _fitNumeric(context.businessNumber, 9),
      _fitNumeric(mainId, 15),
      _fitAlpha('&OF1.31&', 8),
      _fitNumeric(context.softwareRegistrationNumber, 8),
      _fitAlpha(context.softwareName, 20),
      _fitAlpha(context.softwareVersion, 20),
      _fitNumeric(context.softwareMakerVatNumber, 9),
      _fitAlpha(context.softwareMakerName, 20),
      _fitNumeric('2', 1),
      _fitAlpha('', 50),
      _fitNumeric('0', 1),
      _fitNumeric('0', 1),
      _fitNumeric(context.businessNumber, 9),
      _fitNumeric('', 9),
      _fitAlpha('', 10),
      _fitAlpha(context.businessName, 50),
      _fitAlpha(address.street, 50),
      _fitAlpha(address.houseNumber, 10),
      _fitAlpha(address.city, 30),
      _fitAlpha(address.postalCode, 8),
      _fitNumeric('', 4),
      _fitNumeric(fromDate, 8),
      _fitNumeric(toDate, 8),
      _fitNumeric(exportDate, 8),
      _fitNumeric(exportTime, 4),
      _fitNumeric('0', 1),
      _fitNumeric('1', 1),
      _fitAlpha('zip', 20),
      _fitAlpha('ILS', 3),
      _fitNumeric('0', 1),
      _fitAlpha('', 46),
    ], 466);
  }

  static String _buildA100({
    required int recordNumber,
    required String businessNumber,
    required String mainId,
  }) {
    return _joinFixed([
      _fitAlpha('A100', 4),
      _fitNumeric(recordNumber.toString(), 9),
      _fitNumeric(businessNumber, 9),
      _fitNumeric(mainId, 15),
      _fitAlpha('&OF1.31&', 8),
      _fitAlpha('', 50),
    ], 95);
  }

  static String _buildZ900({
    required int recordNumber,
    required String businessNumber,
    required String mainId,
    required int totalRecords,
  }) {
    return _joinFixed([
      _fitAlpha('Z900', 4),
      _fitNumeric(recordNumber.toString(), 9),
      _fitNumeric(businessNumber, 9),
      _fitNumeric(mainId, 15),
      _fitAlpha('&OF1.31&', 8),
      _fitNumeric(totalRecords.toString(), 15),
      _fitAlpha('', 50),
    ], 110);
  }

  static String _buildC100({
    required int recordNumber,
    required String businessNumber,
    required int documentType,
    required String documentNumber,
    required String issueDate,
    required String issueTime,
    required String clientName,
    required String clientAddress,
    required String clientPhone,
    required String clientVatNumber,
    required String valueDate,
    required double subtotal,
    required double discount,
    required double vatAmount,
    required double totalAmount,
    required String customerKey,
    required String documentDate,
    required int linkId,
  }) {
    final address = _splitAddress(clientAddress);
    return _joinFixed([
      _fitAlpha('C100', 4),
      _fitNumeric(recordNumber.toString(), 9),
      _fitNumeric(businessNumber, 9),
      _fitNumeric(documentType.toString(), 3),
      _fitAlpha(documentNumber, 20),
      _fitNumeric(issueDate, 8),
      _fitNumeric(issueTime, 4),
      _fitAlpha(clientName, 50),
      _fitAlpha(address.street, 50),
      _fitAlpha(address.houseNumber, 10),
      _fitAlpha(address.city, 30),
      _fitAlpha(address.postalCode, 8),
      _fitAlpha('', 30),
      _fitAlpha('', 2),
      _fitAlpha(clientPhone, 15),
      _fitNumeric(clientVatNumber, 9),
      _fitNumeric(valueDate, 8),
      _fitSignedAmount(totalAmount, wholeDigits: 12, decimalDigits: 2),
      _fitAlpha('ILS', 3),
      _fitSignedAmount(totalAmount+discount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(discount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(subtotal-vatAmount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(vatAmount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(totalAmount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(0, wholeDigits: 9, decimalDigits: 2),
      _fitAlpha(customerKey, 15),
      _fitAlpha('', 10),
      _fitAlpha('', 1),
      _fitNumeric(documentDate, 8),
      _fitAlpha('', 7),
      _fitAlpha('', 9),
      _fitNumeric(linkId.toString(), 7),
      _fitAlpha('', 13),
    ], 444);
  }

  static String _buildD110({
    required int recordNumber,
    required String businessNumber,
    required int documentType,
    required String documentNumber,
    required int lineNumber,
    required int? baseDocumentType,
    required String? baseDocumentNumber,
    required String description,
    required double quantity,
    required double unitPrice,
    required double discountAmount,
    required double lineTotal,
    required int vatRate,
    required String documentDate,
    required int linkId,
  }) {
    return _joinFixed([
      _fitAlpha('D110', 4),
      _fitNumeric(recordNumber.toString(), 9),
      _fitNumeric(businessNumber, 9),
      _fitNumeric(documentType.toString(), 3),
      _fitAlpha(documentNumber, 20),
      _fitNumeric(lineNumber.toString(), 4),
      _fitNumeric(baseDocumentType?.toString() ?? '', 3),
      _fitAlpha(baseDocumentNumber ?? '', 20),
      _fitNumeric('1', 1),
      _fitAlpha('', 20),
      _fitAlpha(description, 30),
      _fitAlpha('', 50),
      _fitAlpha('', 30),
      _fitAlpha('UNIT', 20),
      _fitSignedAmount(quantity, wholeDigits: 12, decimalDigits: 4),
      _fitSignedAmount(unitPrice, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(discountAmount, wholeDigits: 12, decimalDigits: 2),
      _fitSignedAmount(lineTotal, wholeDigits: 12, decimalDigits: 2),
      _fitNumeric(vatRate.toString(), 4),
      _fitAlpha('', 7),
      _fitNumeric(documentDate, 8),
      _fitNumeric(linkId.toString(), 7),
      _fitAlpha('', 7),
      _fitAlpha('', 21),
    ], 339);
  }

  static String _buildD120({
    required int recordNumber,
    required String businessNumber,
    required int documentType,
    required String documentNumber,
    required int lineNumber,
    required int paymentType,
    required String bankNumber,
    required String branchNumber,
    required String accountNumber,
    required String chequeNumber,
    required String paymentDate,
    required double amount,
    required int? creditCompany,
    required String cardName,
    required int? creditDealType,
    required String documentDate,
    required int linkId,
  }) {
    return _joinFixed([
      _fitAlpha('D120', 4),
      _fitNumeric(recordNumber.toString(), 9),
      _fitNumeric(businessNumber, 9),
      _fitNumeric(documentType.toString(), 3),
      _fitAlpha(documentNumber, 20),
      _fitNumeric(lineNumber.toString(), 4),
      _fitNumeric(paymentType.toString(), 1),
      _fitNumeric(bankNumber, 10),
      _fitNumeric(branchNumber, 10),
      _fitNumeric(accountNumber, 15),
      _fitNumeric(chequeNumber, 10),
      _fitNumeric(paymentDate, 8),
      _fitSignedAmount(amount, wholeDigits: 12, decimalDigits: 2),
      _fitNumeric(creditCompany?.toString() ?? '', 1),
      _fitAlpha(cardName, 20),
      _fitNumeric(creditDealType?.toString() ?? '', 1),
      _fitAlpha('', 7),
      _fitNumeric(documentDate, 8),
      _fitNumeric(linkId.toString(), 7),
      _fitAlpha('', 60),
    ], 222);
  }

  static List<_InvoiceItemRecord> _extractItems(
    Map<String, dynamic> invoiceData,
    double subtotal,
    double vatAmount,
  ) {
    final rawItems = invoiceData['items'];
    if (rawItems is List) {
      final items = rawItems
          .whereType<Map>()
          .map(
            (item) => _InvoiceItemRecord(
              description: (item['description'] ?? 'Item').toString(),
              quantity: _num(item['quantity'], fallback: 1),
              unitPrice: _num(item['unitPriceWithoutTax'] ?? item['price']),
            ),
          )
          .where((item) => item.quantity > 0)
          .toList();
      if (items.isNotEmpty) {
        return items;
      }
    }

    final fallbackSubtotal = vatAmount > 0
        ? subtotal
        : _num(invoiceData['amount']).abs();
    return [
      _InvoiceItemRecord(
        description: 'General item',
        quantity: 1,
        unitPrice: fallbackSubtotal,
      ),
    ];
  }

  static _PaymentDetails _paymentDetails(Map<String, dynamic> invoiceData) {
    final paymentMethod = (invoiceData['paymentMethod'] ?? 'cash').toString();
    final transferDetails = (invoiceData['transferDetails'] ?? '').toString();
    final checkNumber = (invoiceData['checkNumber'] ?? '').toString();

    switch (paymentMethod) {
      case 'credit':
        return const _PaymentDetails(
          typeCode: 3,
          creditCompanyCode: 1,
          cardName: 'CREDIT',
          creditDealType: 1,
        );
      case 'transfer':
        return _PaymentDetails(
          typeCode: 4,
          bankNumber: _extractTransferPart(transferDetails, 0),
          branchNumber: _extractTransferPart(transferDetails, 1),
          accountNumber: _digitsOnly(transferDetails),
          paymentDate: _extractTransferDate(transferDetails),
        );
      case 'check':
        return _PaymentDetails(
          typeCode: 2,
          bankNumber: _extractTransferPart(checkNumber, 0),
          branchNumber: _extractTransferPart(checkNumber, 1),
          chequeNumber: _digitsOnly(checkNumber),
          paymentDate: _extractTransferDate(checkNumber),
        );
      case 'cash':
      default:
        return const _PaymentDetails(typeCode: 1);
    }
  }

  static String? _creditOriginalNumber(Map<String, dynamic> invoiceData) {
    final creditNoteLegal = invoiceData['creditNoteLegal'];
    if (creditNoteLegal is Map) {
      final originalNumber = (creditNoteLegal['originalInvoiceNumber'] ?? '')
          .toString()
          .trim();
      if (originalNumber.isNotEmpty) {
        return originalNumber;
      }
    }
    return null;
  }

  static int? _mapDocumentType(String docType) {
    switch (docType) {
      case 'invoice':
        return 305;
      case 'invoice_receipt':
        return 320;
      case 'credit_note':
        return 330;
      case 'receipt':
        return 400;
      default:
        return null;
    }
  }

  static int _compareLogDocs(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aData = a.data();
    final bData = b.data();

    final dateCompare = (aData['date'] ?? '').toString().compareTo(
      (bData['date'] ?? '').toString(),
    );
    if (dateCompare != 0) {
      return dateCompare;
    }

    final aTimestamp = aData['timestamp'] as Timestamp?;
    final bTimestamp = bData['timestamp'] as Timestamp?;
    if (aTimestamp == null && bTimestamp == null) {
      return 0;
    }
    if (aTimestamp == null) {
      return -1;
    }
    if (bTimestamp == null) {
      return 1;
    }
    return aTimestamp.compareTo(bTimestamp);
  }

  static _AddressParts _splitAddress(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final street = parts.isNotEmpty ? parts[0] : '';
    final city = parts.length > 1 ? parts[1] : '';
    final postalCode = parts.length > 2 ? _digitsOnly(parts[2]) : '';
    final houseMatch = RegExp(r'(\d+[A-Za-z]?)').firstMatch(street);
    final houseNumber = houseMatch?.group(1) ?? '';
    final cleanStreet = houseNumber.isEmpty
        ? street
        : street.replaceFirst(houseNumber, '').trim();

    return _AddressParts(
      street: cleanStreet.isEmpty ? street : cleanStreet,
      houseNumber: houseNumber,
      city: city,
      postalCode: postalCode,
    );
  }

  static String _joinFixed(List<String> parts, int length) {
    final line = parts.join();
    if (line.length != length) {
      throw StateError('Invalid record length $length, got ${line.length}.');
    }
    return line;
  }

  static String _fitAlpha(String value, int length) {
    final normalized = value
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    if (length == 0) {
      return '';
    }
    if (normalized.length >= length) {
      return normalized.substring(0, length);
    }
    return normalized.padRight(length, ' ');
  }

  static String _fitNumeric(String value, int length) {
    if (length == 0) {
      return '';
    }
    final digits = _digitsOnly(value);
    if (digits.isEmpty) {
      return ''.padLeft(length, '0');
    }
    if (digits.length >= length) {
      return digits.substring(digits.length - length);
    }
    return digits.padLeft(length, '0');
  }

  static String _fitSignedAmount(
    num value, {
    required int wholeDigits,
    required int decimalDigits,
  }) {
    final factor = pow(10, decimalDigits).toInt();
    final scaled = (value.abs() * factor).round().toString();
    final digitsLength = wholeDigits + decimalDigits;
    final sign = value < 0 ? '-' : '+';
    final padded = scaled.padLeft(digitsLength, '0');
    if (padded.length > digitsLength) {
      return sign + padded.substring(padded.length - digitsLength);
    }
    return '$sign$padded';
  }

  static String _normalizeDate(String raw) {
    final digits = _digitsOnly(raw);
    if (digits.length != 8) {
      throw StateError(
        'Invalid date "$raw". Dates must be exactly YYYYMMDD with 8 digits.',
      );
    }
    final year = int.parse(digits.substring(0, 4));
    final month = int.parse(digits.substring(4, 6));
    final day = int.parse(digits.substring(6, 8));
    final parsed = DateTime.tryParse(
      '$year-${digits.substring(4, 6)}-${digits.substring(6, 8)}',
    );
    if (parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      throw StateError(
        'Invalid date "$raw". Dates must be valid calendar dates in YYYYMMDD format.',
      );
    }
    return digits;
  }

  static String _timestampToTime(Object? value) {
    if (value is Timestamp) {
      return _formatTime(value.toDate());
    }
    return '0000';
  }

  static String _formatCompactDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}$month$day';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour$minute';
  }

  static String _randomDigits(int length) {
    final random = Random();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }

  static String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String _normalizeIsraeliPhone(String raw) {
    final digits = _digitsOnly(raw);
    if (digits.isEmpty) {
      return '';
    }
    if (digits.startsWith('972') && digits.length >= 11) {
      final localNumber = digits.substring(3);
      if (localNumber.startsWith('0')) {
        return localNumber.substring(0, min(localNumber.length, 10));
      }
      return '0${localNumber.substring(0, min(localNumber.length, 9))}';
    }
    if (digits.startsWith('0')) {
      return digits.substring(0, min(digits.length, 10));
    }
    if (digits.length == 9 && digits.startsWith('5')) {
      return '0$digits';
    }
    return digits.substring(0, min(digits.length, 10));
  }

  static double _absNum(Object? value) => _num(value).abs();

  static String _extractTransferPart(String raw, int index) {
    final groups = RegExp(r'\d+')
        .allMatches(raw)
        .map((match) => match.group(0) ?? '')
        .where((group) => group.isNotEmpty)
        .toList();
    if (index < 0 || index >= groups.length) {
      return '';
    }
    return groups[index];
  }

  static String _extractTransferDate(String raw) {
    final digits = _digitsOnly(raw);
    if (digits.length == 8) {
      return _normalizeDate(digits);
    }
    return '';
  }

  static double _num(Object? value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse((value ?? '').toString()) ?? fallback;
  }
}

class _PaymentDetails {
  final int typeCode;
  final String bankNumber;
  final String branchNumber;
  final String accountNumber;
  final String chequeNumber;
  final String paymentDate;
  final int? creditCompanyCode;
  final String cardName;
  final int? creditDealType;

  const _PaymentDetails({
    required this.typeCode,
    this.bankNumber = '',
    this.branchNumber = '',
    this.accountNumber = '',
    this.chequeNumber = '',
    this.paymentDate = '',
    this.creditCompanyCode,
    this.cardName = '',
    this.creditDealType,
  });
}

class _AddressParts {
  final String street;
  final String houseNumber;
  final String city;
  final String postalCode;

  const _AddressParts({
    required this.street,
    required this.houseNumber,
    required this.city,
    required this.postalCode,
  });
}
