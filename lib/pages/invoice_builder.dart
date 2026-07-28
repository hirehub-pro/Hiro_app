import 'dart:developer' as dev;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/utils/israeli_id_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:untitled1/services/subscription_access_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:untitled1/services/bkmv_export_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/services/invoice_builder_lock_service.dart';

class _SavedInvoiceResult {
  final String url;
  final String fileName;
  final bool wasCreated;

  const _SavedInvoiceResult({
    required this.url,
    required this.fileName,
    required this.wasCreated,
  });
}

class InvoiceBuilderDraftResult {
  final String url;
  final String fileName;
  final String invoiceDocId;
  final String storagePath;
  final double amount;
  final String docType;
  final String? documentNumber;
  final List<Map<String, dynamic>> items;

  const InvoiceBuilderDraftResult({
    required this.url,
    required this.fileName,
    required this.invoiceDocId,
    required this.storagePath,
    required this.amount,
    required this.docType,
    this.documentNumber,
    required this.items,
  });
}

class _TaxAuthorityAllocationResult {
  final bool approved;
  final String? confirmationNumber;
  final String? invoiceId;
  final String? transactionId;
  final Map<String, dynamic> raw;

  const _TaxAuthorityAllocationResult({
    required this.approved,
    required this.raw,
    this.confirmationNumber,
    this.invoiceId,
    this.transactionId,
  });

  Map<String, dynamic> toMap() => {
    'approved': approved,
    if (confirmationNumber != null && confirmationNumber!.isNotEmpty)
      'confirmationNumber': confirmationNumber,
    if (invoiceId != null && invoiceId!.isNotEmpty) 'invoiceId': invoiceId,
    if (transactionId != null && transactionId!.isNotEmpty)
      'transactionId': transactionId,
    'raw': raw,
    'requestedAt': FieldValue.serverTimestamp(),
  };
}

class InvoiceItem {
  final String description;
  final int quantity;
  final double price;
  final bool isPriceBeforeTax;
  InvoiceItem({
    required this.description,
    this.quantity = 1,
    required this.price,
    this.isPriceBeforeTax = false,
  });
}

class _PaymentMethodEntry {
  _PaymentMethodEntry();

  String method = 'cash';
  String creditDealType = 'regular';
  bool isExpanded = true;
  final amountController = TextEditingController();

  final cardNumberController = TextEditingController();
  final cardNameController = TextEditingController();
  final installmentsController = TextEditingController();
  final checkNumberController = TextEditingController();
  final checkBankController = TextEditingController();
  final checkBranchController = TextEditingController();
  final checkAccountController = TextEditingController();
  final transferBankController = TextEditingController();
  final transferBranchController = TextEditingController();
  final transferAccountController = TextEditingController();

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{'method': method};
    final amount = double.tryParse(
      amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount != null) {
      data['amount'] = amount;
    }
    switch (method) {
      case 'credit':
        data['dealType'] = creditDealType;
        if (cardNumberController.text.trim().isNotEmpty) {
          data['cardNumber'] = cardNumberController.text.trim();
        }
        if (cardNameController.text.trim().isNotEmpty) {
          data['cardName'] = cardNameController.text.trim();
        }
        if (creditDealType == 'installments' &&
            installmentsController.text.trim().isNotEmpty) {
          data['installments'] = installmentsController.text.trim();
        }
        break;
      case 'check':
        data['checkNumber'] = checkNumberController.text.trim();
        if (checkBankController.text.trim().isNotEmpty) {
          data['bank'] = checkBankController.text.trim();
        }
        if (checkBranchController.text.trim().isNotEmpty) {
          data['branch'] = checkBranchController.text.trim();
        }
        if (checkAccountController.text.trim().isNotEmpty) {
          data['account'] = checkAccountController.text.trim();
        }
        break;
      case 'transfer':
        data['bank'] = transferBankController.text.trim();
        data['branch'] = transferBranchController.text.trim();
        data['account'] = transferAccountController.text.trim();
        break;
      case 'cash':
      default:
        break;
    }
    return data;
  }

  void dispose() {
    amountController.dispose();
    cardNumberController.dispose();
    cardNameController.dispose();
    installmentsController.dispose();
    checkNumberController.dispose();
    checkBankController.dispose();
    checkBranchController.dispose();
    checkAccountController.dispose();
    transferBankController.dispose();
    transferBranchController.dispose();
    transferAccountController.dispose();
  }
}

class InvoiceBuilderPage extends StatefulWidget {
  final String workerName;
  final String? workerPhone;
  final String? workerEmail;
  final String? receiverId;
  final String? receiverName;
  final String? receiverPhone;
  final String? receiverEmail;
  final String? receiverAddress;
  final String? initialDocType;
  final List<Map<String, dynamic>>? initialItems;
  final String? initialNotes;
  final String? initialPaymentMethod;
  final String? initialCheckNumber;
  final String? initialTransferDetails;
  final String? initialCreditOriginalInvoiceNumber;
  final String? initialCreditOriginalInvoiceDate;
  final String? initialCreditReason;
  final String? initialCreditDeliveryMethod;
  final String? initialCreditReceiptConfirmation;
  final double? initialPaymentAmount;
  final String? sourceInvoiceNumber;
  final String? sourceInvoiceDocId;
  final double? sourceInvoiceTotalAmount;
  final bool returnDraftOnSend;

  const InvoiceBuilderPage({
    super.key,
    required this.workerName,
    this.workerPhone,
    this.workerEmail,
    this.receiverId,
    this.receiverName,
    this.receiverPhone,
    this.receiverEmail,
    this.receiverAddress,
    this.initialDocType,
    this.initialItems,
    this.initialNotes,
    this.initialPaymentMethod,
    this.initialCheckNumber,
    this.initialTransferDetails,
    this.initialCreditOriginalInvoiceNumber,
    this.initialCreditOriginalInvoiceDate,
    this.initialCreditReason,
    this.initialCreditDeliveryMethod,
    this.initialCreditReceiptConfirmation,
    this.initialPaymentAmount,
    this.sourceInvoiceNumber,
    this.sourceInvoiceDocId,
    this.sourceInvoiceTotalAmount,
    this.returnDraftOnSend = false,
  });

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
  static const int _sandboxAccountingSoftwareNumber = 987654321;

  final InvoiceBuilderLockService _invoiceBuilderLock =
      InvoiceBuilderLockService();
  bool _isAcquiringLock = true;
  bool _hasInvoiceBuilderLock = false;
  bool _lockLostDialogShown = false;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );

  bool get _isLicensedDealerType =>
      _dealerType == 'licensed' || _dealerType == 'company';

  String _normalizePaymentMethod(String? raw) {
    switch (raw) {
      case 'cash':
      case 'credit':
      case 'transfer':
      case 'check':
        return raw!;
      default:
        return 'cash';
    }
  }

  List<Map<String, String>> _logTargetsForDocType(String docType) {
    switch (docType) {
      case 'quote':
      case 'work_order':
        return const [];
      case 'receipt':
        return [
          {'bucket': 'receipts'},
        ];
      case 'credit_note':
        return [
          {'bucket': 'credit_notes'},
        ];
      case 'invoice_receipt':
        return [
          {'bucket': 'invoices'},
          {'bucket': 'receipts'},
        ];
      case 'invoice':
      default:
        return [
          {'bucket': 'invoices'},
        ];
    }
  }

  String _counterDocIdForType(String docType) => 'document_counter_$docType';

  DocumentReference<Map<String, dynamic>>? _counterRefForDocType(
    String docType,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('counters')
        .doc(_counterDocIdForType(docType));
  }

  String _formatDocumentNumber(int counter) {
    final year = intl.DateFormat('yyyy').format(DateTime.now());
    return '$year-${counter.toString().padLeft(4, '0')}';
  }

  String _invoiceNumberForPdf(String documentNumber) {
    final sequence = documentNumber.split('-').last;
    return int.tryParse(sequence)?.toString() ?? sequence;
  }

  String _invoiceDocIdFor(String docType, String documentNumber) {
    return '${docType}_$documentNumber';
  }

  /// Generate BKMVDATA.TXT from logs/ collection
  Future<void> generateBkmvDataTxt({
    required String userId,
    required String fromDate, // format: YYYYMMDD
    required String toDate, // format: YYYYMMDD
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportRoot = Directory('${dir.path}/BKMVDATA');
    await exportRoot.create(recursive: true);
    final result = await BkmvExportService.exportForUser(
      firestore: FirebaseFirestore.instance,
      userId: userId,
      fromDate: fromDate,
      toDate: toDate,
      rootDirectory: exportRoot,
    );
    if (mounted) {
      final message = result.hasFiles
          ? 'BKMVDATA files generated in ${result.packages.first.directory.path}'
          : (result.warnings.isNotEmpty
                ? result.warnings.join('\n')
                : 'No BKMVDATA files were generated.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Atomic Firestore transaction for invoice creation and logging
  Future<InvoiceBuilderDraftResult?> _createInvoiceAndLog({
    required Uint8List pdfBytes,
    Map<String, dynamic>? taxAuthorityAllocation,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final userId = user.uid;
    final dateStr = _invoiceDateStorageValue();
    final timestamp = FieldValue.serverTimestamp();
    final customerId = _clientIdController.text.trim().isNotEmpty
        ? _clientIdController.text.trim()
        : _clientNameController.text.isNotEmpty
        ? _clientNameController.text
        : null;
    final docType = _selectedDocType;
    final creditNoteLegalData = _creditNoteLegalData;
    final signedTotalAmount = _totalAmount;
    final totalEarnedDelta = docType == 'credit_note'
        ? -_totalAmount
        : _totalAmount;
    final calculatedVat = _vatAmount;
    final vatAmount = calculatedVat;
    final logTargets = _logTargetsForDocType(docType);
    final assignedSequenceNumber = _currentDocumentCounter;
    final assignedDocumentNumber = _invoiceNumber.trim();

    final userDoc = FirebaseFirestore.instance.collection('users').doc(userId);
    final counterRef = userDoc
        .collection('counters')
        .doc(_counterDocIdForType(docType));
    final invoicesRef = userDoc.collection('invoices');
    final invoiceTotalsRef = FirebaseFirestore.instance
        .collection('metadata')
        .doc('invoice_counts');
    final userLogsRef = userDoc.collection('logs');
    final logEntries = logTargets.map((target) {
      final logBucketRef = userLogsRef.doc(target['bucket']!);
      return {
        'bucket': target['bucket']!,
        'bucketRef': logBucketRef,
        'fileRef': logBucketRef.collection('files').doc(),
      };
    }).toList();
    final paymentMethodsData = _paymentMethods
        .map((entry) => entry.toMap())
        .toList();
    final paymentAmountTotal = _paymentMethodsAmountTotal();
    final hasDiscount = _hasDiscount && _manualDiscountAmount > 0;
    final discountAmount = hasDiscount ? _manualDiscountAmount : 0.0;
    final signedDiscountAmount = discountAmount == 0
        ? 0.0
        : (docType == 'credit_note' ? discountAmount : -discountAmount);
    final roundingAmount = _roundingAmount;
    final itemsNetTotal = _items.fold<double>(
      0,
      (runningTotal, item) => runningTotal + _itemTotalBeforeTax(item),
    );
    final subtotalBeforeTax = _subtotalAmount;
    final subtotalAfterTax = _totalBeforeRoundingAmount;
    final signedSubtotalBeforeTax = subtotalBeforeTax;
    final signedSubtotalAfterTax = subtotalAfterTax;
    final signedRoundingAmount = roundingAmount == 0
        ? 0.0
        : (docType == 'credit_note' ? roundingAmount : -roundingAmount);
    var remainingDiscount = discountAmount;
    final logItems = _items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isLastItem = index == _items.length - 1;
      final lineSubtotalBeforeTax = _itemTotalBeforeTax(item);
      final proportionalDiscount = hasDiscount && itemsNetTotal > 0
          ? discountAmount * (lineSubtotalBeforeTax / itemsNetTotal)
          : 0.0;
      final lineDiscount = hasDiscount
          ? (isLastItem ? remainingDiscount : proportionalDiscount)
          : 0.0;
      if (hasDiscount) {
        remainingDiscount -= lineDiscount;
      }
      final lineTotalBeforeTax = lineSubtotalBeforeTax - lineDiscount;
      final lineTaxPaid = _usesVat ? lineTotalBeforeTax * _vatRate : 0.0;
      final lineTotalAfterTax = lineTotalBeforeTax + lineTaxPaid;

      return {
        'description': item.description,
        'quantity': item.quantity,
        'unitPrice': _unitPriceAfterTax(item),
        'unitPriceWithoutTax': _unitPriceBeforeTax(item),
        'discount': lineDiscount == 0 ? 0.0 : -lineDiscount,
        'taxPaid': lineTaxPaid,
        'total': lineTotalAfterTax,
        'priceTaxMode': item.isPriceBeforeTax ? 'before_tax' : 'after_tax',
      };
    }).toList();
    final clientDetails = {
      'id': customerId,
      'name': _clientNameController.text,
      'address': _clientAddressController.text,
      'phone': _clientPhoneController.text,
      'email': _clientEmailController.text.trim(),
      'taxId': _clientIdController.text.trim(),
    };
    final businessDetails = {
      'businessId': _businessId,
      'businessAddress': _businessAddress,
      'dealerType': _dealerType,
      'isBusinessVerified': _isBusinessVerified,
    };
    final allocationNumber = taxAuthorityAllocation?['confirmationNumber']
        ?.toString()
        .trim();

    if (docType == 'quote' || docType == 'work_order') {
      final fileName =
          '${docType}_${userId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final storagePath = 'invoices/$userId/$fileName';
      final ref = firebase_storage.FirebaseStorage.instance.ref().child(
        storagePath,
      );
      await ref.putData(pdfBytes);
      final downloadUrl = await ref.getDownloadURL();
      final quoteDocRef = invoicesRef.doc();
      final clientName = _clientNameController.text.trim();
      final savedQuoteName = clientName.isNotEmpty
          ? '${_labelForDocType(docType)} - $clientName'
          : _labelForDocType(docType);
      final quoteData = {
        'type': docType,
        'docType': docType,
        'name': savedQuoteName,
        'fileName': fileName,
        'url': downloadUrl,
        'storagePath': storagePath,
        'amount': signedTotalAmount,
        'vatAmount': vatAmount,
        'clientName': _clientNameController.text,
        'clientAddress': _clientAddressController.text,
        'clientPhone': _clientPhoneController.text,
        'clientEmail': _clientEmailController.text.trim(),
        'clientTaxId': _clientIdController.text.trim(),
        'items': _items
            .map(
              (item) => {
                'description': item.description,
                'quantity': item.quantity,
                'price': item.price,
                'priceTaxMode': item.isPriceBeforeTax
                    ? 'before_tax'
                    : 'after_tax',
              },
            )
            .toList(),
        'priceTaxModeDefault': _selectedPriceTaxMode,
        'hasDiscount': _hasDiscount,
        'discountAmount': _manualDiscountAmount,
        'roundTotalEnabled': _roundTotalEnabled,
        'roundingAmount': _roundingAmount,
        'notes': _notesController.text,
        'paymentMethod': _paymentMethods.isNotEmpty
            ? _paymentMethods.first.method
            : 'cash',
        'paymentMethods': paymentMethodsData,
        'paymentAmountTotal': paymentAmountTotal,
        'date': dateStr,
        if (_showsDueDateSection && _selectedPaymentDueDate != null)
          'paymentDueDate': _paymentDueDateStorageValue(),
        'invoiceDocId': quoteDocRef.id,
        'createdAt': timestamp,
      };
      if (taxAuthorityAllocation != null) {
        quoteData['taxAuthorityAllocation'] = taxAuthorityAllocation;
      }
      if (allocationNumber != null && allocationNumber.isNotEmpty) {
        quoteData['allocationNumber'] = allocationNumber;
        quoteData['taxAuthorityAllocationNumber'] = allocationNumber;
      }
      await quoteDocRef.set(quoteData);
      return InvoiceBuilderDraftResult(
        url: downloadUrl,
        fileName: fileName,
        invoiceDocId: quoteDocRef.id,
        storagePath: storagePath,
        amount: signedTotalAmount,
        docType: docType,
        items: _items
            .map(
              (item) => {
                'description': item.description,
                'quantity': item.quantity,
                'price': item.price,
                'priceTaxMode': item.isPriceBeforeTax
                    ? 'before_tax'
                    : 'after_tax',
              },
            )
            .toList(),
      );
    }

    late int nextNumber;
    late String nextDocumentNumber;
    late String invoiceDocId;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final logCounterSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final entry in logEntries) {
        final logBucketRef =
            entry['bucketRef']! as DocumentReference<Map<String, dynamic>>;
        logCounterSnaps.add(await transaction.get(logBucketRef));
      }

      final storedNextNumber = counterSnap.exists
          ? ((counterSnap.data() as Map<String, dynamic>)['value'] as num?)
                ?.toInt()
          : null;

      if (assignedSequenceNumber != null &&
          assignedSequenceNumber > 0 &&
          assignedDocumentNumber.isNotEmpty) {
        if (storedNextNumber != null &&
            storedNextNumber > 0 &&
            storedNextNumber != assignedSequenceNumber) {
          throw StateError(
            'Document number changed before save. Please preview and save again.',
          );
        }
        nextNumber = assignedSequenceNumber;
        nextDocumentNumber = assignedDocumentNumber;
      } else {
        nextNumber = storedNextNumber ?? 1;
        if (nextNumber < 1) nextNumber = 1;
        nextDocumentNumber = _formatDocumentNumber(nextNumber);
      }

      invoiceDocId = _invoiceDocIdFor(docType, nextDocumentNumber);

      transaction.set(counterRef, {
        'value': nextNumber + 1,
        'docType': docType,
        'updatedAt': timestamp,
      }, SetOptions(merge: true));

      final invoiceData = {
        'type': docType,
        'docType': docType,
        'amount': signedTotalAmount,
        'vatAmount': vatAmount,
        'clientName': _clientNameController.text,
        'clientAddress': _clientAddressController.text,
        'clientPhone': _clientPhoneController.text,
        'clientEmail': _clientEmailController.text.trim(),
        'clientTaxId': _clientIdController.text.trim(),
        'items': _items
            .map(
              (item) => {
                'description': item.description,
                'quantity': item.quantity,
                'price': item.price,
                'priceTaxMode': item.isPriceBeforeTax
                    ? 'before_tax'
                    : 'after_tax',
              },
            )
            .toList(),
        'priceTaxModeDefault': _selectedPriceTaxMode,
        'hasDiscount': _hasDiscount,
        'discountAmount': _manualDiscountAmount,
        'roundTotalEnabled': _roundTotalEnabled,
        'roundingAmount': _roundingAmount,
        'notes': _notesController.text,
        'paymentMethod': _paymentMethods.isNotEmpty
            ? _paymentMethods.first.method
            : 'cash',
        'paymentMethods': paymentMethodsData,
        'paymentAmountTotal': paymentAmountTotal,
        'sourceInvoiceNumber': widget.sourceInvoiceNumber,
        'sourceInvoiceDocId': widget.sourceInvoiceDocId,
        'sourceInvoiceTotalAmount': widget.sourceInvoiceTotalAmount,
        'invoiceNumber': nextDocumentNumber,
        'sequenceNumber': nextNumber,
        'invoiceDocId': invoiceDocId,
        'date': dateStr,
        if (_showsDueDateSection && _selectedPaymentDueDate != null)
          'paymentDueDate': _paymentDueDateStorageValue(),
        'createdAt': timestamp,
        if (docType == 'invoice') 'paymentStatus': 'unpaid',
        if (docType == 'invoice') 'paidAmount': 0.0,
        if (docType == 'invoice_receipt') 'paymentStatus': 'paid',
        if (docType == 'invoice_receipt') 'paidAmount': signedTotalAmount.abs(),
        ...?creditNoteLegalData == null
            ? null
            : {'creditNoteLegal': creditNoteLegalData},
      };
      if (taxAuthorityAllocation != null) {
        invoiceData['taxAuthorityAllocation'] = taxAuthorityAllocation;
      }
      if (allocationNumber != null && allocationNumber.isNotEmpty) {
        invoiceData['allocationNumber'] = allocationNumber;
        invoiceData['taxAuthorityAllocationNumber'] = allocationNumber;
      }

      final invoiceDoc = invoicesRef.doc(invoiceDocId);
      transaction.set(invoiceDoc, invoiceData);
      transaction.set(invoiceTotalsRef, {
        docType: FieldValue.increment(1),
        'updatedAt': timestamp,
      }, SetOptions(merge: true));

      // Keep a per-type counter and write each file entry under logs/<type>/files.
      for (var i = 0; i < logEntries.length; i++) {
        final entry = logEntries[i];
        final logBucketRef =
            entry['bucketRef']! as DocumentReference<Map<String, dynamic>>;
        final logFileRef =
            entry['fileRef']! as DocumentReference<Map<String, dynamic>>;
        final logCounterSnap = logCounterSnaps[i];
        int logCounter = 1;
        if (logCounterSnap.exists) {
          final logCounterData = logCounterSnap.data() as Map<String, dynamic>;
          logCounter = (logCounterData['value'] as int? ?? 0) + 1;
        }
        transaction.set(logBucketRef, {
          'value': logCounter,
          'updatedAt': timestamp,
          'docType': entry['bucket'],
        }, SetOptions(merge: true));

        final logData = {
          'userId': userId,
          'bucket': entry['bucket'],
          'docType': docType,
          'counter': logCounter,
          'documentNumber': nextNumber,
          'sequenceNumber': nextNumber,
          'invoiceDocId': invoiceDocId,
          'date': dateStr,
          'issueDate': dateStr,
          if (_showsDueDateSection && _selectedPaymentDueDate != null)
            'paymentDueDate': _paymentDueDateStorageValue(),
          'clientDetails': clientDetails,
          'businessDetails': businessDetails,
          'amount': signedTotalAmount,
          'subtotalBeforeTax': signedSubtotalBeforeTax,
          'subtotalAfterTax': signedSubtotalAfterTax,
          'vatAmount': vatAmount,
          'grandTotal': signedTotalAmount,
          'discountAmount': signedDiscountAmount,
          'roundingAmount': signedRoundingAmount,
          'customerId': customerId,
          'clientName': _clientNameController.text,
          'clientAddress': _clientAddressController.text,
          'clientPhone': _clientPhoneController.text,
          'clientEmail': _clientEmailController.text.trim(),
          'clientTaxId': _clientIdController.text.trim(),
          'paymentMethod': _paymentMethods.isNotEmpty
              ? _paymentMethods.first.method
              : 'cash',
          'paymentMethods': paymentMethodsData,
          'paymentAmountTotal': paymentAmountTotal,
          'sourceInvoiceNumber': widget.sourceInvoiceNumber,
          'sourceInvoiceDocId': widget.sourceInvoiceDocId,
          'sourceInvoiceTotalAmount': widget.sourceInvoiceTotalAmount,
          'items': logItems,
          'fileName': '',
          'storagePath': '',
          'url': '',
          'timestamp': timestamp,
          if (docType == 'invoice') 'paymentStatus': 'unpaid',
          if (docType == 'invoice') 'paidAmount': 0.0,
          if (docType == 'invoice_receipt') 'paymentStatus': 'paid',
          if (docType == 'invoice_receipt')
            'paidAmount': signedTotalAmount.abs(),
          ...?creditNoteLegalData == null
              ? null
              : {'creditNoteLegal': creditNoteLegalData},
        };
        if (taxAuthorityAllocation != null) {
          logData['taxAuthorityAllocation'] = taxAuthorityAllocation;
        }
        if (allocationNumber != null && allocationNumber.isNotEmpty) {
          logData['allocationNumber'] = allocationNumber;
          logData['taxAuthorityAllocationNumber'] = allocationNumber;
        }
        transaction.set(logFileRef, logData);
      }
    });

    // Upload PDF to Storage (after transaction). Regenerate from the saved
    // allocation number so Storage cannot receive stale pre-allocation bytes.
    var uploadPdfBytes = pdfBytes;
    if (allocationNumber != null && allocationNumber.isNotEmpty) {
      final allocatedPdfBytes = await _getGeneratedPdfBytes(
        allocationNumber: allocationNumber,
      );
      if (allocatedPdfBytes == null) {
        throw StateError(
          'Could not generate the invoice PDF with the Tax Authority allocation number.',
        );
      }
      uploadPdfBytes = allocatedPdfBytes;
    }

    // Upload PDF to Storage (after transaction)
    final fileName =
        'invoice_${userId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final storagePath = 'invoices/$userId/$fileName';
    final ref = firebase_storage.FirebaseStorage.instance.ref().child(
      storagePath,
    );
    await ref.putData(uploadPdfBytes);
    final downloadUrl = await ref.getDownloadURL();
    final clientName = _clientNameController.text.trim();
    final savedInvoiceName = clientName.isNotEmpty
        ? '${_labelForDocType(docType)} #$nextDocumentNumber - $clientName'
        : '${_labelForDocType(docType)} #$nextDocumentNumber';

    await invoicesRef.doc(invoiceDocId).update({
      'name': savedInvoiceName,
      'fileName': fileName,
      'url': downloadUrl,
      'storagePath': storagePath,
      if (allocationNumber != null && allocationNumber.isNotEmpty)
        'allocationNumber': allocationNumber,
      if (allocationNumber != null && allocationNumber.isNotEmpty)
        'taxAuthorityAllocationNumber': allocationNumber,
    });
    if (docType != 'quote' && docType != 'work_order') {
      await _addToTotalEarned(userId: userId, amount: totalEarnedDelta);
    }
    await Future.wait(
      logEntries.map((entry) async {
        final logFileRef =
            entry['fileRef']! as DocumentReference<Map<String, dynamic>>;
        await logFileRef.update({
          'fileName': fileName,
          'storagePath': storagePath,
          'url': downloadUrl,
          if (allocationNumber != null && allocationNumber.isNotEmpty)
            'allocationNumber': allocationNumber,
          if (allocationNumber != null && allocationNumber.isNotEmpty)
            'taxAuthorityAllocationNumber': allocationNumber,
        });
      }),
    );

    if (docType == 'receipt' &&
        widget.sourceInvoiceNumber != null &&
        widget.sourceInvoiceDocId != null &&
        widget.sourceInvoiceTotalAmount != null) {
      await _updateLinkedInvoicePaymentStatus(
        userId: userId,
        paidAmount: paymentAmountTotal,
      );
    }

    return InvoiceBuilderDraftResult(
      url: downloadUrl,
      fileName: fileName,
      invoiceDocId: invoiceDocId,
      storagePath: storagePath,
      amount: signedTotalAmount,
      docType: docType,
      documentNumber: nextDocumentNumber,
      items: _items
          .map(
            (item) => {
              'description': item.description,
              'quantity': item.quantity,
              'price': item.price,
              'priceTaxMode': item.isPriceBeforeTax
                  ? 'before_tax'
                  : 'after_tax',
            },
          )
          .toList(),
    );
  }

  Future<void> _updateLinkedInvoicePaymentStatus({
    required String userId,
    required double paidAmount,
  }) async {
    final sourceInvoiceNumber = widget.sourceInvoiceNumber?.trim();
    final sourceInvoiceDocId = widget.sourceInvoiceDocId?.trim();
    final sourceInvoiceTotalAmount = widget.sourceInvoiceTotalAmount;
    if (sourceInvoiceNumber == null ||
        sourceInvoiceNumber.isEmpty ||
        sourceInvoiceDocId == null ||
        sourceInvoiceDocId.isEmpty ||
        sourceInvoiceTotalAmount == null ||
        sourceInvoiceTotalAmount <= 0 ||
        paidAmount <= 0) {
      return;
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final invoiceRef = userRef.collection('invoices').doc(sourceInvoiceDocId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final invoiceSnap = await transaction.get(invoiceRef);
      final currentPaidAmount =
          (invoiceSnap.data()?['paidAmount'] as num?)?.toDouble() ?? 0.0;
      final nextPaidAmount = (currentPaidAmount + paidAmount).clamp(
        0.0,
        sourceInvoiceTotalAmount,
      );
      final nextStatus = nextPaidAmount <= 0
          ? 'unpaid'
          : (nextPaidAmount + 0.01 >= sourceInvoiceTotalAmount
                ? 'paid'
                : 'partial');

      final paymentUpdate = {
        'paidAmount': nextPaidAmount,
        'paymentStatus': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (invoiceSnap.exists) {
        transaction.set(invoiceRef, paymentUpdate, SetOptions(merge: true));
      }
    });
  }

  String _labelForDocType(String docType) {
    switch (docType) {
      case 'quote':
        return 'Quote';
      case 'work_order':
        return 'Work Order';
      case 'invoice':
        return 'Invoice';
      case 'invoice_receipt':
        return 'Invoice Receipt';
      case 'credit_note':
        return 'Credit Note';
      case 'receipt':
      default:
        return 'Receipt';
    }
  }

  final _clientNameController = TextEditingController();
  final _clientAddressController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _clientEmailController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _invoiceDateController = TextEditingController();
  final _paymentDueDateController = TextEditingController();
  final _itemDescController = TextEditingController();
  final _itemQtyController = TextEditingController(text: "1");
  final _itemPriceController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();
  final _creditReasonController = TextEditingController();
  final _creditOriginalInvoiceNumberController = TextEditingController();
  final _creditOriginalInvoiceDateController = TextEditingController();
  final _creditReceiptConfirmationController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  // Payment method state
  final List<_PaymentMethodEntry> _paymentMethods = [_PaymentMethodEntry()];
  String _selectedCreditDeliveryMethod = 'email_confirmation';

  final List<InvoiceItem> _items = [];
  bool _isPreparing = false;
  String _invoiceNumber = "";
  int? _currentDocumentCounter;
  bool _isLoadingCounterAssignment = false;
  double _vatRate = 0.17;
  double _allocationNumberMinAmountBeforeVat = double.infinity;
  DateTime _selectedInvoiceDate = DateTime.now();
  DateTime? _selectedPaymentDueDate;
  bool _hasCustomPaymentDueDate = false;
  String _selectedPriceTaxMode = 'after_tax';
  bool _hasDiscount = false;
  bool _roundTotalEnabled = true;

  bool get _isCreditNote => _selectedDocType == 'credit_note';
  bool get _isQuoteLike =>
      _selectedDocType == 'quote' || _selectedDocType == 'work_order';
  bool get _showsDueDateSection =>
      _selectedDocType == 'quote' || _selectedDocType == 'invoice';
  bool get _requiresSequentialDocumentNumber => !_isQuoteLike;
  bool get _showsPaymentMethodSection =>
      !_isQuoteLike && _selectedDocType != 'invoice';
  bool get _usesVat => _isLicensedDealerType && _selectedDocType != 'receipt';
  bool get _isTaxInvoiceDocType =>
      _selectedDocType == 'invoice' || _selectedDocType == 'invoice_receipt';
  bool get _requiresTaxAuthorityAllocation =>
      _isTaxInvoiceDocType &&
      _usesVat &&
      _digitsOnly(_clientIdController.text).isNotEmpty &&
      _subtotalAmount > _allocationNumberMinAmountBeforeVat;

  double _unitPriceAfterTax(InvoiceItem item) {
    if (!_usesVat) return item.price;
    return item.isPriceBeforeTax ? item.price * (1 + _vatRate) : item.price;
  }

  double _unitPriceBeforeTax(InvoiceItem item) {
    if (!_usesVat) return item.price;
    return item.isPriceBeforeTax ? item.price : item.price / (1 + _vatRate);
  }

  double _itemTotalAfterTax(InvoiceItem item) =>
      _unitPriceAfterTax(item) * item.quantity;

  double _itemTotalBeforeTax(InvoiceItem item) =>
      _unitPriceBeforeTax(item) * item.quantity;

  double get _itemsSubtotalBeforeTax =>
      _items.fold<double>(0, (runningTotal, item) {
        return runningTotal + _itemTotalBeforeTax(item);
      });

  double get _itemsTotalBeforeDiscount =>
      _items.fold<double>(0, (runningTotal, item) {
        return runningTotal + _itemTotalAfterTax(item);
      });

  double get _manualDiscountAmount {
    if (!_hasDiscount) return 0.0;
    final parsed = double.tryParse(
      _discountController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return 0.0;
    final maxDiscount = _itemsSubtotalBeforeTax;
    return parsed > maxDiscount ? maxDiscount : parsed;
  }

  double get _discountAmount => _manualDiscountAmount;

  double get _subtotalAmount {
    final subtotal = _itemsSubtotalBeforeTax - _discountAmount;
    return subtotal < 0 ? 0 : subtotal;
  }

  double get _vatAmount => _usesVat ? _subtotalAmount * _vatRate : 0.0;

  double get _totalBeforeRoundingAmount => _subtotalAmount + _vatAmount;

  double get _roundingAmount {
    if (!_roundTotalEnabled) return 0.0;
    final roundedTotal = _totalBeforeRoundingAmount.floorToDouble();
    final reductionNeeded = _totalBeforeRoundingAmount - roundedTotal;
    return reductionNeeded <= 0 ? 0.0 : reductionNeeded;
  }

  double get _totalAmount => _totalBeforeRoundingAmount - _roundingAmount;

  double get _signedTotalAmount => _totalAmount;

  double get _signedRoundingAmount {
    return _roundingAmount == 0
        ? 0.0
        : (_isCreditNote ? _roundingAmount : -_roundingAmount);
  }

  double get _signedSubtotalAmount {
    return _subtotalAmount;
  }

  double get _signedVatAmount {
    return _vatAmount;
  }

  double _signedItemTotal(InvoiceItem item) => _itemTotalAfterTax(item);

  double _parseVatPercent(dynamic value) {
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (parsed == null || parsed <= 0 || parsed > 100) {
      return 17.0;
    }
    return parsed;
  }

  double? _parsePositiveAmount(dynamic value) {
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _digitsOnly(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\D'), '');

  String _invoiceDateIsoValue() {
    return intl.DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate);
  }

  String _formattedVatPercent() {
    final percent = _vatRate * 100;
    final rounded = percent.toStringAsFixed(2);
    return rounded.contains('.')
        ? rounded.replaceFirst(RegExp(r'\.?0+$'), '')
        : rounded;
  }

  String _vatLabel(bool isRtl) {
    final percent = _formattedVatPercent();
    return isRtl ? 'מע"מ ($percent%):' : 'VAT ($percent%):';
  }

  String _previewFileName() {
    if (_invoiceNumber.isNotEmpty) {
      return '$_invoiceNumber.pdf';
    }
    final datePart = intl.DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate);
    return '${_labelForDocType(_selectedDocType).toLowerCase().replaceAll(' ', '_')}_$datePart.pdf';
  }

  String _formattedInvoiceDate() {
    return intl.DateFormat('dd/MM/yyyy').format(_selectedInvoiceDate);
  }

  String _invoiceDateStorageValue() {
    return intl.DateFormat('yyyyMMdd').format(_selectedInvoiceDate);
  }

  String _paymentDueDateStorageValue() {
    final dueDate = _selectedPaymentDueDate;
    if (dueDate == null) return '';
    return intl.DateFormat('yyyyMMdd').format(dueDate);
  }

  String _formattedPaymentDueDate() {
    final dueDate = _selectedPaymentDueDate;
    if (dueDate == null) return '';
    return intl.DateFormat('dd/MM/yyyy').format(dueDate);
  }

  DateTime _defaultPaymentDueDate() {
    return _selectedInvoiceDate.add(const Duration(days: 30));
  }

  String _creditDeliveryMethodLabel(
    Map<String, String> strings,
    String method,
  ) {
    switch (method) {
      case 'registered_mail':
        return strings['delivery_registered_mail']!;
      case 'customer_signature':
        return strings['delivery_customer_signature']!;
      case 'manual_delivery':
        return strings['delivery_manual']!;
      case 'email_confirmation':
      default:
        return strings['delivery_email_confirmation']!;
    }
  }

  Map<String, dynamic>? get _creditNoteLegalData {
    if (!_isCreditNote) return null;
    return {
      'originalInvoiceNumber': _creditOriginalInvoiceNumberController.text
          .trim(),
      'originalInvoiceDate': _creditOriginalInvoiceDateController.text.trim(),
      'creditReason': _creditReasonController.text.trim(),
      'deliveryMethod': _selectedCreditDeliveryMethod,
      'receiptConfirmation': _creditReceiptConfirmationController.text.trim(),
    };
  }

  // State for dealer logic
  String _dealerType = 'exempt';
  String? _businessName;
  String? _businessId;
  String? _businessAddress;
  String? _workerName;
  String? _verifiedBusinessLogoUrl;
  bool _isBusinessVerified = false;
  String _selectedDocType = 'quote';
  bool _isLoadingBusinessLogo = false;
  bool _invoiceLogoTouched = false;
  Uint8List? _businessLogoBytes;

  pw.Font? _cachedFont;
  pw.Font? _cachedFontBold;
  pw.MemoryImage? _cachedLogo;
  pw.MemoryImage? _cachedAppIcon;
  Map<String, String>? _cachedStrings;
  String? _lastLocale;
  late final Future<SubscriptionAccessState> _accessFuture;

  @override
  void initState() {
    super.initState();
    _acquireInvoiceBuilderLock();
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
    _invoiceNumber = "";

    // Auto-fill from widget parameters
    if (widget.receiverName != null) {
      _clientNameController.text = widget.receiverName!;
    }
    if (widget.receiverPhone != null) {
      _clientPhoneController.text = widget.receiverPhone!;
    }
    if (widget.receiverEmail != null) {
      _clientEmailController.text = widget.receiverEmail!;
    }
    if (widget.receiverAddress != null) {
      _clientAddressController.text = widget.receiverAddress!;
    }
    _invoiceDateController.text = _formattedInvoiceDate();
    _selectedPaymentDueDate = _defaultPaymentDueDate();
    _paymentDueDateController.text = _formattedPaymentDueDate();

    _applyInitialTemplate();
    _prefillClientBusinessIdFromReceiver();
    _fetchWorkerInfo();
    _loadVatRate();
    _loadAssets();
  }

  Future<void> _acquireInvoiceBuilderLock() async {
    _invoiceBuilderLock.onLeaseLost = _handleInvoiceBuilderLockLost;
    final acquired = await _invoiceBuilderLock.acquire();
    if (!mounted) return;
    if (acquired) {
      setState(() {
        _isAcquiringLock = false;
        _hasInvoiceBuilderLock = true;
      });
      return;
    }

    setState(() => _isAcquiringLock = false);
    _showInvoiceBuilderLockedMessage();
  }

  void _handleInvoiceBuilderLockLost() {
    if (!mounted || _lockLostDialogShown) return;
    setState(() => _hasInvoiceBuilderLock = false);
    _showInvoiceBuilderLockedMessage();
  }

  Future<void> _showInvoiceBuilderLockedMessage() async {
    if (!mounted || _lockLostDialogShown) return;
    _lockLostDialogShown = true;
    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFFFF7ED),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.devices_other_rounded,
            color: Color(0xFFEA580C),
            size: 28,
          ),
        ),
        title: Text(
          strings['invoice_builder_locked_title']!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: Text(
          strings['invoice_builder_locked']!,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45, color: Color(0xFF475569)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(strings['invoice_builder_locked_action']!),
            ),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _applyInitialTemplate() {
    if (widget.initialDocType != null && widget.initialDocType!.isNotEmpty) {
      _selectedDocType = widget.initialDocType!;
    }

    if (widget.initialNotes != null) {
      _notesController.text = widget.initialNotes!;
    }
    if (widget.initialPaymentMethod != null &&
        widget.initialPaymentMethod!.isNotEmpty) {
      _paymentMethods.first.method = _normalizePaymentMethod(
        widget.initialPaymentMethod,
      );
    }
    if (widget.initialPaymentAmount != null &&
        widget.initialPaymentAmount! > 0) {
      _paymentMethods.first.amountController.text = widget.initialPaymentAmount!
          .toStringAsFixed(2);
    }
    if (widget.initialCheckNumber != null) {
      _paymentMethods.first.checkNumberController.text =
          widget.initialCheckNumber!;
    }
    if (widget.initialTransferDetails != null) {
      _paymentMethods.first.transferBankController.text =
          widget.initialTransferDetails!;
    }
    if (widget.initialCreditOriginalInvoiceNumber != null) {
      _creditOriginalInvoiceNumberController.text =
          widget.initialCreditOriginalInvoiceNumber!;
    }
    if (widget.initialCreditOriginalInvoiceDate != null) {
      _creditOriginalInvoiceDateController.text =
          widget.initialCreditOriginalInvoiceDate!;
    }
    if (widget.initialCreditReason != null) {
      _creditReasonController.text = widget.initialCreditReason!;
    }
    if (widget.initialCreditDeliveryMethod != null &&
        widget.initialCreditDeliveryMethod!.isNotEmpty) {
      _selectedCreditDeliveryMethod = widget.initialCreditDeliveryMethod!;
    }
    if (widget.initialCreditReceiptConfirmation != null) {
      _creditReceiptConfirmationController.text =
          widget.initialCreditReceiptConfirmation!;
    }

    final rawItems = widget.initialItems;
    if (rawItems == null || rawItems.isEmpty) return;

    if (rawItems.length == 1) {
      final firstItem = rawItems.first;
      final description = (firstItem['description'] ?? '').toString().trim();
      final rawPrice = firstItem['price'];
      final price = (rawPrice as num?)?.toDouble();
      final quantity = (firstItem['quantity'] as num?)?.toInt() ?? 1;
      final priceTaxMode = (firstItem['priceTaxMode'] ?? 'after_tax')
          .toString();

      if (description.isNotEmpty && (price == null || price <= 0)) {
        _itemDescController.text = description;
        _itemQtyController.text = quantity < 1 ? '1' : quantity.toString();
        _selectedPriceTaxMode = priceTaxMode;
        return;
      }
    }

    _items
      ..clear()
      ..addAll(
        rawItems.map((item) {
          final description = (item['description'] ?? '').toString();
          final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final priceTaxMode = (item['priceTaxMode'] ?? 'after_tax').toString();
          return InvoiceItem(
            description: description,
            quantity: quantity < 1 ? 1 : quantity,
            price: price,
            isPriceBeforeTax: priceTaxMode == 'before_tax',
          );
        }),
      );
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedInvoiceDate = picked;
      _invoiceDateController.text = _formattedInvoiceDate();
      if (!_hasCustomPaymentDueDate) {
        _selectedPaymentDueDate = _defaultPaymentDueDate();
        _paymentDueDateController.text = _formattedPaymentDueDate();
      }
    });
  }

  Future<void> _pickPaymentDueDate() async {
    final initialDate =
        _selectedPaymentDueDate ??
        _selectedInvoiceDate.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPaymentDueDate = picked;
      _hasCustomPaymentDueDate = true;
      _paymentDueDateController.text = _formattedPaymentDueDate();
    });
  }

  Future<void> _prefillClientBusinessIdFromReceiver() async {
    final receiverId = widget.receiverId?.trim();
    if (receiverId == null || receiverId.isEmpty) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .get();
      final verificationDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .collection('verification_info')
          .doc('latest')
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final verificationData = verificationDoc.data() ?? <String, dynamic>{};
      final receiverName = (userData['name'] ?? widget.receiverName ?? '')
          .toString()
          .trim();
      final receiverPhone =
          (userData['phone'] ??
                  userData['phoneNumber'] ??
                  userData['mobileNumber'] ??
                  widget.receiverPhone ??
                  '')
              .toString()
              .trim();
      final receiverAddress =
          (verificationData['address'] ??
                  userData['address'] ??
                  userData['location'] ??
                  widget.receiverAddress ??
                  '')
              .toString()
              .trim();
      final businessId = verificationDoc
          .data()?['businessId']
          ?.toString()
          .trim();
      if (!mounted) return;

      final shouldUpdateName =
          _clientNameController.text.trim().isEmpty && receiverName.isNotEmpty;
      final shouldUpdatePhone =
          _clientPhoneController.text.trim().isEmpty &&
          receiverPhone.isNotEmpty;
      final shouldUpdateAddress =
          _clientAddressController.text.trim().isEmpty &&
          receiverAddress.isNotEmpty;
      final shouldUpdateBusinessId =
          _clientIdController.text.trim().isEmpty &&
          businessId != null &&
          businessId.isNotEmpty;

      if (shouldUpdateName ||
          shouldUpdatePhone ||
          shouldUpdateAddress ||
          shouldUpdateBusinessId) {
        setState(() {
          if (shouldUpdateName) {
            _clientNameController.text = receiverName;
          }
          if (shouldUpdatePhone) {
            _clientPhoneController.text = receiverPhone;
          }
          if (shouldUpdateAddress) {
            _clientAddressController.text = receiverAddress;
          }
          if (shouldUpdateBusinessId) {
            _clientIdController.text = businessId;
          }
        });
      }
    } catch (e) {
      dev.log('Error prefilling client business ID: $e');
    }
  }

  Future<void> _fetchWorkerInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Fetch from unified 'users' collection
        final workerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (workerDoc.exists && mounted) {
          final workerData = workerDoc.data();
          setState(() {
            _isBusinessVerified = workerData?['isapproved'] ?? false;
            _workerName = workerData?['name']?.toString().trim();
          });

          // Fetch from verification_info sub-collection for business details
          final vInfoDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('verification_info')
              .doc('latest')
              .get();
          if (vInfoDoc.exists && mounted) {
            final vData = vInfoDoc.data();
            final businessLogoUrl =
                (vData?['businessLogoUrl'] ??
                        workerData?['businessLogoUrl'] ??
                        '')
                    .toString()
                    .trim();
            setState(() {
              _businessName = vData?['businessName']?.toString().trim();
              _businessId = vData?['businessId'];
              _businessAddress = vData?['address'];
              _dealerType = vData?['dealerType'] ?? 'exempt';
              _verifiedBusinessLogoUrl = businessLogoUrl.isEmpty
                  ? null
                  : businessLogoUrl;

              if (widget.initialDocType == null ||
                  widget.initialDocType!.isEmpty) {
                if (_isBusinessVerified && _isLicensedDealerType) {
                  _selectedDocType = 'invoice_receipt';
                } else {
                  _selectedDocType = 'quote';
                }
              }
            });
            await _loadDefaultBusinessLogo();
          }
          await _loadCurrentDocumentNumber(promptIfMissing: true);
        }
      } catch (e) {
        dev.log("Error fetching worker info: $e");
      }
    }
  }

  Future<void> _loadVatRate() async {
    try {
      final systemDoc = await FirebaseFirestore.instance
          .collection('metadata')
          .doc('system')
          .get();
      final systemData = systemDoc.data();
      final vatPercent = _parseVatPercent(systemData?['vatPercent']);
      final allocationMinAmount = _parsePositiveAmount(
        systemData?['allocationNumberMinAmountBeforeVat'],
      );
      if (!mounted) return;
      setState(() {
        _vatRate = vatPercent / 100;
        _allocationNumberMinAmountBeforeVat =
            allocationMinAmount ?? double.infinity;
      });
    } catch (e) {
      dev.log('Error loading VAT rate: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_invoiceBuilderLock.release());
    _clientNameController.dispose();
    _clientAddressController.dispose();
    _clientPhoneController.dispose();
    _clientEmailController.dispose();
    _clientIdController.dispose();
    _invoiceDateController.dispose();
    _paymentDueDateController.dispose();
    _itemDescController.dispose();
    _itemQtyController.dispose();
    _itemPriceController.dispose();
    _discountController.dispose();
    _notesController.dispose();
    _creditReasonController.dispose();
    _creditOriginalInvoiceNumberController.dispose();
    _creditOriginalInvoiceDateController.dispose();
    _creditReceiptConfirmationController.dispose();
    for (final methodEntry in _paymentMethods) {
      methodEntry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final fontData = await rootBundle.load(
        "assets/fonts/Rubik-VariableFont_wght.ttf",
      );
      _cachedFont = pw.Font.ttf(fontData);
      _cachedFontBold = pw.Font.ttf(fontData);
      final appIconData = await rootBundle.load('assets/icon/app_icon.jpg');
      _cachedAppIcon = pw.MemoryImage(appIconData.buffer.asUint8List());
    } catch (e) {
      dev.log("Font load failed: $e");
    }
  }

  Future<bool> _isTaxAuthorityConnected() async {
    try {
      final callable = _functions.httpsCallable(
        'getTaxAuthorityConnectionStatus',
      );
      final result = await callable.call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      return data['connected'] == true;
    } catch (e) {
      dev.log('Tax Authority connection check failed: $e');
      return false;
    }
  }

  Future<void> _openTaxAuthorityConnection() async {
    try {
      final callable = _functions.httpsCallable(
        'createTaxAuthorityAuthorizationUrl',
      );
      final response = await callable.call<Map<String, dynamic>>();
      final authorizationUrl = response.data['authorizationUrl']?.toString();
      final uri = Uri.tryParse(authorizationUrl ?? '');
      final opened =
          uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw StateError(
          'Tax Authority authorization URL could not be opened.',
        );
      }
    } catch (e) {
      dev.log('Failed to start Tax Authority connection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Tax Authority login.')),
        );
      }
    }
  }

  int _taxAuthorityInvoiceType() {
    return _selectedDocType == 'invoice_receipt' ? 320 : 305;
  }

  List<Map<String, dynamic>> _taxAuthorityItemsPayload() {
    final totalBeforeDiscount = _itemsSubtotalBeforeTax;
    final discountAmount = _discountAmount;
    var remainingDiscount = discountAmount;

    return _items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final isLastItem = index == _items.length - 1;
      final lineBeforeDiscount = _itemTotalBeforeTax(item);
      final proportionalDiscount = discountAmount > 0 && totalBeforeDiscount > 0
          ? discountAmount * (lineBeforeDiscount / totalBeforeDiscount)
          : 0.0;
      final lineDiscount = discountAmount > 0
          ? (isLastItem ? remainingDiscount : proportionalDiscount)
          : 0.0;
      remainingDiscount -= lineDiscount;
      final totalAmount = lineBeforeDiscount - lineDiscount;

      return {
        'index': index + 1,
        'description': item.description,
        'quantity': item.quantity,
        'price_per_unit': _unitPriceBeforeTax(item),
        'discount': lineDiscount,
        'total_amount': totalAmount,
        'vat_rate': _vatRate * 100,
        'vat_amount': totalAmount * _vatRate,
      };
    }).toList();
  }

  Future<_TaxAuthorityAllocationResult> _requestTaxAuthorityAllocation() async {
    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final businessVatNumber = _digitsOnly(_businessId);
    final customerVatNumber = _digitsOnly(_clientIdController.text);
    if (businessVatNumber.isEmpty || customerVatNumber.isEmpty) {
      throw StateError(strings['tax_authority_missing_tax_ids']!);
    }

    final invoiceDocId = _invoiceDocIdFor(_selectedDocType, _invoiceNumber);
    final callable = _functions.httpsCallable('requestTaxInvoiceAllocation');
    final HttpsCallableResult<Map<String, dynamic>> result;
    try {
      result = await callable.call<Map<String, dynamic>>({
        'invoiceDocId': invoiceDocId,
        'invoice': {
          'invoice_id': invoiceDocId,
          'invoice_type': _taxAuthorityInvoiceType(),
          'vat_number': int.parse(businessVatNumber),
          'user_name': (_workerName == null || _workerName!.isEmpty)
              ? 'Hiro'
              : _workerName,
          'invoice_reference_number': _invoiceNumber,
          'customer_vat_number': int.parse(customerVatNumber),
          'customer_name': _clientNameController.text.trim(),
          'invoice_date': _invoiceDateIsoValue(),
          'invoice_issuance_date': _invoiceDateIsoValue(),
          'accounting_software_number': _sandboxAccountingSoftwareNumber,
          'amount_before_discount': _itemsSubtotalBeforeTax,
          'discount': _discountAmount,
          'payment_amount': _subtotalAmount,
          'vat_amount': _vatAmount,
          'payment_amount_including_vat': _totalBeforeRoundingAmount,
          'invoice_note': _notesController.text.trim(),
          'action': 0,
          'items': _taxAuthorityItemsPayload(),
        },
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          e.message?.contains('OAuth authorization') == true) {
        throw StateError(strings['tax_authority_not_connected']!);
      }
      final authorityMessage = _taxAuthorityErrorMessageFromDetails(e.details);
      throw StateError(
        authorityMessage ??
            e.message ??
            strings['tax_authority_allocation_failed']!,
      );
    }
    final data = Map<String, dynamic>.from(result.data);
    final confirmationNumber = data['confirmationNumber']?.toString().trim();

    if (data['approved'] != true ||
        confirmationNumber == null ||
        confirmationNumber.isEmpty) {
      throw StateError(strings['tax_authority_allocation_failed']!);
    }

    return _TaxAuthorityAllocationResult(
      approved: data['approved'] == true,
      confirmationNumber: confirmationNumber,
      invoiceId: data['invoiceId']?.toString(),
      transactionId: data['transactionId']?.toString(),
      raw: data,
    );
  }

  String? _taxAuthorityErrorMessageFromDetails(dynamic details) {
    final messages = <String>{};

    void collect(dynamic value) {
      if (value is Map) {
        final message = value['message'];
        if (message is String && message.trim().isNotEmpty) {
          messages.add(message.trim());
        } else {
          collect(message);
        }
        for (final entry in value.values) {
          collect(entry);
        }
      } else if (value is Iterable) {
        for (final entry in value) {
          collect(entry);
        }
      }
    }

    collect(details);
    if (messages.isEmpty) return null;
    return messages.take(3).join('\n');
  }

  Future<void> _loadDefaultBusinessLogo() async {
    final logoUrl = _verifiedBusinessLogoUrl;
    if (_invoiceLogoTouched || logoUrl == null || logoUrl.isEmpty) return;

    setState(() => _isLoadingBusinessLogo = true);
    try {
      final ref = firebase_storage.FirebaseStorage.instance.refFromURL(logoUrl);
      final bytes = await ref.getData(3 * 1024 * 1024);
      if (!mounted || _invoiceLogoTouched) return;

      setState(() {
        _businessLogoBytes = bytes;
        _cachedLogo = bytes == null ? null : pw.MemoryImage(bytes);
        _isLoadingBusinessLogo = false;
      });
    } catch (e) {
      dev.log('Business logo load failed: $e');
      if (!mounted || _invoiceLogoTouched) return;
      setState(() => _isLoadingBusinessLogo = false);
    }
  }

  Future<void> _pickBusinessLogo() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _invoiceLogoTouched = true;
      _businessLogoBytes = bytes;
      _cachedLogo = pw.MemoryImage(bytes);
    });
  }

  void _removeBusinessLogo() {
    setState(() {
      _invoiceLogoTouched = true;
      _businessLogoBytes = null;
      _cachedLogo = null;
    });
  }

  Map<String, String> _getLocalizedStrings(
    BuildContext context, {
    bool listen = true,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;

    return _localizedStringsForLocale(locale);
  }

  Map<String, String> _localizedStringsForLocale(String locale) {
    if (_cachedStrings != null && _lastLocale == locale) {
      return _cachedStrings!;
    }

    _lastLocale = locale;
    switch (locale) {
      case 'he':
        _cachedStrings = {
          'title': 'מפיק מסמכים עסקיים',
          'invoice_builder_locked_title': 'יוצר החשבוניות כבר בשימוש',
          'invoice_builder_locked':
              'יוצר החשבוניות פתוח כעת במכשיר אחר. סגרו אותו במכשיר האחר ולאחר מכן נסו שוב.',
          'invoice_builder_locked_action': 'חזרה',
          'ok': 'אישור',
          'client_info': 'פרטי הלקוח:',
          'client_name': 'שם הלקוח',
          'client_id': 'מס\' עוסק / ת.ז. / ח.פ.',
          'client_address': 'כתובת הלקוח',
          'client_phone': 'טלפון הלקוח',
          'client_email': 'דוא״ל הלקוח',
          'client_details_required': 'יש למלא לפחות את שם הלקוח.',
          'client_id_invalid_length': 'מספר הלקוח חייב להיות בן 9 ספרות.',
          'client_id_invalid': 'מספר הלקוח אינו תקין.',
          'items': 'פירוט פריטים ושירותים',
          'desc': 'תיאור השירות/מוצר',
          'qty': 'כמות',
          'price': 'מחיר ליח\'',
          'price_tax_mode': 'מחיר כולל/לפני מע"מ',
          'price_before_tax': 'לפני מע"מ',
          'price_after_tax': 'כולל מע"מ',
          'has_discount': 'האם יש הנחה?',
          'discount_amount': 'סכום הנחה',
          'discount_invalid':
              'אם יש הנחה יש למלא סכום הנחה תקין שקטן או שווה לסכום הפריטים.',
          'discount': 'הנחה',
          'round_total': 'עיגול סכום',
          'rounding_amount': 'סכום לעיגול',
          'round_total_done': 'הסכום עוגל ל-{amount} ₪',
          'round_total_already': 'הסכום כבר מעוגל',
          'entered_price_before_tax': 'לפני מע"מ',
          'entered_price_after_tax': 'כולל מע"מ',
          'add_item': 'הוסף פריט',
          'total': 'סה"כ לתשלום',
          'generate': 'תצוגה מקדימה / הדפסה',
          'empty_items': 'נא להוסיף לפחות פריט אחד',
          'worker': 'פרטי העסק:',
          'date': 'תאריך:',
          'business_logo_section': 'לוגו לחשבונית',
          'business_logo': 'לוגו העסק',
          'business_logo_hint':
              'הלוגו שאימתת בעסק נטען כברירת מחדל ויופיע על החשבוניות שלך. אפשר להחליף או להסיר אותו למסמך הזה.',
          'add_logo': 'הוסף לוגו',
          'change_logo': 'החלף לוגו',
          'remove_logo': 'הסר לוגו',
          'verified_logo_badge': 'ברירת מחדל מאימות העסק',
          'payment_due_date': 'לתשלום עד:',
          'inv_no': 'מספר מסמך:',
          'invoice_counter': 'מונה חשבוניות',
          'preparing': 'מכין את המסמך...',
          'legal_disclaimer':
              'הופק באמצעות הירו. מסמך זה הינו מסמך ממוחשב המאושר ע"י רשות המסים בישראל. מקור.',
          'send_to_contact': 'שלח ישירות בצ׳אט',
          'send_to': 'שלח ל-',
          'no_contacts': 'לא נמצאו אנשי קשר',
          'sent_success': 'המסמך נשלח בהצלחה!',
          'notes': 'הערות נוספות ותנאי תשלום',
          'subtotal': 'סה"כ לפני מע"מ',
          'doc_type': 'סוג המסמך',
          'quote': 'הצעת מחיר',
          'work_order': 'הזמנת עבודה',
          'receipt': 'קבלה',
          'invoice': 'חשבונית מס',
          'invoice_receipt': 'חשבונית מס / קבלה',
          'credit_note': 'הודעת זיכוי',
          'licensed_only': 'זמין לעוסק מורשה מאומת בלבד',
          'vat_id': 'ח.פ / ע.מ:',
          'vat': 'מע"מ:',
          'original': 'מקור',
          'business_name': 'שם העסק:',
          'tax_invoice_num': 'חשבונית מס מס\':',
          'licensed_dealer': 'עוסק מורשה',
          'exempt_dealer': 'עוסק פטור',
          'company_dealer': 'חברה בע״מ',
          'business_address': 'כתובת העסק:',
          'worker_id': 'מזהה עובד:',
          'authorized_dealer_label': 'עובד מורשה:',
          'payment_method': 'אמצעי תשלום',
          'credit_note_legal': 'פרטי הודעת זיכוי',
          'credit_reason': 'סיבת הזיכוי',
          'original_invoice_number': 'מספר חשבונית מקור',
          'original_invoice_date': 'תאריך חשבונית מקור',
          'delivery_method': 'אופן מסירת הודעת הזיכוי',
          'receipt_confirmation': 'אסמכתא למסירה / אישור קבלה',
          'pick_date': 'בחירת תאריך',
          'delivery_registered_mail': 'דואר רשום',
          'delivery_email_confirmation': 'אישור דוא"ל',
          'delivery_customer_signature': 'חתימת לקוח',
          'delivery_manual': 'מסירה ידנית',
          'credit_note_missing_fields':
              'להודעת זיכוי יש למלא מספר חשבונית מקור, תאריך מקור, סיבת זיכוי ואסמכתא למסירה.',
          'credit_note_legal_hint':
              'לשימוש תקין בישראל יש לשמור קישור לחשבונית המקור ואסמכתא למסירת הודעת הזיכוי ללקוח.',
          'doc_start_title': 'מספר פתיחה למסמך',
          'doc_start_message':
              'זו הפעם הראשונה שאתה משתמש ב-{docType}. הזן את המספר שממנו המסמך הזה צריך להתחיל.',
          'doc_start_warning':
              'חשוב להזין את המספר הנכון. אם תזין מספר שגוי, האחריות היא שלך ולא תוכל לשנות אותו אחר כך.',
          'doc_start_field': 'מספר פתיחה',
          'doc_start_invalid': 'יש להזין מספר תקין גדול מ-0',
          'allocation_number': 'מספר הקצאה מרשות המס',
          'tax_authority_connect_title': 'חיבור לרשות המסים',
          'tax_authority_connect_message':
              'הסכום לפני מע"מ מחייב מספר הקצאה מרשות המסים. כדי לקבל אותו יש להתחבר לרשות המסים.',
          'tax_authority_connect_action': 'התחבר לרשות המסים',
          'tax_authority_continue_without_connection': 'להמשיך בלי חיבור',
          'tax_authority_requesting_allocation': 'מבקש מספר הקצאה מרשות המס...',
          'tax_authority_missing_tax_ids':
              'כדי לקבל מספר הקצאה יש למלא מספר עוסק של העסק ומספר עוסק/ת.ז. של הלקוח.',
          'tax_authority_not_connected':
              'צריך להשלים חיבור לרשות המסים לפני שמירת החשבונית.',
          'tax_authority_allocation_failed':
              'לא התקבל מספר הקצאה מרשות המס. החשבונית לא נשמרה.',
          'continue': 'המשך',
          'cancel': 'ביטול',
        };
        break;
      case 'ar':
        _cachedStrings = {
          'title': 'منشئ المستندات التجارية',
          'invoice_builder_locked_title': 'منشئ الفواتير قيد الاستخدام',
          'invoice_builder_locked':
              'منشئ الفواتير مفتوح حاليًا على جهاز آخر. أغلقه على الجهاز الآخر، ثم حاول مرة أخرى.',
          'invoice_builder_locked_action': 'رجوع',
          'ok': 'حسنًا',
          'client_info': 'تفاصيل العميل:',
          'client_name': 'اسم العميل',
          'client_id': 'رقم النشاط / الهوية / الرقم الضريبي',
          'client_address': 'عنوان العميل',
          'client_phone': 'هاتف العميل',
          'client_email': 'البريد الإلكتروني للعميل',
          'client_details_required': 'يرجى إدخال اسم العميل على الأقل.',
          'client_id_invalid_length': 'يجب أن يتكون رقم العميل من 9 أرقام.',
          'client_id_invalid': 'رقم العميل غير صالح.',
          'items': 'تفاصيل الخدمات والمنتجات',
          'desc': 'الوصف',
          'qty': 'الكمية',
          'price': 'سعر الوحدة',
          'price_tax_mode': 'حالة السعر الضريبية',
          'price_before_tax': 'قبل الضريبة',
          'price_after_tax': 'شامل الضريبة',
          'has_discount': 'هل يوجد خصم؟',
          'discount_amount': 'مبلغ الخصم',
          'discount_invalid':
              'عند تفعيل الخصم، أدخل مبلغًا صحيحًا يساوي أو يقل عن إجمالي العناصر.',
          'discount': 'الخصم',
          'round_total': 'تقريب المبلغ',
          'rounding_amount': 'مبلغ التقريب',
          'round_total_done': 'تم تقريب المبلغ إلى {amount} ₪',
          'round_total_already': 'المبلغ مقرب بالفعل',
          'entered_price_before_tax': 'قبل الضريبة',
          'entered_price_after_tax': 'شامل الضريبة',
          'add_item': 'إضافة عنصر',
          'total': 'الإجمالي المستحق',
          'generate': 'معاينة / طباعة',
          'empty_items': 'يرجى إضافة عنصر واحد على الأقل',
          'worker': 'تفاصيل النشاط التجاري:',
          'date': 'التاريخ:',
          'business_logo_section': 'شعار الفاتورة',
          'business_logo': 'شعار النشاط التجاري',
          'business_logo_hint':
              'سيتم تحميل الشعار الذي وثقته للنشاط التجاري كخيار افتراضي وسيظهر على فواتيرك. يمكنك تغييره أو إزالته لهذا المستند.',
          'add_logo': 'إضافة شعار',
          'change_logo': 'تغيير الشعار',
          'remove_logo': 'إزالة الشعار',
          'verified_logo_badge': 'افتراضي من توثيق النشاط',
          'payment_due_date': 'الدفع حتى:',
          'inv_no': 'رقم المستند:',
          'invoice_counter': 'عداد الفواتير',
          'preparing': 'جارٍ تجهيز المستند...',
          'legal_disclaimer':
              'تم إنشاؤه عبر hiro. هذا مستند محوسب معتمد من سلطة الضرائب الإسرائيلية. أصل.',
          'send_to_contact': 'إرسال إلى جهة الاتصال',
          'send_to': 'إرسال إلى ',
          'no_contacts': 'لم يتم العثور على جهات اتصال',
          'sent_success': 'تم إرسال المستند بنجاح!',
          'notes': 'ملاحظات / شروط الدفع',
          'subtotal': 'الإجمالي الفرعي قبل الضريبة',
          'doc_type': 'نوع المستند',
          'quote': 'عرض سعر',
          'work_order': 'أمر عمل',
          'receipt': 'إيصال',
          'invoice': 'فاتورة ضريبية',
          'invoice_receipt': 'فاتورة ضريبية / إيصال',
          'credit_note': 'إشعار دائن',
          'licensed_only': 'متاح فقط للتاجر المرخص الموثق',
          'vat_id': 'رقم الضريبة / الرقم الضريبي:',
          'vat': 'ضريبة القيمة المضافة:',
          'original': 'أصل',
          'business_name': 'اسم النشاط التجاري:',
          'tax_invoice_num': 'رقم الفاتورة الضريبية:',
          'licensed_dealer': 'تاجر مرخص',
          'exempt_dealer': 'تاجر معفى',
          'company_dealer': 'شركة محدودة',
          'business_address': 'عنوان النشاط التجاري:',
          'worker_id': 'معرّف العامل:',
          'authorized_dealer_label': 'تاجر معتمد:',
          'payment_method': 'طريقة الدفع',
          'credit_note_legal': 'تفاصيل الإشعار الدائن',
          'credit_reason': 'سبب الإشعار الدائن',
          'original_invoice_number': 'رقم الفاتورة الأصلية',
          'original_invoice_date': 'تاريخ الفاتورة الأصلية',
          'delivery_method': 'طريقة التسليم',
          'receipt_confirmation': 'إثبات التسليم / تأكيد الاستلام',
          'pick_date': 'اختر التاريخ',
          'delivery_registered_mail': 'بريد مسجل',
          'delivery_email_confirmation': 'تأكيد عبر البريد الإلكتروني',
          'delivery_customer_signature': 'توقيع العميل',
          'delivery_manual': 'تسليم يدوي',
          'credit_note_missing_fields':
              'يتطلب الإشعار الدائن رقم الفاتورة الأصلية وتاريخها وسبب الإشعار وإثبات التسليم.',
          'credit_note_legal_hint':
              'للامتثال في إسرائيل، احتفظ بمرجع الفاتورة الأصلية وإثبات تسليم الإشعار الدائن إلى العميل.',
          'doc_start_title': 'رقم بداية المستند',
          'doc_start_message':
              'هذه هي المرة الأولى التي تستخدم فيها {docType}. أدخل الرقم الذي يجب أن يبدأ منه هذا النوع من المستندات.',
          'doc_start_warning':
              'من المهم إدخال الرقم الصحيح. إذا أدخلت رقمًا خاطئًا، فستتحمل المسؤولية ولن تتمكن من تغييره لاحقًا.',
          'doc_start_field': 'رقم البداية',
          'doc_start_invalid': 'أدخل رقمًا صحيحًا أكبر من 0',
          'continue': 'متابعة',
          'cancel': 'إلغاء',
        };
        break;
      case 'ru':
        _cachedStrings = {
          'title': 'Конструктор бизнес-документов',
          'invoice_builder_locked_title': 'Конструктор счетов уже используется',
          'invoice_builder_locked':
              'Конструктор счетов сейчас открыт на другом устройстве. Закройте его там, затем повторите попытку.',
          'invoice_builder_locked_action': 'Назад',
          'ok': 'ОК',
          'client_info': 'Данные клиента:',
          'client_name': 'Имя клиента',
          'client_id': 'Номер бизнеса / ID / налоговый номер',
          'client_address': 'Адрес клиента',
          'client_phone': 'Телефон клиента',
          'client_email': 'Электронная почта клиента',
          'client_details_required':
              'Пожалуйста, укажите как минимум имя клиента.',
          'client_id_invalid_length': 'ID клиента должен состоять из 9 цифр.',
          'client_id_invalid': 'ID клиента недействителен.',
          'items': 'Товары и услуги',
          'desc': 'Описание',
          'qty': 'Кол-во',
          'price': 'Цена за единицу',
          'price_tax_mode': 'Режим цены по налогу',
          'price_before_tax': 'До налога',
          'price_after_tax': 'С налогом',
          'has_discount': 'Применить скидку?',
          'discount_amount': 'Сумма скидки',
          'discount_invalid':
              'Если скидка включена, введите корректную сумму, не превышающую общую сумму позиций.',
          'discount': 'Скидка',
          'round_total': 'Округлить сумму',
          'rounding_amount': 'Сумма округления',
          'round_total_done': 'Сумма округлена до {amount} ₪',
          'round_total_already': 'Сумма уже округлена',
          'entered_price_before_tax': 'До налога',
          'entered_price_after_tax': 'С налогом',
          'add_item': 'Добавить позицию',
          'total': 'Итого к оплате',
          'generate': 'Предпросмотр / Печать',
          'empty_items': 'Добавьте хотя бы одну позицию',
          'worker': 'Данные бизнеса:',
          'date': 'Дата:',
          'business_logo_section': 'Логотип счета',
          'business_logo': 'Логотип бизнеса',
          'business_logo_hint':
              'Логотип из подтверждения бизнеса загружается по умолчанию и будет показан в ваших счетах. Для этого документа его можно заменить или убрать.',
          'add_logo': 'Добавить логотип',
          'change_logo': 'Изменить логотип',
          'remove_logo': 'Удалить логотип',
          'verified_logo_badge': 'По умолчанию из проверки бизнеса',
          'payment_due_date': 'Оплатить до:',
          'inv_no': 'Номер документа:',
          'invoice_counter': 'Счетчик счетов',
          'preparing': 'Подготовка документа...',
          'legal_disclaimer':
              'Создано через hiro. Это компьютеризированный документ, одобренный Налоговым управлением Израиля. Оригинал.',
          'send_to_contact': 'Отправить контакту',
          'send_to': 'Отправить ',
          'no_contacts': 'Контакты не найдены',
          'sent_success': 'Документ успешно отправлен!',
          'notes': 'Примечания / условия оплаты',
          'subtotal': 'Подытог без НДС',
          'doc_type': 'Тип документа',
          'quote': 'Коммерческое предложение',
          'work_order': 'Заказ-наряд',
          'receipt': 'Квитанция',
          'invoice': 'Налоговый счет',
          'invoice_receipt': 'Налоговый счет / квитанция',
          'credit_note': 'Кредит-нота',
          'licensed_only':
              'Доступно только для подтвержденного лицензированного дилера',
          'vat_id': 'НДС / налоговый номер:',
          'vat': 'НДС:',
          'original': 'Оригинал',
          'business_name': 'Название бизнеса:',
          'tax_invoice_num': 'Номер налогового счета:',
          'licensed_dealer': 'Лицензированный дилер',
          'exempt_dealer': 'Освобожденный дилер',
          'company_dealer': 'Общество с ограниченной ответственностью',
          'business_address': 'Адрес бизнеса:',
          'worker_id': 'ID работника:',
          'authorized_dealer_label': 'Уполномоченный дилер:',
          'payment_method': 'Способ оплаты',
          'credit_note_legal': 'Данные кредит-ноты',
          'credit_reason': 'Причина возврата',
          'original_invoice_number': 'Номер исходного счета',
          'original_invoice_date': 'Дата исходного счета',
          'delivery_method': 'Способ доставки',
          'receipt_confirmation': 'Подтверждение доставки / получения',
          'pick_date': 'Выбрать дату',
          'delivery_registered_mail': 'Заказное письмо',
          'delivery_email_confirmation': 'Подтверждение по email',
          'delivery_customer_signature': 'Подпись клиента',
          'delivery_manual': 'Ручная доставка',
          'credit_note_missing_fields':
              'Для кредит-ноты необходимы номер исходного счета, дата исходного счета, причина возврата и подтверждение доставки.',
          'credit_note_legal_hint':
              'Для соответствия требованиям в Израиле храните ссылку на исходный счет и подтверждение вручения кредит-ноты клиенту.',
          'doc_start_title': 'Начальный номер документа',
          'doc_start_message':
              'Вы впервые используете {docType}. Введите номер, с которого должен начинаться этот тип документа.',
          'doc_start_warning':
              'Важно ввести правильный номер. Если вы введете неправильный номер, ответственность будет на вас, и позже его нельзя будет изменить.',
          'doc_start_field': 'Начальный номер',
          'doc_start_invalid': 'Введите корректный номер больше 0',
          'continue': 'Продолжить',
          'cancel': 'Отмена',
        };
        break;
      case 'am':
        _cachedStrings = {
          'title': 'የንግድ ሰነድ አዘጋጅ',
          'invoice_builder_locked_title': 'የኢንቮይስ አዘጋጁ በጥቅም ላይ ነው',
          'invoice_builder_locked':
              'የኢንቮይስ አዘጋጁ አሁን በሌላ መሣሪያ ላይ ክፍት ነው። በዚያ መሣሪያ ላይ ይዝጉት እና ከዚያ እንደገና ይሞክሩ።',
          'invoice_builder_locked_action': 'ተመለስ',
          'ok': 'እሺ',
          'client_info': 'የደንበኛ ዝርዝሮች:',
          'client_name': 'የደንበኛ ስም',
          'client_id': 'የንግድ ቁጥር / መታወቂያ / የግብር ቁጥር',
          'client_address': 'የደንበኛ አድራሻ',
          'client_phone': 'የደንበኛ ስልክ',
          'client_email': 'የደንበኛ ኢሜይል',
          'client_details_required': 'ቢያንስ የደንበኛውን ስም ያስገቡ።',
          'client_id_invalid_length': 'የደንበኛ መታወቂያ 9 አሃዞች መሆን አለበት።',
          'client_id_invalid': 'የደንበኛ መታወቂያው ትክክል አይደለም።',
          'items': 'የአገልግሎት እና የእቃ ዝርዝሮች',
          'desc': 'መግለጫ',
          'qty': 'ብዛት',
          'price': 'የአንዱ ዋጋ',
          'price_tax_mode': 'የዋጋ ግብር ሁኔታ',
          'price_before_tax': 'ከግብር በፊት',
          'price_after_tax': 'ግብር ጨምሮ',
          'has_discount': 'ቅናሽ አለ?',
          'discount_amount': 'የቅናሽ መጠን',
          'discount_invalid': 'ቅናሽ ከተመረጠ ከጠቅላላ ዕቃዎች መጠን ያልበለጠ ትክክለኛ መጠን ያስገቡ።',
          'discount': 'ቅናሽ',
          'round_total': 'ጠቅላላ ድምሩን አዙር',
          'rounding_amount': 'የማዞሪያ መጠን',
          'round_total_done': 'መጠኑ ወደ {amount} ₪ ተዞሯል',
          'round_total_already': 'መጠኑ አስቀድሞ ዙር ነው',
          'entered_price_before_tax': 'ከግብር በፊት',
          'entered_price_after_tax': 'ግብር ጨምሮ',
          'add_item': 'እቃ ጨምር',
          'total': 'ጠቅላላ ክፍያ',
          'generate': 'ቅድመ እይታ / አትም',
          'empty_items': 'ቢያንስ አንድ እቃ ያክሉ',
          'worker': 'የንግድ ዝርዝሮች:',
          'date': 'ቀን:',
          'business_logo_section': 'የደረሰኝ አርማ',
          'business_logo': 'የንግድ አርማ',
          'business_logo_hint':
              'በንግድ ማረጋገጫው ውስጥ ያከሉት አርማ እንደ ነባሪ ይጫናል እና በደረሰኞችዎ ላይ ይታያል። ለዚህ ሰነድ መቀየር ወይም ማስወገድ ይችላሉ።',
          'add_logo': 'አርማ ጨምር',
          'change_logo': 'አርማ ቀይር',
          'remove_logo': 'አርማ አስወግድ',
          'verified_logo_badge': 'ከንግድ ማረጋገጫ ነባሪ',
          'payment_due_date': 'እስከዚህ ቀን ይከፈል:',
          'inv_no': 'የሰነድ ቁጥር:',
          'invoice_counter': 'የደረሰኝ ቆጣሪ',
          'preparing': 'ሰነዱን በማዘጋጀት ላይ...',
          'legal_disclaimer':
              'በ hiro ተፈጥሯል። ይህ በእስራኤል የግብር ባለስልጣን የተፈቀደ ኮምፒውተራዊ ሰነድ ነው። ዋና ቅጂ።',
          'send_to_contact': 'ወደ ዕውቂያ ላክ',
          'send_to': 'ወደ ',
          'no_contacts': 'ምንም ዕውቂያዎች አልተገኙም',
          'sent_success': 'ሰነዱ በተሳካ ሁኔታ ተልኳል!',
          'notes': 'ማስታወሻዎች / የክፍያ ውሎች',
          'subtotal': 'ንዑስ ድምር (ከቫት በፊት)',
          'doc_type': 'የሰነድ አይነት',
          'quote': 'የዋጋ ቅናሽ ጥያቄ',
          'work_order': 'የስራ ትዕዛዝ',
          'receipt': 'ደረሰኝ',
          'invoice': 'የግብር ደረሰኝ',
          'invoice_receipt': 'የግብር ደረሰኝ / ደረሰኝ',
          'credit_note': 'የክሬዲት ማስታወሻ',
          'licensed_only': 'ለተረጋገጠ ፈቃድ ያለው ነጋዴ ብቻ ይገኛል',
          'vat_id': 'ቫት / የግብር ቁጥር:',
          'vat': 'ቫት:',
          'original': 'ዋና',
          'business_name': 'የንግድ ስም:',
          'tax_invoice_num': 'የግብር ደረሰኝ ቁጥር:',
          'licensed_dealer': 'ፈቃድ ያለው ነጋዴ',
          'exempt_dealer': 'ነፃ ነጋዴ',
          'company_dealer': 'ውስን ኩባንያ',
          'business_address': 'የንግድ አድራሻ:',
          'worker_id': 'የሰራተኛ መታወቂያ:',
          'authorized_dealer_label': 'የተፈቀደ ነጋዴ:',
          'payment_method': 'የክፍያ ዘዴ',
          'credit_note_legal': 'የክሬዲት ማስታወሻ ዝርዝሮች',
          'credit_reason': 'የክሬዲት ምክንያት',
          'original_invoice_number': 'የመጀመሪያው ደረሰኝ ቁጥር',
          'original_invoice_date': 'የመጀመሪያው ደረሰኝ ቀን',
          'delivery_method': 'የማድረስ ዘዴ',
          'receipt_confirmation': 'የማድረስ / የመቀበል ማረጋገጫ',
          'pick_date': 'ቀን ይምረጡ',
          'delivery_registered_mail': 'የተመዘገበ ፖስታ',
          'delivery_email_confirmation': 'የኢሜይል ማረጋገጫ',
          'delivery_customer_signature': 'የደንበኛ ፊርማ',
          'delivery_manual': 'በእጅ ማድረስ',
          'credit_note_missing_fields':
              'ለክሬዲት ማስታወሻ የመጀመሪያው ደረሰኝ ቁጥር፣ ቀን፣ ምክንያት እና የማድረስ ማረጋገጫ ያስፈልጋሉ።',
          'credit_note_legal_hint':
              'በእስራኤል ደንብ መሰረት የመጀመሪያውን ደረሰኝ ማጣቀሻ እና የክሬዲት ማስታወሻው ለደንበኛው እንደደረሰ ማረጋገጫ ያስቀምጡ።',
          'doc_start_title': 'የመነሻ ሰነድ ቁጥር',
          'doc_start_message':
              'ይህን {docType} ለመጀመሪያ ጊዜ እየተጠቀሙ ነው። ይህ የሰነድ አይነት የሚጀምርበትን ቁጥር ያስገቡ።',
          'doc_start_warning':
              'ትክክለኛውን ቁጥር ማስገባት አስፈላጊ ነው። የተሳሳተ ቁጥር ካስገቡ ኃላፊነቱ የእርስዎ ነው እና በኋላ መቀየር አይቻልም።',
          'doc_start_field': 'የመነሻ ቁጥር',
          'doc_start_invalid': 'ከ0 በላይ የሆነ ትክክለኛ ቁጥር ያስገቡ',
          'continue': 'ቀጥል',
          'cancel': 'ሰርዝ',
        };
        break;
      default:
        _cachedStrings = {
          'title': 'Business Document Builder',
          'invoice_builder_locked_title': 'Invoice Builder Is In Use',
          'invoice_builder_locked':
              'Invoice Builder is currently open on another device. Close it there, then try again.',
          'invoice_builder_locked_action': 'Back',
          'ok': 'OK',
          'client_info': 'Client Details:',
          'client_name': 'Client Name',
          'client_id': 'Business No. / ID / Tax ID',
          'client_address': 'Client Address',
          'client_phone': 'Client Phone',
          'client_email': 'Client Email',
          'client_details_required': 'Please fill at least the client name.',
          'client_id_invalid_length': 'Client ID must be 9 digits.',
          'client_id_invalid': 'Client ID is not valid.',
          'items': 'Service Items & Details',
          'desc': 'Description',
          'qty': 'Qty',
          'price': 'Unit Price',
          'price_tax_mode': 'Price Tax Mode',
          'price_before_tax': 'Before Tax',
          'price_after_tax': 'After Tax',
          'has_discount': 'Apply Discount?',
          'discount_amount': 'Discount Amount',
          'discount_invalid':
              'When discount is enabled, enter a valid amount less than or equal to items total.',
          'discount': 'Discount',
          'round_total': 'Round Total',
          'rounding_amount': 'Rounding Amount',
          'round_total_done': 'Amount rounded to {amount} ₪',
          'round_total_already': 'The amount is already rounded',
          'entered_price_before_tax': 'Before Tax',
          'entered_price_after_tax': 'After Tax',
          'add_item': 'Add Item',
          'total': 'Grand Total',
          'generate': 'Preview / Print PDF',
          'empty_items': 'Please add at least one item',
          'worker': 'Business Details:',
          'date': 'Date:',
          'business_logo_section': 'Document Logo',
          'business_logo': 'Business Logo',
          'business_logo_hint':
              'Your verified business logo loads by default and appears on your documents. You can change or remove it for this document.',
          'add_logo': 'Add Logo',
          'change_logo': 'Change Logo',
          'remove_logo': 'Remove Logo',
          'verified_logo_badge': 'Default from business verification',
          'payment_due_date': 'Pay Until:',
          'inv_no': 'Document No:',
          'invoice_counter': 'Invoice Counter',
          'preparing': 'Preparing document...',
          'legal_disclaimer':
              'Generated via hiro. This is a computerized document authorized by the Israel Tax Authority. Original.',
          'send_to_contact': 'Send to Contact',
          'send_to': 'Send to ',
          'no_contacts': 'No contacts found',
          'sent_success': 'Invoice sent successfully!',
          'notes': 'Notes / Payment Terms',
          'subtotal': 'Subtotal (Excl. VAT)',
          'doc_type': 'Document Type',
          'quote': 'Quote',
          'work_order': 'Work Order',
          'receipt': 'Receipt',
          'invoice': 'Tax Invoice',
          'invoice_receipt': 'Tax Invoice / Receipt',
          'credit_note': 'Credit Note',
          'licensed_only': 'Verified Licensed Dealers only',
          'vat_id': 'VAT ID / Tax ID:',
          'vat': 'VAT:',
          'original': 'Original',
          'business_name': 'Business Name:',
          'tax_invoice_num': 'Tax Invoice No:',
          'licensed_dealer': 'Licensed Dealer',
          'exempt_dealer': 'Exempt Dealer',
          'company_dealer': 'Limited Company',
          'business_address': 'Business Address:',
          'worker_id': 'Worker ID:',
          'authorized_dealer_label': 'Authorized Dealer:',
          'payment_method': 'Payment Method',
          'credit_note_legal': 'Credit Note Details',
          'credit_reason': 'Reason for Credit',
          'original_invoice_number': 'Original Invoice Number',
          'original_invoice_date': 'Original Invoice Date',
          'delivery_method': 'Delivery Method',
          'receipt_confirmation': 'Delivery / Receipt Confirmation',
          'pick_date': 'Pick Date',
          'delivery_registered_mail': 'Registered Mail',
          'delivery_email_confirmation': 'Email Confirmation',
          'delivery_customer_signature': 'Customer Signature',
          'delivery_manual': 'Manual Delivery',
          'credit_note_missing_fields':
              'Credit notes require original invoice number, original invoice date, reason for credit, and delivery proof.',
          'credit_note_legal_hint':
              'For Israeli compliance, keep the original invoice reference and proof that the credit note was delivered to the customer.',
          'doc_start_title': 'Starting Document Number',
          'doc_start_message':
              'This is your first time using {docType}. Enter the number this document type should start from.',
          'doc_start_warning':
              'It is important to enter the correct number. If you enter the wrong number, it is your responsibility and you will not be able to change it later.',
          'doc_start_field': 'Starting Number',
          'doc_start_invalid': 'Enter a valid number greater than 0',
          'allocation_number': 'Tax Authority allocation number',
          'tax_authority_connect_title': 'Connect to the Tax Authority',
          'tax_authority_connect_message':
              'This amount before VAT requires a Tax Authority allocation number. Connect to request it.',
          'tax_authority_connect_action': 'Connect to Tax Authority',
          'tax_authority_continue_without_connection': 'Continue without it',
          'tax_authority_requesting_allocation':
              'Requesting Tax Authority allocation number...',
          'tax_authority_missing_tax_ids':
              'To request an allocation number, enter the business tax ID and the customer tax ID.',
          'tax_authority_not_connected':
              'Complete the Tax Authority connection before saving this invoice.',
          'tax_authority_allocation_failed':
              'No allocation number was received from the Tax Authority. The invoice was not saved.',
          'continue': 'Continue',
          'cancel': 'Cancel',
        };
    }
    return _cachedStrings!;
  }

  Map<String, String> _withRequiredDefaults(Map<String, String> source) {
    const defaults = {
      'title': 'Business Document Builder',
      'invoice_builder_locked_title': 'Invoice Builder Is In Use',
      'invoice_builder_locked':
          'Invoice Builder is currently open on another device. Close it there, then try again.',
      'invoice_builder_locked_action': 'Back',
      'ok': 'OK',
      'preparing': 'Preparing document...',
      'doc_type': 'Document Type',
      'quote': 'Quote',
      'work_order': 'Work Order',
      'receipt': 'Receipt',
      'invoice': 'Tax Invoice',
      'invoice_receipt': 'Tax Invoice / Receipt',
      'credit_note': 'Credit Note',
      'licensed_only': 'Verified Licensed Dealers only',
      'invoice_counter': 'Invoice Counter',
      'client_info': 'Client Details:',
      'client_name': 'Client Name',
      'client_id': 'Business No. / ID / Tax ID',
      'client_phone': 'Client Phone',
      'client_email': 'Client Email',
      'client_address': 'Client Address',
      'client_details_required': 'Please fill at least the client name.',
      'client_id_invalid_length': 'Client ID must be 9 digits.',
      'client_id_invalid': 'Client ID is not valid.',
      'items': 'Service Items & Details',
      'desc': 'Description',
      'qty': 'Qty',
      'price': 'Unit Price',
      'price_tax_mode': 'Price Tax Mode',
      'price_before_tax': 'Before Tax',
      'price_after_tax': 'After Tax',
      'has_discount': 'Apply Discount?',
      'discount_amount': 'Discount Amount',
      'discount_invalid':
          'When discount is enabled, enter a valid amount less than or equal to items total.',
      'discount': 'Discount',
      'round_total': 'Round Total',
      'rounding_amount': 'Rounding Amount',
      'round_total_done': 'Amount rounded to {amount} ₪',
      'round_total_already': 'The amount is already rounded',
      'entered_price_before_tax': 'Before Tax',
      'entered_price_after_tax': 'After Tax',
      'add_item': 'Add Item',
      'notes': 'Notes / Payment Terms',
      'total': 'Grand Total',
      'generate': 'Preview / Print PDF',
      'empty_items': 'Please add at least one item',
      'send_to_contact': 'Send to Contact',
      'no_contacts': 'No contacts found',
      'sent_success': 'Invoice sent successfully!',
      'worker': 'Business Details:',
      'date': 'Date:',
      'business_logo_section': 'Document Logo',
      'business_logo': 'Business Logo',
      'business_logo_hint':
          'Your verified business logo loads by default and appears on your documents. You can change or remove it for this document.',
      'add_logo': 'Add Logo',
      'change_logo': 'Change Logo',
      'remove_logo': 'Remove Logo',
      'verified_logo_badge': 'Default from business verification',
      'payment_due_date': 'Pay Until:',
      'inv_no': 'Document No:',
      'tax_invoice_num': 'Tax Invoice No:',
      'original': 'Original',
      'business_name': 'Business Name:',
      'business_address': 'Business Address:',
      'worker_id': 'Worker ID:',
      'subtotal': 'Subtotal (Excl. VAT)',
      'vat': 'VAT:',
      'legal_disclaimer':
          'Generated via hiro. This is a computerized document authorized by the Israel Tax Authority. Original.',
      'licensed_dealer': 'Licensed Dealer',
      'exempt_dealer': 'Exempt Dealer',
      'company_dealer': 'Limited Company',
      'vat_id': 'VAT ID / Tax ID:',
      'authorized_dealer_label': 'Authorized Dealer:',
      'credit_note_legal': 'Credit Note Details',
      'credit_reason': 'Reason for Credit',
      'original_invoice_number': 'Original Invoice Number',
      'original_invoice_date': 'Original Invoice Date',
      'delivery_method': 'Delivery Method',
      'receipt_confirmation': 'Delivery / Receipt Confirmation',
      'pick_date': 'Pick Date',
      'delivery_registered_mail': 'Registered Mail',
      'delivery_email_confirmation': 'Email Confirmation',
      'delivery_customer_signature': 'Customer Signature',
      'delivery_manual': 'Manual Delivery',
      'credit_note_missing_fields':
          'Credit notes require original invoice number, original invoice date, reason for credit, and delivery proof.',
      'credit_note_legal_hint':
          'For Israeli compliance, keep the original invoice reference and proof that the credit note was delivered to the customer.',
      'doc_start_title': 'Starting Document Number',
      'doc_start_message':
          'This is your first time using {docType}. Enter the number this document type should start from.',
      'doc_start_warning':
          'It is important to enter the correct number. If you enter the wrong number, it is your responsibility and you will not be able to change it later.',
      'doc_start_field': 'Starting Number',
      'doc_start_invalid': 'Enter a valid number greater than 0',
      'allocation_number': 'Tax Authority allocation number',
      'tax_authority_connect_title': 'Connect to the Tax Authority',
      'tax_authority_connect_message':
          'This amount before VAT requires a Tax Authority allocation number. Connect to request it.',
      'tax_authority_connect_action': 'Connect to Tax Authority',
      'tax_authority_continue_without_connection': 'Continue without it',
      'tax_authority_requesting_allocation':
          'Requesting Tax Authority allocation number...',
      'tax_authority_missing_tax_ids':
          'To request an allocation number, enter the business tax ID and the customer tax ID.',
      'tax_authority_not_connected':
          'Complete the Tax Authority connection before saving this invoice.',
      'tax_authority_allocation_failed':
          'No allocation number was received from the Tax Authority. The invoice was not saved.',
      'continue': 'Continue',
      'cancel': 'Cancel',
    };

    return {...defaults, ...source};
  }

  void _addItem() {
    if (_itemDescController.text.isEmpty || _itemPriceController.text.isEmpty) {
      return;
    }
    final price =
        double.tryParse(
          _itemPriceController.text.trim().replaceAll(',', '.'),
        ) ??
        0.0;
    final qty = int.tryParse(_itemQtyController.text) ?? 1;
    setState(() {
      final newItem = InvoiceItem(
        description: _itemDescController.text,
        quantity: qty,
        price: price,
        isPriceBeforeTax: _selectedPriceTaxMode == 'before_tax',
      );
      _items.add(newItem);
      _itemDescController.clear();
      _itemPriceController.clear();
      _itemQtyController.text = "1";
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _loadCurrentDocumentNumber({
    bool promptIfMissing = false,
  }) async {
    if (!_requiresSequentialDocumentNumber) {
      if (mounted) {
        setState(() {
          _currentDocumentCounter = null;
          _invoiceNumber = '';
          _isLoadingCounterAssignment = false;
        });
      }
      return;
    }

    final ref = _counterRefForDocType(_selectedDocType);
    if (ref == null) return;

    if (mounted) {
      setState(() {
        _isLoadingCounterAssignment = true;
      });
    }

    try {
      final snapshot = await ref.get();
      final storedCounter = (snapshot.data()?['value'] as num?)?.toInt();
      if (!mounted) return;

      if (storedCounter != null && storedCounter > 0) {
        setState(() {
          _currentDocumentCounter = storedCounter;
          _invoiceNumber = _formatDocumentNumber(storedCounter);
          _isLoadingCounterAssignment = false;
        });
        return;
      }

      setState(() {
        _currentDocumentCounter = null;
        _invoiceNumber = '';
        _isLoadingCounterAssignment = false;
      });

      if (promptIfMissing) {
        final assigned = await _promptForStartingDocumentNumber();
        if (!assigned && mounted) {
          Navigator.of(context).maybePop();
        }
      }
    } catch (e) {
      dev.log('Error loading document counter: $e');
      if (mounted) {
        setState(() {
          _isLoadingCounterAssignment = false;
        });
      }
    }
  }

  Future<bool> _ensureDocumentNumberAssigned() async {
    if (!_requiresSequentialDocumentNumber) {
      return true;
    }
    if (_currentDocumentCounter != null && _invoiceNumber.isNotEmpty) {
      return true;
    }
    return _promptForStartingDocumentNumber();
  }

  Future<bool> _promptForStartingDocumentNumber() async {
    final ref = _counterRefForDocType(_selectedDocType);
    if (ref == null || !mounted) return false;

    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final controller = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(strings['doc_start_title']!),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings['doc_start_message']!.replaceFirst(
                      '{docType}',
                      _documentTypeDisplayName(strings, _selectedDocType),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings['doc_start_warning']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: strings['doc_start_field']!,
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  icon: const BackButtonIcon(),
                  label: Text(
                    MaterialLocalizations.of(dialogContext).backButtonTooltip,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final parsed = int.tryParse(controller.text.trim());
                    if (parsed == null || parsed < 1) {
                      setDialogState(() {
                        errorText = strings['doc_start_invalid']!;
                      });
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(strings['continue']!),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return false;

    final startNumber = int.parse(controller.text.trim());
    try {
      await ref.set({
        'value': startNumber,
        'docType': _selectedDocType,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return false;
      setState(() {
        _currentDocumentCounter = startNumber;
        _invoiceNumber = _formatDocumentNumber(startNumber);
        _isLoadingCounterAssignment = false;
      });
      return true;
    } catch (e) {
      dev.log('Error saving starting document counter: $e');
      return false;
    } finally {
      controller.dispose();
    }
  }

  bool get _isWaitingForStartingNumber =>
      _requiresSequentialDocumentNumber &&
      !_isLoadingCounterAssignment &&
      (_currentDocumentCounter == null || _invoiceNumber.isEmpty);

  String _documentTypeDisplayName(Map<String, String> strings, String docType) {
    switch (docType) {
      case 'quote':
        return strings['quote']!;
      case 'work_order':
        return strings['work_order']!;
      case 'invoice':
        return strings['invoice']!;
      case 'invoice_receipt':
        return strings['invoice_receipt']!;
      case 'credit_note':
        return strings['credit_note']!;
      case 'receipt':
      default:
        return strings['receipt']!;
    }
  }

  Future<Uint8List?> _getGeneratedPdfBytes({String? allocationNumber}) async {
    if (_items.isEmpty) return null;

    try {
      if (_cachedFont == null) await _loadAssets();
      return await _generatePdf(
        pdf.PdfPageFormat.a4,
        _cachedFont!,
        _cachedFontBold!,
        _cachedLogo,
        appIcon: _cachedAppIcon,
        allocationNumber: allocationNumber,
      );
    } catch (e) {
      dev.log("Error generating PDF: $e");
      return null;
    }
  }

  Widget _buildBusinessLogoSection(Map<String, String> strings) {
    final hasLogo =
        _businessLogoBytes != null && _businessLogoBytes!.isNotEmpty;

    return _buildSectionCard(
      title: strings['business_logo_section']!,
      icon: Icons.image_outlined,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _isLoadingBusinessLogo
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : hasLogo
                        ? Image.memory(_businessLogoBytes!, fit: BoxFit.cover)
                        : const Icon(
                            Icons.storefront_outlined,
                            size: 34,
                            color: Color(0xFF94A3B8),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings['business_logo']!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings['business_logo_hint']!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (!_invoiceLogoTouched &&
                            (_verifiedBusinessLogoUrl?.isNotEmpty ?? false) &&
                            hasLogo) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              strings['verified_logo_badge']!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickBusinessLogo,
                    icon: Icon(
                      hasLogo ? Icons.refresh_rounded : Icons.upload_outlined,
                    ),
                    label: Text(
                      hasLogo ? strings['change_logo']! : strings['add_logo']!,
                    ),
                  ),
                  if (hasLogo)
                    TextButton(
                      onPressed: _removeBusinessLogo,
                      child: Text(strings['remove_logo']!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _validateCreditNoteLegalFields() {
    if (!_isCreditNote) return true;

    final strings = _getLocalizedStrings(context, listen: false);
    final missing =
        _creditOriginalInvoiceNumberController.text.trim().isEmpty ||
        _creditOriginalInvoiceDateController.text.trim().isEmpty ||
        _creditReasonController.text.trim().isEmpty ||
        _creditReceiptConfirmationController.text.trim().isEmpty;

    if (!missing) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings['credit_note_missing_fields']!)),
    );
    return false;
  }

  bool _validateClientDetails() {
    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final missingClientDetails = _clientNameController.text.trim().isEmpty;

    if (missingClientDetails) {
      final locale = Provider.of<LanguageProvider>(
        context,
        listen: false,
      ).locale.languageCode;
      final fallback = (locale == 'he' || locale == 'ar')
          ? 'יש למלא לפחות את שם הלקוח.'
          : 'Please fill at least the client name.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings['client_details_required'] ?? fallback)),
      );
      return false;
    }

    final clientIdDigits = _digitsOnly(_clientIdController.text);
    if (clientIdDigits.isNotEmpty && clientIdDigits.length != 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings['client_id_invalid_length']!)),
      );
      return false;
    }
    if (clientIdDigits.isNotEmpty && !isValidIsraeliId(clientIdDigits)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['client_id_invalid']!)));
      return false;
    }

    return true;
  }

  bool _validateDiscount() {
    if (!_hasDiscount) return true;

    final strings = _getLocalizedStrings(context, listen: false);
    final parsed = double.tryParse(
      _discountController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0 || parsed > _itemsTotalBeforeDiscount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['discount_invalid']!)));
      return false;
    }
    return true;
  }

  String _paymentMethodLabel(bool isRtl, String method) {
    switch (method) {
      case 'credit':
        return isRtl ? 'אשראי' : 'Credit Card';
      case 'transfer':
        return isRtl ? 'העברה בנקאית' : 'Bank Transfer';
      case 'check':
        return isRtl ? 'צ׳ק' : 'Check';
      case 'cash':
      default:
        return isRtl ? 'מזומן' : 'Cash';
    }
  }

  String _creditDealTypeLabel(bool isRtl, String dealType) {
    switch (dealType) {
      case 'installments':
        return isRtl ? 'תשלומים' : 'Installments';
      case 'credit':
        return isRtl ? 'קרדיט' : 'Credit';
      case 'other':
        return isRtl ? 'אחר' : 'Other';
      case 'regular':
      default:
        return isRtl ? 'רגיל' : 'Regular';
    }
  }

  double? _parsePaymentAmount(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  double _paymentMethodsAmountTotal() {
    var total = 0.0;
    for (final methodEntry in _paymentMethods) {
      total += _parsePaymentAmount(methodEntry.amountController.text) ?? 0.0;
    }
    return total;
  }

  bool _validatePaymentMethods() {
    if (!_showsPaymentMethodSection) return true;

    final strings = _getLocalizedStrings(context, listen: false);
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    for (var i = 0; i < _paymentMethods.length; i++) {
      final methodEntry = _paymentMethods[i];
      final amount = _parsePaymentAmount(methodEntry.amountController.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'חובה למלא סכום תשלום תקין בכל אמצעי תשלום (שורה ${i + 1}).'
                  : 'A valid payment amount is required for each payment method (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'check' &&
          methodEntry.checkNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'בשיטת צ׳ק חובה למלא מספר צ׳ק (שורה ${i + 1}).'
                  : 'Check number is required for check payments (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'credit' &&
          methodEntry.creditDealType == 'installments') {
        final installments = methodEntry.installmentsController.text.trim();
        final parsed = int.tryParse(installments);
        if (installments.isEmpty || parsed == null || parsed < 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRtl
                    ? 'באשראי מסוג תשלומים חובה לרשום מספר תשלומים תקין (שורה ${i + 1}).'
                    : 'Installments count is required for installment credit payments (row ${i + 1}).',
              ),
            ),
          );
          return false;
        }
      }

      if (methodEntry.method == 'transfer') {
        final bank = methodEntry.transferBankController.text.trim();
        final branch = methodEntry.transferBranchController.text.trim();
        final account = methodEntry.transferAccountController.text.trim();
        if (bank.isEmpty || branch.isEmpty || account.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRtl
                    ? 'בהעברה בנקאית חובה למלא בנק, סניף ומספר חשבון (שורה ${i + 1}).'
                    : 'Bank transfer requires bank name, branch, and account number (row ${i + 1}).',
              ),
            ),
          );
          return false;
        }
      }
    }

    if (_paymentMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings['payment_method'] ??
                (isRtl
                    ? 'יש לבחור אמצעי תשלום'
                    : 'Select at least one payment method'),
          ),
        ),
      );
      return false;
    }

    final paidTotal = _paymentMethodsAmountTotal();
    final expectedTotal = _totalAmount;
    if ((paidTotal - expectedTotal).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'סה״כ התשלומים (${paidTotal.toStringAsFixed(2)} ₪) חייב להיות שווה לסה״כ לתשלום (${expectedTotal.toStringAsFixed(2)} ₪).'
                : 'Total payments (${paidTotal.toStringAsFixed(2)} ₪) must equal grand total (${expectedTotal.toStringAsFixed(2)} ₪).',
          ),
        ),
      );
      return false;
    }

    return true;
  }

  String _paymentMethodsSummaryText(bool isRtl) {
    if (_paymentMethods.isEmpty) {
      return _paymentMethodLabel(isRtl, 'cash');
    }
    final sections = <String>[];
    for (final methodEntry in _paymentMethods) {
      final parts = <String>[_paymentMethodLabel(isRtl, methodEntry.method)];
      final amount = _parsePaymentAmount(methodEntry.amountController.text);
      if (amount != null) {
        parts.add(
          '${isRtl ? 'סכום ששולם: ' : 'Amount Paid: '}${amount.toStringAsFixed(2)} ₪',
        );
      }
      if (methodEntry.method == 'credit') {
        final cardNumber = methodEntry.cardNumberController.text.trim();
        final cardName = methodEntry.cardNameController.text.trim();
        if (cardNumber.isNotEmpty) {
          parts.add((isRtl ? 'מספר כרטיס: ' : 'Card Number: ') + cardNumber);
        }
        if (cardName.isNotEmpty) {
          parts.add((isRtl ? 'שם כרטיס: ' : 'Card Name: ') + cardName);
        }
        parts.add(
          (isRtl ? 'סוג העסקה: ' : 'Deal Type: ') +
              _creditDealTypeLabel(isRtl, methodEntry.creditDealType),
        );
        if (methodEntry.creditDealType == 'installments') {
          final installments = methodEntry.installmentsController.text.trim();
          if (installments.isNotEmpty) {
            parts.add(
              (isRtl ? 'מספר תשלומים: ' : 'Installments: ') + installments,
            );
          }
        }
      } else if (methodEntry.method == 'check') {
        final checkNumber = methodEntry.checkNumberController.text.trim();
        if (checkNumber.isNotEmpty) {
          parts.add((isRtl ? 'מספר צ׳ק: ' : 'Check Number: ') + checkNumber);
        }
        final bank = methodEntry.checkBankController.text.trim();
        final branch = methodEntry.checkBranchController.text.trim();
        final account = methodEntry.checkAccountController.text.trim();
        if (bank.isNotEmpty) {
          parts.add((isRtl ? 'בנק: ' : 'Bank: ') + bank);
        }
        if (branch.isNotEmpty) {
          parts.add((isRtl ? 'סניף: ' : 'Branch: ') + branch);
        }
        if (account.isNotEmpty) {
          parts.add((isRtl ? 'חשבון בנק: ' : 'Bank Account: ') + account);
        }
      } else if (methodEntry.method == 'transfer') {
        final bank = methodEntry.transferBankController.text.trim();
        final branch = methodEntry.transferBranchController.text.trim();
        final account = methodEntry.transferAccountController.text.trim();
        if (bank.isNotEmpty) {
          parts.add((isRtl ? 'בנק: ' : 'Bank: ') + bank);
        }
        if (branch.isNotEmpty) {
          parts.add((isRtl ? 'סניף: ' : 'Branch: ') + branch);
        }
        if (account.isNotEmpty) {
          parts.add((isRtl ? 'חשבון בנק: ' : 'Bank Account: ') + account);
        }
      }
      sections.add(parts.join(' | '));
    }
    return sections.join('\n--------------------\n');
  }

  Future<void> _pickCreditOriginalInvoiceDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null || !mounted) return;
    _creditOriginalInvoiceDateController.text = intl.DateFormat(
      'dd/MM/yyyy',
    ).format(picked);
  }

  Future<void> _openPreviewPage() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _getLocalizedStrings(context, listen: false)['empty_items']!,
          ),
        ),
      );
      return;
    }
    if (!_validateClientDetails()) {
      return;
    }

    if (!_validateCreditNoteLegalFields()) {
      return;
    }
    if (!_validateDiscount()) {
      return;
    }
    if (!_validatePaymentMethods()) {
      return;
    }

    final assigned = await _ensureDocumentNumberAssigned();
    if (!assigned) {
      return;
    }

    setState(() => _isPreparing = true);

    try {
      final pdfBytes = await _getGeneratedPdfBytes();
      if (pdfBytes == null) {
        if (mounted) setState(() => _isPreparing = false);
        return;
      }

      if (!mounted) return;
      setState(() => _isPreparing = false);

      InvoiceBuilderDraftResult? savedDraftResult;
      final action = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewPage(
            pdfBytes: pdfBytes,
            fileName: _previewFileName(),
            requireTaxAuthorityConnectionPrompt:
                _requiresTaxAuthorityAllocation,
            isTaxAuthorityConnected: _isTaxAuthorityConnected,
            onConnectTaxAuthority: _openTaxAuthorityConnection,
            onSave: () async {
              var finalPdfBytes = pdfBytes;
              Map<String, dynamic>? taxAuthorityAllocation;

              if (_requiresTaxAuthorityAllocation) {
                final strings = _withRequiredDefaults(
                  _getLocalizedStrings(context, listen: false),
                );
                final connected = await _isTaxAuthorityConnected();
                if (!connected) {
                  throw StateError(strings['tax_authority_not_connected']!);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        strings['tax_authority_requesting_allocation']!,
                      ),
                    ),
                  );
                }
                final allocation = await _requestTaxAuthorityAllocation();
                taxAuthorityAllocation = allocation.toMap();
                final allocatedPdfBytes = await _getGeneratedPdfBytes(
                  allocationNumber: allocation.confirmationNumber,
                );
                if (allocatedPdfBytes == null) {
                  throw StateError(strings['tax_authority_allocation_failed']!);
                }
                finalPdfBytes = allocatedPdfBytes;
              }

              savedDraftResult = await _createInvoiceAndLog(
                pdfBytes: finalPdfBytes,
                taxAuthorityAllocation: taxAuthorityAllocation,
              );
              return finalPdfBytes;
            },
            onSendForSignature: _isQuoteLike
                ? () async {
                    final saved = savedDraftResult;
                    if (saved == null) {
                      throw StateError(
                        _getLocalizedStrings(
                              context,
                              listen: false,
                            )['save_before_signing'] ??
                            'Save the document before sending it for signature.',
                      );
                    }
                    await _sendForSignature(saved);
                  }
                : null,
          ),
        ),
      );

      if (action == 'send' && mounted) {
        if (widget.returnDraftOnSend) {
          Navigator.pop(context, savedDraftResult);
          return;
        }
        if (widget.receiverId != null && savedDraftResult != null) {
          final sent = await _sendSavedInvoiceToContact(
            widget.receiverId!,
            widget.receiverName ?? "User",
            savedDraftResult!,
          );
          if (sent && mounted) {
            Navigator.pop(context);
          }
        } else if (widget.receiverId != null) {
          final sent = await _sendToContact(
            widget.receiverId!,
            widget.receiverName ?? "User",
          );
          if (sent && mounted) {
            Navigator.pop(context);
          }
        } else {
          await _showContactPickerAndSend(savedInvoice: savedDraftResult);
        }
      }

      await _loadCurrentDocumentNumber();
    } catch (e) {
      if (mounted) setState(() => _isPreparing = false);
      dev.log("PDF Layout Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
      }
    }
  }

  Future<_SavedInvoiceResult?> _saveInvoicePdf(
    Uint8List pdfBytes, {
    String? receiverNameOverride,
    bool showFeedback = true,
  }) async {
    final assigned = await _ensureDocumentNumberAssigned();
    if (!assigned) return null;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final receiverName = receiverNameOverride?.trim().isNotEmpty == true
        ? receiverNameOverride!.trim()
        : (widget.receiverName?.trim().isNotEmpty == true
              ? widget.receiverName!.trim()
              : (_clientNameController.text.trim().isNotEmpty
                    ? _clientNameController.text.trim()
                    : 'Client'));
    final userInvoicesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('invoices');
    final invoiceDocId = _requiresSequentialDocumentNumber
        ? _invoiceDocIdFor(_selectedDocType, _invoiceNumber)
        : userInvoicesRef.doc().id;
    final invoiceRef = userInvoicesRef.doc(invoiceDocId);
    final counterRef = _requiresSequentialDocumentNumber
        ? _counterRefForDocType(_selectedDocType)
        : null;

    try {
      final existingByInvoice = _requiresSequentialDocumentNumber
          ? await invoiceRef.get()
          : null;
      if (existingByInvoice?.exists == true) {
        final existingData = existingByInvoice?.data() ?? <String, dynamic>{};
        if (showFeedback && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Provider.of<LanguageProvider>(
                          context,
                          listen: false,
                        ).locale.languageCode ==
                        'he'
                    ? 'החשבונית כבר נשמרה'
                    : 'Invoice already saved',
              ),
            ),
          );
        }
        return _SavedInvoiceResult(
          url: (existingData['url'] ?? '').toString(),
          fileName: (existingData['fileName'] ?? _previewFileName()).toString(),
          wasCreated: false,
        );
      }

      final datePart = intl.DateFormat(
        'yyyy-MM-dd',
      ).format(_selectedInvoiceDate);
      final baseName = '$receiverName $datePart';

      final existing = await userInvoicesRef
          .where('baseName', isEqualTo: baseName)
          .get();

      final suffixIndex = existing.docs.length + 1;
      final finalName = suffixIndex == 1
          ? baseName
          : '$baseName ($suffixIndex)';
      final safeName = _safeFileName(finalName);
      final storagePath = 'invoices/${currentUser.uid}/$safeName.pdf';

      final ref = firebase_storage.FirebaseStorage.instance.ref().child(
        storagePath,
      );
      await ref.putData(pdfBytes);
      final downloadUrl = await ref.getDownloadURL();

      await invoiceRef.set({
        'name': finalName,
        'baseName': baseName,
        'receiverName': receiverName,
        'fileName': '$finalName.pdf',
        'storagePath': storagePath,
        'url': downloadUrl,
        'amount': _totalAmount,
        'clientName': _clientNameController.text,
        'clientAddress': _clientAddressController.text,
        'clientPhone': _clientPhoneController.text,
        'clientEmail': _clientEmailController.text.trim(),
        'clientTaxId': _clientIdController.text.trim(),
        'paymentMethod': _paymentMethods.isNotEmpty
            ? _paymentMethods.first.method
            : 'cash',
        'paymentMethods': _paymentMethods
            .map((entry) => entry.toMap())
            .toList(),
        'paymentAmountTotal': _paymentMethodsAmountTotal(),
        'priceTaxModeDefault': _selectedPriceTaxMode,
        'hasDiscount': _hasDiscount,
        'discountAmount': _manualDiscountAmount,
        'roundTotalEnabled': _roundTotalEnabled,
        'roundingAmount': _roundingAmount,
        'docType': _selectedDocType,
        if (_showsDueDateSection && _selectedPaymentDueDate != null)
          'paymentDueDate': _paymentDueDateStorageValue(),
        'invoiceDocId': invoiceDocId,
        'createdAt': FieldValue.serverTimestamp(),
        if (_invoiceNumber.isNotEmpty) 'invoiceNumber': _invoiceNumber,
        if (_currentDocumentCounter != null)
          'sequenceNumber': _currentDocumentCounter,
        if (_creditNoteLegalData != null)
          'creditNoteLegal': _creditNoteLegalData,
      });

      if (counterRef != null && _currentDocumentCounter != null) {
        await counterRef.set({
          'value': _currentDocumentCounter! + 1,
          'docType': _selectedDocType,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) {
          setState(() {
            _currentDocumentCounter = _currentDocumentCounter! + 1;
            _invoiceNumber = _formatDocumentNumber(_currentDocumentCounter!);
          });
        }
      }
      if (!_isQuoteLike) {
        await _addToTotalEarned(
          userId: currentUser.uid,
          amount: _isCreditNote ? -_totalAmount : _totalAmount,
        );
      }

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Provider.of<LanguageProvider>(
                        context,
                        listen: false,
                      ).locale.languageCode ==
                      'he'
                  ? 'החשבונית נשמרה בהצלחה'
                  : 'Invoice saved successfully',
            ),
          ),
        );
      }

      return _SavedInvoiceResult(
        url: downloadUrl,
        fileName: '$finalName.pdf',
        wasCreated: true,
      );
    } catch (e) {
      dev.log('Save invoice error: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save invoice.')));
      return null;
    }
  }

  Future<void> _addToTotalEarned({
    required String userId,
    required double amount,
  }) async {
    final totalEarnedRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('metadata')
        .doc('financial_summary');

    await totalEarnedRef.set({
      'totalEarned': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _safeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  Future<void> _showContactPickerAndSend({
    InvoiceBuilderDraftResult? savedInvoice,
  }) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _getLocalizedStrings(context, listen: false)['empty_items']!,
          ),
        ),
      );
      return;
    }

    if (widget.receiverId != null) {
      if (savedInvoice != null) {
        _sendSavedInvoiceToContact(
          widget.receiverId!,
          widget.receiverName ?? "User",
          savedInvoice,
        );
      } else {
        _sendToContact(widget.receiverId!, widget.receiverName ?? "User");
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final strings = _getLocalizedStrings(context, listen: false);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings['send_to_contact']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_rooms')
                      .where('users', arrayContains: user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final rooms = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final List users = data['users'] ?? [];
                      return !users.contains('hiro_manager');
                    }).toList();

                    if (rooms.isEmpty) {
                      return Center(child: Text(strings['no_contacts']!));
                    }

                    return ListView.builder(
                      itemCount: rooms.length,
                      itemBuilder: (context, index) {
                        final data =
                            rooms[index].data() as Map<String, dynamic>;
                        final otherId = (data['users'] as List).firstWhere(
                          (id) => id != user.uid,
                        );
                        final otherName =
                            data['user_names']?[otherId] ?? "User";

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF1976D2,
                            ).withValues(alpha: 0.1),
                            child: Text(
                              otherName[0].toUpperCase(),
                              style: const TextStyle(color: Color(0xFF1976D2)),
                            ),
                          ),
                          title: Text(otherName),
                          onTap: () {
                            Navigator.pop(context);
                            if (savedInvoice != null) {
                              _sendSavedInvoiceToContact(
                                otherId,
                                otherName,
                                savedInvoice,
                              );
                            } else {
                              _sendToContact(otherId, otherName);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _sendSavedInvoiceToContact(
    String receiverId,
    String receiverName,
    InvoiceBuilderDraftResult saved,
  ) async {
    if (saved.url.isEmpty) return false;

    try {
      if (mounted) setState(() => _isPreparing = true);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final ids = [currentUser.uid, receiverId]..sort();
      final roomId = ids.join('_');
      final documentLabel = saved.documentNumber?.isNotEmpty == true
          ? saved.documentNumber!
          : (_invoiceNumber.isNotEmpty
                ? _invoiceNumber
                : _labelForDocType(saved.docType));
      final messageText = 'Sent a document: $documentLabel';

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'senderId': currentUser.uid,
            'receiverId': receiverId,
            'message': messageText,
            'text': messageText,
            'type': 'file',
            'url': saved.url,
            'fileUrl': saved.url,
            'fileName': saved.fileName,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });

      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set(
        {
          'lastMessage': messageText,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'users': [currentUser.uid, receiverId],
          'user_names': {
            currentUser.uid: widget.workerName,
            receiverId: receiverName,
          },
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() => _isPreparing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _getLocalizedStrings(context, listen: false)['sent_success']!,
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _isPreparing = false);
      dev.log("Error sending saved PDF: $e");
      return false;
    }
  }

  Future<String> _createSigningLink(
    InvoiceBuilderDraftResult saved, {
    String? receiverId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('createDocumentSigningRequest');
    final result = await callable.call(<String, dynamic>{
      'invoiceDocId': saved.invoiceDocId,
      if (receiverId != null && receiverId.isNotEmpty) 'receiverId': receiverId,
    });
    final link = (result.data as Map<Object?, Object?>?)?['url']?.toString();
    if (link == null || link.isEmpty) {
      throw StateError('The signing link could not be created.');
    }
    return link;
  }

  Future<void> _sendSigningLinkToContact(
    InvoiceBuilderDraftResult saved,
    String receiverId,
    String receiverName,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final link = await _createSigningLink(saved, receiverId: receiverId);
    final ids = [currentUser.uid, receiverId]..sort();
    final roomId = ids.join('_');
    final label = _labelForDocType(saved.docType);
    final messageText = 'מסמך לחתימה: $label';

    await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .add({
          'senderId': currentUser.uid,
          'receiverId': receiverId,
          'message': messageText,
          'text': messageText,
          'type': 'file',
          'url': link,
          'fileUrl': link,
          'fileName': '$label - לחתימה',
          'signingRequest': true,
          'invoiceDocId': saved.invoiceDocId,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });

    await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set({
      'lastMessage': messageText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastTimestamp': FieldValue.serverTimestamp(),
      'users': [currentUser.uid, receiverId],
      'user_names': {
        currentUser.uid: widget.workerName,
        receiverId: receiverName,
      },
      'unreadCount.$receiverId': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('users')
        .doc(receiverId)
        .collection('notifications')
        .add({
          'type': 'chat_message',
          'title': widget.workerName,
          'body': messageText,
          'message': messageText,
          'fromId': currentUser.uid,
          'fromName': widget.workerName,
          'chatPartnerId': currentUser.uid,
          'chatPartnerName': widget.workerName,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _sendForSignature(InvoiceBuilderDraftResult saved) async {
    if (widget.receiverId != null) {
      await _sendSigningLinkToContact(
        saved,
        widget.receiverId!,
        widget.receiverName ?? 'User',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הקישור לחתימה נשלח בצ׳אט')),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'שליחת מסמך לחתימה',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.chat_bubble_rounded),
                title: const Text('שלח בצ׳אט של Hiro'),
                onTap: () => Navigator.pop(sheetContext, 'hiro'),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('שלח באפליקציה אחרת'),
                onTap: () => Navigator.pop(sheetContext, 'external'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'external') {
      final link = await _createSigningLink(saved);
      await SharePlus.instance.share(
        ShareParams(text: 'נא לפתוח את המסמך, לחתום ולשלוח אותו מחדש:\n$link'),
      );
      return;
    }

    await _showSigningContactPicker(saved);
  }

  Future<void> _showSigningContactPicker(
    InvoiceBuilderDraftResult saved,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.65,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'בחר לקוח',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chat_rooms')
                        .where('users', arrayContains: user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rooms = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final users = (data['users'] as List?) ?? const [];
                        return !users.contains('hiro_manager');
                      }).toList();
                      if (rooms.isEmpty) {
                        return const Center(child: Text('לא נמצאו שיחות'));
                      }
                      return ListView.builder(
                        itemCount: rooms.length,
                        itemBuilder: (context, index) {
                          final data =
                              rooms[index].data() as Map<String, dynamic>;
                          final users = (data['users'] as List).cast<String>();
                          final otherId = users.firstWhere(
                            (id) => id != user.uid,
                          );
                          final otherName =
                              data['user_names']?[otherId]?.toString() ??
                              'User';
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_rounded),
                            ),
                            title: Text(otherName),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await _sendSigningLinkToContact(
                                saved,
                                otherId,
                                otherName,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('הקישור לחתימה נשלח בצ׳אט'),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _sendToContact(String receiverId, String receiverName) async {
    if (!_validateClientDetails()) {
      return false;
    }
    if (!_validateCreditNoteLegalFields()) {
      return false;
    }
    if (!_validateDiscount()) {
      return false;
    }
    if (!_validatePaymentMethods()) {
      return false;
    }

    final assigned = await _ensureDocumentNumberAssigned();
    if (!assigned) {
      return false;
    }

    setState(() => _isPreparing = true);
    final pdfBytes = await _getGeneratedPdfBytes();

    if (pdfBytes == null) {
      if (mounted) setState(() => _isPreparing = false);
      return false;
    }

    try {
      final saved = await _saveInvoicePdf(
        pdfBytes,
        receiverNameOverride: receiverName,
        showFeedback: false,
      );
      if (saved == null || saved.url.isEmpty) {
        if (mounted) setState(() => _isPreparing = false);
        return false;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final ids = [currentUser.uid, receiverId]..sort();
      final roomId = ids.join('_');

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'senderId': currentUser.uid,
            'receiverId': receiverId,
            'message': _invoiceNumber.isNotEmpty
                ? 'Sent a document: $_invoiceNumber'
                : 'Sent a document: ${_labelForDocType(_selectedDocType)}',
            'text': _invoiceNumber.isNotEmpty
                ? 'Sent a document: $_invoiceNumber'
                : 'Sent a document: ${_labelForDocType(_selectedDocType)}',
            'type': 'file',
            'url': saved.url,
            'fileUrl': saved.url,
            'fileName': saved.fileName,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });

      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set(
        {
          'lastMessage': _invoiceNumber.isNotEmpty
              ? 'Sent a document: $_invoiceNumber'
              : 'Sent a document: ${_labelForDocType(_selectedDocType)}',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'users': [currentUser.uid, receiverId],
          'user_names': {
            currentUser.uid: widget.workerName,
            receiverId: receiverName,
          },
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() => _isPreparing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _getLocalizedStrings(context, listen: false)['sent_success']!,
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _isPreparing = false);
      dev.log("Error sending PDF: $e");
      return false;
    }
  }

  Future<Uint8List> _generatePdf(
    pdf.PdfPageFormat format,
    pw.Font font,
    pw.Font fontBold,
    pw.MemoryImage? logo, {
    pw.MemoryImage? appIcon,
    String? allocationNumber,
  }) async {
    final doc = pw.Document();
    final strings = _localizedStringsForLocale('he');

    final isInvoice =
        _selectedDocType == 'invoice' || _selectedDocType == 'invoice_receipt';
    final docTitle = _selectedDocType == 'quote'
        ? strings['quote']!
        : _selectedDocType == 'work_order'
        ? strings['work_order']!
        : _selectedDocType == 'receipt'
        ? strings['receipt']!
        : _selectedDocType == 'invoice'
        ? strings['invoice']!
        : _selectedDocType == 'invoice_receipt'
        ? strings['invoice_receipt']!
        : _selectedDocType == 'credit_note'
        ? strings['credit_note']!
        : strings['doc_type']!;
    final creditNoteLegalData = _creditNoteLegalData;
    final cleanAllocationNumber = allocationNumber?.trim();
    final generatedAt = intl.DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.now());
    final signingDocumentLabel = _invoiceNumber.isEmpty
        ? docTitle
        : '$docTitle $_invoiceNumber';
    final pdfInvoiceNumber = _invoiceNumberForPdf(_invoiceNumber);

    doc.addPage(
      pw.MultiPage(
        pageFormat: format.copyWith(
          marginTop: 1.5 * pdf.PdfPageFormat.cm,
          marginBottom: 57,
          marginLeft: 1.5 * pdf.PdfPageFormat.cm,
          marginRight: 1.5 * pdf.PdfPageFormat.cm,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (pw.Context context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: pw.BoxDecoration(
                  color: pdf.PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      pw.Container(
                        margin: const pw.EdgeInsets.only(left: 18),
                        child: pw.Image(
                          logo,
                          width: 112,
                          height: 112,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            docTitle,
                            style: pw.TextStyle(
                              fontSize: 28,
                              fontWeight: pw.FontWeight.bold,
                              color: pdf.PdfColors.blue900,
                            ),
                          ),
                          pw.Text(
                            strings['original']!,
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: pdf.PdfColors.blueGrey800,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          if (_invoiceNumber.isNotEmpty)
                            pw.Text(
                              isInvoice
                                  ? "${strings['tax_invoice_num']} $pdfInvoiceNumber"
                                  : "${strings['inv_no']} $_invoiceNumber",
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 14,
                                color: pdf.PdfColors.blueGrey800,
                              ),
                            ),
                          if (isInvoice &&
                              cleanAllocationNumber != null &&
                              cleanAllocationNumber.isNotEmpty)
                            pw.Text(
                              "${strings['allocation_number'] ?? 'מספר הקצאה מרשות המס'}: $cleanAllocationNumber",
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                                color: pdf.PdfColors.blueGrey800,
                              ),
                            ),
                          pw.Text(
                            "${strings['date']} ${_formattedInvoiceDate()}",
                            style: pw.TextStyle(
                              fontSize: 12,
                              color: pdf.PdfColors.blueGrey800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
            ],
          ),
        ),
        footer: (pw.Context context) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            if (!_isQuoteLike)
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Divider(
                      thickness: 0.8,
                      color: pdf.PdfColors.blueGrey900,
                    ),
                    pw.SizedBox(height: 6),
                    pw.Directionality(
                      textDirection: pw.TextDirection.ltr,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: 220,
                            child: pw.Align(
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Directionality(
                                textDirection: pw.TextDirection.rtl,
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.SizedBox(
                                      width: double.infinity,
                                      child: pw.Align(
                                        alignment: pw.Alignment.centerLeft,
                                        child: pw.Directionality(
                                          textDirection: pw.TextDirection.rtl,
                                          child: pw.Text(
                                            'הופק ב $generatedAt | $docTitle${pdfInvoiceNumber.isEmpty ? '' : ' $pdfInvoiceNumber'}',
                                            textAlign: pw.TextAlign.left,
                                            style: pw.TextStyle(
                                              fontSize: 11,
                                              color: pdf.PdfColors.blueGrey900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 7),
                                    pw.SizedBox(
                                      width: double.infinity,
                                      child: pw.Align(
                                        alignment: pw.Alignment.centerLeft,
                                        child: pw.Directionality(
                                          textDirection: pw.TextDirection.ltr,
                                          child: pw.Text(
                                            '${context.pageNumber} / ${context.pagesCount}',
                                            style: pw.TextStyle(
                                              fontSize: 13,
                                              color: pdf.PdfColors.blueGrey700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          pw.Spacer(),
                          pw.SizedBox(
                            width: 250,
                            child: pw.Align(
                              alignment: pw.Alignment.centerRight,
                              child: pw.Directionality(
                                textDirection: pw.TextDirection.rtl,
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                                  children: [
                                    pw.SizedBox(
                                      width: double.infinity,
                                      child: pw.Text(
                                        'חתימה דיגיטלית מאובטחת',
                                        textAlign: pw.TextAlign.right,
                                        style: pw.TextStyle(
                                          fontSize: 21,
                                          fontWeight: pw.FontWeight.bold,
                                          color: pdf.PdfColors.black,
                                        ),
                                      ),
                                    ),
                                    pw.SizedBox(height: 3),
                                    pw.SizedBox(
                                      width: double.infinity,
                                      child: pw.Directionality(
                                        textDirection: pw.TextDirection.ltr,
                                        child: pw.Row(
                                          mainAxisAlignment:
                                              pw.MainAxisAlignment.end,
                                          children: [
                                            if (appIcon != null) ...[
                                              pw.Image(
                                                appIcon,
                                                width: 20,
                                                height: 20,
                                                fit: pw.BoxFit.contain,
                                              ),
                                              pw.SizedBox(width: 4),
                                            ],
                                            pw.Directionality(
                                              textDirection:
                                                  pw.TextDirection.rtl,
                                              child: pw.Text(
                                                'מסמך ממוחשב הופק על ידי הירו',
                                                style: pw.TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      pdf.PdfColors.blueGrey900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (_isQuoteLike)
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  '${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: pdf.PdfColors.blueGrey700,
                  ),
                ),
              ),
          ],
        ),
        build: (pw.Context context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Business & Client Info
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Business Details
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: pdf.PdfColors.blue50,
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'פרטי העסק',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: pdf.PdfColors.blue900,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              (_businessName == null || _businessName!.isEmpty)
                                  ? widget.workerName
                                  : _businessName!,
                              style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              '${_dealerType == 'company'
                                  ? 'חברה בע״מ'
                                  : _isLicensedDealerType
                                  ? 'עוסק מורשה'
                                  : 'עוסק פטור'}: ${_businessId ?? ''}',
                              style: pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              'כתובת העסק: ${_businessAddress ?? ''}',
                              style: pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              'טלפון: ${widget.workerPhone ?? ''}',
                              style: pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              'דוא״ל: ${widget.workerEmail ?? ''}',
                              style: pw.TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 24),
                    // Client Details
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: pdf.PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'פרטי לקוח',
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: pdf.PdfColors.blue900,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              'לכבוד: ${_clientNameController.text}',
                              style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if (_clientIdController.text.trim().isNotEmpty)
                              pw.Text(
                                "${strings['client_id']!}: ${_clientIdController.text.trim()}",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            if (_clientPhoneController.text.isNotEmpty)
                              pw.Text(
                                'טלפון: ${_clientPhoneController.text}',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            if (_clientEmailController.text.trim().isNotEmpty)
                              pw.Text(
                                'דוא״ל: ${_clientEmailController.text.trim()}',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            if (_clientAddressController.text.isNotEmpty)
                              pw.Text(
                                'כתובת: ${_clientAddressController.text}',
                                style: pw.TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 28),
                if (creditNoteLegalData != null) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColors.amber50,
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: pdf.PdfColors.amber200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          strings['credit_note_legal']!,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 13,
                            color: pdf.PdfColors.orange900,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          "${strings['original_invoice_number']!}: ${creditNoteLegalData['originalInvoiceNumber']}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "${strings['original_invoice_date']!}: ${creditNoteLegalData['originalInvoiceDate']}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "${strings['credit_reason']!}: ${creditNoteLegalData['creditReason']}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "${strings['delivery_method']!}: ${_creditDeliveryMethodLabel(strings, creditNoteLegalData['deliveryMethod'] as String)}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.Text(
                          "${strings['receipt_confirmation']!}: ${creditNoteLegalData['receiptConfirmation']}",
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 18),
                ],
                // Items Table
                pw.TableHelper.fromTextArray(
                  headers: [
                    strings['desc']!,
                    strings['qty']!,
                    strings['price']!,
                    strings['total']!,
                  ],
                  data: _items
                      .map(
                        (item) => [
                          item.description,
                          item.quantity.toString(),
                          "${_unitPriceAfterTax(item).toStringAsFixed(2)} ₪",
                          "${_signedItemTotal(item).toStringAsFixed(2)} ₪",
                        ],
                      )
                      .toList(),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: pdf.PdfColors.white,
                    fontSize: 12,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: pdf.PdfColors.blue,
                  ),
                  cellAlignment: pw.Alignment.centerRight,
                  cellStyle: const pw.TextStyle(fontSize: 11),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FixedColumnWidth(60),
                    2: const pw.FixedColumnWidth(100),
                    3: const pw.FixedColumnWidth(100),
                  },
                  border: pw.TableBorder.all(
                    color: pdf.PdfColors.grey400,
                    width: 0.5,
                  ),
                ),
                pw.SizedBox(height: 18),
                // Summary Box
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(14),
                    width: 260,
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(color: pdf.PdfColors.blue100),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (_selectedDocType != 'receipt' &&
                            _isLicensedDealerType) ...[
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                strings['subtotal']!,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Text(
                                "${_signedSubtotalAmount.toStringAsFixed(2)} ₪",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                _vatLabel(true),
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Text(
                                "${_signedVatAmount.toStringAsFixed(2)} ₪",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          pw.Divider(
                            thickness: 1,
                            color: pdf.PdfColors.grey400,
                          ),
                        ],
                        if (_discountAmount > 0) ...[
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                strings['discount']!,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Text(
                                "-${_discountAmount.toStringAsFixed(2)} ₪",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          pw.Divider(
                            thickness: 1,
                            color: pdf.PdfColors.grey400,
                          ),
                        ],
                        if (_roundingAmount > 0) ...[
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                strings['rounding_amount']!,
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Text(
                                "${_signedRoundingAmount.toStringAsFixed(2)} ₪",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          pw.Divider(
                            thickness: 1,
                            color: pdf.PdfColors.grey400,
                          ),
                        ],
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              strings['total']!,
                              style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: pdf.PdfColors.blue900,
                              ),
                            ),
                            pw.Text(
                              "${_signedTotalAmount.toStringAsFixed(2)} ₪",
                              style: pw.TextStyle(
                                fontSize: 15,
                                fontWeight: pw.FontWeight.bold,
                                color: pdf.PdfColors.blue900,
                              ),
                            ),
                          ],
                        ),
                        if (_showsDueDateSection &&
                            _selectedPaymentDueDate != null) ...[
                          pw.SizedBox(height: 8),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                strings['payment_due_date']!,
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  color: pdf.PdfColors.blueGrey800,
                                ),
                              ),
                              pw.Text(
                                _formattedPaymentDueDate(),
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: pdf.PdfColors.blueGrey800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_showsPaymentMethodSection) ...[
                  pw.SizedBox(height: 24),
                  pw.Text(
                    strings['payment_method']!,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: pdf.PdfColors.blue900,
                    ),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: pdf.PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Text(
                      _paymentMethodsSummaryText(true),
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],
                if (_notesController.text.isNotEmpty) ...[
                  pw.Text(
                    strings['notes']!,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: pdf.PdfColors.blue900,
                    ),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: pdf.PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Text(
                      _notesController.text,
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],
              ],
            ),
          ),
          if (_isQuoteLike) pw.NewPage(freeSpace: 170),
          if (_isQuoteLike) pw.Spacer(),
          if (_isQuoteLike)
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Container(
                height: 160,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'חתימה:',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: pdf.PdfColors.blueGrey800,
                          ),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Container(
                          width: 230,
                          height: 12,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: pdf.PdfColors.blueGrey800,
                                width: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 18),
                    pw.Divider(thickness: 1, color: pdf.PdfColors.blueGrey900),
                    pw.SizedBox(height: 10),
                    pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        'חתימה דיגיטלית מאובטחת',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: pdf.PdfColors.black,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Directionality(
                      textDirection: pw.TextDirection.ltr,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text(
                                'הופק ב $generatedAt | $signingDocumentLabel',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: pdf.PdfColors.blueGrey900,
                                ),
                                textAlign: pw.TextAlign.left,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 18),
                          pw.Expanded(
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Text(
                                'מסמך זה מיועד לחתימה דיגיטלית '
                                'באמצעות מערכת הירו',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  color: pdf.PdfColors.blueGrey900,
                                ),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAcquiringLock) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasInvoiceBuilderLock) {
      return const SizedBox.shrink();
    }

    final strings = _withRequiredDefaults(_getLocalizedStrings(context));
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return FutureBuilder<SubscriptionAccessState>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data?.isUnsubscribedWorker == true) {
          return Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: SubscriptionAccessService.buildLockedScaffold(
              title: strings['title']!,
              message: isRtl
                  ? 'יצירת חשבוניות זמינה רק לבעלי מנוי Pro פעיל.'
                  : 'Invoice creation is available only with an active Pro subscription.',
            ),
          );
        }

        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              title: Text(
                strings['title']!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1976D2),
              elevation: 0,
              centerTitle: true,
            ),
            body: _isPreparing
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF1976D2),
                        ),
                        const SizedBox(height: 16),
                        Text(strings['preparing']!),
                      ],
                    ),
                  )
                : _isLoadingCounterAssignment || _isWaitingForStartingNumber
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFF1976D2),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            strings['doc_start_title']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            strings['doc_start_message']!.replaceFirst(
                              '{docType}',
                              _documentTypeDisplayName(
                                strings,
                                _selectedDocType,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionCard(
                          title: strings['doc_type']!,
                          icon: Icons.article_outlined,
                          children: [
                            DropdownButtonFormField<String>(
                              key: ValueKey(_selectedDocType),
                              isExpanded: true,
                              initialValue: _selectedDocType,
                              decoration: _inputStyle(
                                strings['doc_type']!,
                                Icons.description_outlined,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'quote',
                                  child: Text(strings['quote']!),
                                ),
                                DropdownMenuItem(
                                  value: 'work_order',
                                  child: Text(strings['work_order']!),
                                ),
                                DropdownMenuItem(
                                  value: 'receipt',
                                  child: Text(strings['receipt']!),
                                ),
                                DropdownMenuItem(
                                  value: 'invoice',
                                  enabled:
                                      _isLicensedDealerType &&
                                      _isBusinessVerified,
                                  child: Text(
                                    strings['invoice']! +
                                        ((!_isLicensedDealerType ||
                                                !_isBusinessVerified)
                                            ? " (${strings['licensed_only']})"
                                            : ""),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          (_isLicensedDealerType &&
                                              _isBusinessVerified)
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'invoice_receipt',
                                  enabled:
                                      _isLicensedDealerType &&
                                      _isBusinessVerified,
                                  child: Text(
                                    strings['invoice_receipt']! +
                                        ((!_isLicensedDealerType ||
                                                !_isBusinessVerified)
                                            ? " (${strings['licensed_only']})"
                                            : ""),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          (_isLicensedDealerType &&
                                              _isBusinessVerified)
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'credit_note',
                                  child: Text(strings['credit_note']!),
                                ),
                              ],
                              onChanged: (val) async {
                                if (val == null) return;
                                setState(() {
                                  _selectedDocType = val;
                                  _currentDocumentCounter = null;
                                  _invoiceNumber = '';
                                });
                                await _loadCurrentDocumentNumber(
                                  promptIfMissing: true,
                                );
                              },
                            ),
                            if (_isCreditNote) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFDBA74),
                                  ),
                                ),
                                child: Text(
                                  strings['credit_note_legal_hint']!,
                                  style: const TextStyle(
                                    color: Color(0xFF9A3412),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildBusinessLogoSection(strings),
                        const SizedBox(height: 20),
                        if (_isCreditNote) ...[
                          _buildSectionCard(
                            title: strings['credit_note_legal']!,
                            icon: Icons.gavel_rounded,
                            children: [
                              _buildTextField(
                                _creditOriginalInvoiceNumberController,
                                strings['original_invoice_number']!,
                                Icons.receipt_long_outlined,
                                required: true,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller:
                                    _creditOriginalInvoiceDateController,
                                readOnly: true,
                                onTap: _pickCreditOriginalInvoiceDate,
                                decoration:
                                    _inputStyle(
                                      strings['original_invoice_date']!,
                                      Icons.event_outlined,
                                      required: true,
                                    ).copyWith(
                                      suffixIcon: TextButton(
                                        onPressed:
                                            _pickCreditOriginalInvoiceDate,
                                        child: Text(strings['pick_date']!),
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _creditReasonController,
                                maxLines: 3,
                                decoration: _inputStyle(
                                  strings['credit_reason']!,
                                  Icons.rule_folder_outlined,
                                  required: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey(_selectedCreditDeliveryMethod),
                                initialValue: _selectedCreditDeliveryMethod,
                                decoration: _inputStyle(
                                  strings['delivery_method']!,
                                  Icons.local_shipping_outlined,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'email_confirmation',
                                    child: Text(
                                      strings['delivery_email_confirmation']!,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'registered_mail',
                                    child: Text(
                                      strings['delivery_registered_mail']!,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'customer_signature',
                                    child: Text(
                                      strings['delivery_customer_signature']!,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'manual_delivery',
                                    child: Text(strings['delivery_manual']!),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    _selectedCreditDeliveryMethod = val;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller:
                                    _creditReceiptConfirmationController,
                                maxLines: 2,
                                decoration: _inputStyle(
                                  strings['receipt_confirmation']!,
                                  Icons.verified_outlined,
                                  required: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Payment Method Section
                        const SizedBox(height: 20),
                        _buildSectionCard(
                          title: strings['client_info']!,
                          icon: Icons.person_add_alt_1_rounded,
                          children: [
                            _buildTextField(
                              _clientNameController,
                              strings['client_name']!,
                              Icons.person_outline,
                              required: true,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              _clientIdController,
                              strings['client_id']!,
                              Icons.badge_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              _clientPhoneController,
                              strings['client_phone']!,
                              Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              _clientEmailController,
                              strings['client_email']!,
                              Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              _clientAddressController,
                              strings['client_address']!,
                              Icons.location_on_outlined,
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        _buildSectionCard(
                          title: strings['date']!,
                          icon: Icons.event_outlined,
                          children: [
                            TextField(
                              controller: _invoiceDateController,
                              readOnly: true,
                              onTap: _pickInvoiceDate,
                              decoration:
                                  _inputStyle(
                                    strings['date']!,
                                    Icons.event_outlined,
                                    required: true,
                                  ).copyWith(
                                    suffixIcon: TextButton(
                                      onPressed: _pickInvoiceDate,
                                      child: Text(strings['pick_date']!),
                                    ),
                                  ),
                            ),
                            if (_showsDueDateSection) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _paymentDueDateController,
                                readOnly: true,
                                onTap: _pickPaymentDueDate,
                                decoration:
                                    _inputStyle(
                                      strings['payment_due_date']!,
                                      Icons.schedule_outlined,
                                    ).copyWith(
                                      suffixIcon: TextButton(
                                        onPressed: _pickPaymentDueDate,
                                        child: Text(strings['pick_date']!),
                                      ),
                                    ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 20),
                        _buildSectionCard(
                          title: strings['items']!,
                          icon: Icons.list_alt_rounded,
                          children: [
                            _buildTextField(
                              _itemDescController,
                              strings['desc']!,
                              Icons.description_outlined,
                              required: true,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _itemQtyController,
                                    strings['qty']!,
                                    Icons.numbers_rounded,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    _itemPriceController,
                                    strings['price']!,
                                    Icons.sell_outlined,
                                    required: true,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _selectedPriceTaxMode,
                              decoration: _inputStyle(
                                strings['price_tax_mode']!,
                                Icons.percent_rounded,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'after_tax',
                                  child: Text(strings['price_after_tax']!),
                                ),
                                DropdownMenuItem(
                                  value: 'before_tax',
                                  child: Text(strings['price_before_tax']!),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedPriceTaxMode = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(strings['has_discount']!),
                              value: _hasDiscount,
                              onChanged: (value) {
                                setState(() {
                                  _hasDiscount = value;
                                  if (!value) {
                                    _discountController.clear();
                                  }
                                });
                              },
                            ),
                            if (_hasDiscount) ...[
                              const SizedBox(height: 8),
                              _buildTextField(
                                _discountController,
                                strings['discount_amount']!,
                                Icons.discount_outlined,
                                required: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _addItem,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(strings['add_item']!),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF1976D2,
                                  ).withValues(alpha: 0.1),
                                  foregroundColor: const Color(0xFF1976D2),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_showsPaymentMethodSection)
                          _buildSectionCard(
                            title: isRtl ? 'אמצעי תשלום' : 'Payment Method',
                            icon: Icons.payment,
                            children: [
                              ...List.generate(_paymentMethods.length, (index) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index == _paymentMethods.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: _buildPaymentMethodCard(
                                    index,
                                    _paymentMethods[index],
                                    isRtl,
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    for (final methodEntry in _paymentMethods) {
                                      methodEntry.isExpanded = false;
                                    }
                                    _paymentMethods.add(_PaymentMethodEntry());
                                  });
                                },
                                icon: const Icon(Icons.add),
                                label: Text(
                                  isRtl
                                      ? 'הוסף אמצעי תשלום'
                                      : 'Add Payment Method',
                                ),
                              ),
                            ],
                          ),
                        if (_items.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    item.description,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "${item.quantity} x ${item.price.toStringAsFixed(2)} ₪ (${item.isPriceBeforeTax ? strings['entered_price_before_tax']! : strings['entered_price_after_tax']!})",
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${_signedItemTotal(item).toStringAsFixed(2)} ₪",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1976D2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () => _removeItem(index),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        const SizedBox(height: 20),
                        _buildSectionCard(
                          title: strings['notes']!,
                          icon: Icons.note_add_outlined,
                          children: [
                            TextField(
                              controller: _notesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: strings['notes'],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        if (_items.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1976D2),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1976D2,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      strings['total']!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      "${_signedTotalAmount.toStringAsFixed(2)} ₪",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_discountAmount > 0) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        strings['discount']!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        "-${_discountAmount.toStringAsFixed(2)} ₪",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (_roundingAmount > 0) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        strings['rounding_amount']!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        "${_signedRoundingAmount.toStringAsFixed(2)} ₪",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  value: _roundTotalEnabled,
                                  onChanged: (value) {
                                    setState(() {
                                      _roundTotalEnabled = value;
                                    });
                                  },
                                  secondary: const Icon(
                                    Icons.currency_exchange_rounded,
                                    color: Colors.white,
                                  ),
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: Colors.white54,
                                  title: Text(
                                    strings['round_total']!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _openPreviewPage,
                                        icon: const Icon(Icons.print_rounded),
                                        label: Text(strings['generate']!),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.2),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF1976D2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard(
    int index,
    _PaymentMethodEntry entry,
    bool isRtl,
  ) {
    final parsedAmount = _parsePaymentAmount(entry.amountController.text);

    if (!entry.isExpanded) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _paymentMethodLabel(isRtl, entry.method),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (parsedAmount != null)
                    Text(
                      '${isRtl ? 'שולם: ' : 'Paid: '}${parsedAmount.toStringAsFixed(2)} ₪',
                      style: const TextStyle(color: Color(0xFF475569)),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() => entry.isExpanded = true);
              },
              icon: const Icon(Icons.expand_more),
              tooltip: isRtl ? 'פתח' : 'Expand',
            ),
            IconButton(
              onPressed: _paymentMethods.length == 1
                  ? null
                  : () {
                      setState(() {
                        final removed = _paymentMethods.removeAt(index);
                        removed.dispose();
                      });
                    },
              icon: const Icon(Icons.delete_outline),
              tooltip: isRtl ? 'הסר' : 'Remove',
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: entry.method,
                  decoration: _inputStyle(
                    isRtl ? 'אמצעי תשלום' : 'Payment Method',
                    Icons.payment,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'cash',
                      child: Text(isRtl ? 'מזומן' : 'Cash'),
                    ),
                    DropdownMenuItem(
                      value: 'credit',
                      child: Text(isRtl ? 'אשראי' : 'Credit Card'),
                    ),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text(isRtl ? 'העברה בנקאית' : 'Bank Transfer'),
                    ),
                    DropdownMenuItem(
                      value: 'check',
                      child: Text(isRtl ? 'צ׳ק' : 'Check'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => entry.method = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() => entry.isExpanded = false);
                },
                icon: const Icon(Icons.expand_less),
                tooltip: isRtl ? 'כווץ' : 'Collapse',
              ),
              IconButton(
                onPressed: _paymentMethods.length == 1
                    ? null
                    : () {
                        setState(() {
                          final removed = _paymentMethods.removeAt(index);
                          removed.dispose();
                        });
                      },
                icon: const Icon(Icons.delete_outline),
                tooltip: isRtl ? 'הסר' : 'Remove',
              ),
            ],
          ),
          if (entry.method == 'credit') ...[
            const SizedBox(height: 12),
            _buildTextField(
              entry.cardNumberController,
              isRtl ? 'מספר כרטיס (אופציונלי)' : 'Card Number (Optional)',
              Icons.credit_card,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.cardNameController,
              isRtl
                  ? 'שם הכרטיס (Visa, MasterCard וכו׳) - אופציונלי'
                  : 'Card Name (Visa, MasterCard, etc.) - Optional',
              Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: entry.creditDealType,
              decoration: _inputStyle(
                isRtl ? 'סוג העסקה' : 'Deal Type',
                Icons.receipt_long_outlined,
              ),
              items: [
                DropdownMenuItem(
                  value: 'regular',
                  child: Text(isRtl ? 'רגיל' : 'Regular'),
                ),
                DropdownMenuItem(
                  value: 'installments',
                  child: Text(isRtl ? 'תשלומים' : 'Installments'),
                ),
                DropdownMenuItem(
                  value: 'credit',
                  child: Text(isRtl ? 'קרדיט' : 'Credit'),
                ),
                DropdownMenuItem(
                  value: 'other',
                  child: Text(isRtl ? 'אחר' : 'Other'),
                ),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() => entry.creditDealType = val);
              },
            ),
            if (entry.creditDealType == 'installments') ...[
              const SizedBox(height: 12),
              _buildTextField(
                entry.installmentsController,
                isRtl ? 'מספר תשלומים (חובה)' : 'Installments Count (Required)',
                Icons.format_list_numbered,
                required: true,
                keyboardType: TextInputType.number,
              ),
            ],
          ],
          if (entry.method == 'check') ...[
            const SizedBox(height: 12),
            _buildTextField(
              entry.checkNumberController,
              isRtl ? 'מספר צ׳ק (חובה)' : 'Check Number (Required)',
              Icons.confirmation_number,
              required: true,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.checkBankController,
              isRtl ? 'בנק (אופציונלי)' : 'Bank (Optional)',
              Icons.account_balance,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.checkBranchController,
              isRtl ? 'סניף (אופציונלי)' : 'Branch (Optional)',
              Icons.store_mall_directory_outlined,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.checkAccountController,
              isRtl ? 'חשבון בנק (אופציונלי)' : 'Bank Account (Optional)',
              Icons.account_balance_wallet_outlined,
            ),
          ],
          if (entry.method == 'transfer') ...[
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferBankController,
              isRtl ? 'בנק (חובה)' : 'Bank Name (Required)',
              Icons.account_balance,
              required: true,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferBranchController,
              isRtl ? 'סניף (חובה)' : 'Branch (Required)',
              Icons.store_mall_directory_outlined,
              required: true,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferAccountController,
              isRtl ? 'מספר חשבון (חובה)' : 'Account Number (Required)',
              Icons.account_balance,
              required: true,
            ),
          ],
          const SizedBox(height: 12),
          _buildTextField(
            entry.amountController,
            isRtl ? 'סכום ששולם (חובה)' : 'Amount Paid (Required)',
            Icons.payments_outlined,
            required: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
              setState(() => entry.isExpanded = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: _inputStyle(label, icon, required: required),
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    if (!required) return Text(label);
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16, color: Color(0xFF0F172A)),
        children: [
          TextSpan(text: label),
          const TextSpan(
            text: ' *',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon, {
    bool required = false,
  }) {
    return InputDecoration(
      label: _buildFieldLabel(label, required: required),
      prefixIcon: Icon(icon, size: 20, color: const Color(0xFF64748B)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}

class InvoicePreviewPage extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final Future<Uint8List?> Function() onSave;
  final bool requireTaxAuthorityConnectionPrompt;
  final Future<bool> Function()? isTaxAuthorityConnected;
  final Future<void> Function()? onConnectTaxAuthority;
  final Future<void> Function()? onSendForSignature;

  const InvoicePreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.onSave,
    this.requireTaxAuthorityConnectionPrompt = false,
    this.isTaxAuthorityConnected,
    this.onConnectTaxAuthority,
    this.onSendForSignature,
  });

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  bool _isSaved = false;
  bool _isSaving = false;
  bool _isSendingForSignature = false;
  late Uint8List _pdfBytes;

  @override
  void initState() {
    super.initState();
    _pdfBytes = widget.pdfBytes;
    if (widget.requireTaxAuthorityConnectionPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTaxAuthorityConnectionPromptIfNeeded();
      });
    }
  }

  Future<void> _handleSendForSignature() async {
    if (_isSendingForSignature || widget.onSendForSignature == null) return;
    setState(() => _isSendingForSignature = true);
    try {
      await widget.onSendForSignature!.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlySaveError(e))));
      }
    } finally {
      if (mounted) setState(() => _isSendingForSignature = false);
    }
  }

  Future<bool> _showTaxAuthorityConnectionPromptIfNeeded({
    bool requiredForSave = false,
  }) async {
    if (!mounted) return false;
    final isConnected = await widget.isTaxAuthorityConnected?.call() ?? true;
    if (!mounted || isConnected) return true;

    final isRtl =
        Provider.of<LanguageProvider>(
              context,
              listen: false,
            ).locale.languageCode ==
            'he' ||
        Provider.of<LanguageProvider>(
              context,
              listen: false,
            ).locale.languageCode ==
            'ar';

    final shouldConnect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(
            isRtl ? 'חיבור לרשות המסים' : 'Connect to the Tax Authority',
          ),
          content: Text(
            requiredForSave
                ? (isRtl
                      ? 'אי אפשר לשמור את החשבונית לפני קבלת מספר הקצאה. השלם חיבור לרשות המסים ואז לחץ שמור שוב.'
                      : 'This invoice cannot be saved before receiving an allocation number. Complete the Tax Authority connection, then press Save again.')
                : (isRtl
                      ? 'הסכום לפני מע"מ מחייב מספר הקצאה מרשות המסים. כדי לקבל אותו יש להתחבר לרשות המסים.'
                      : 'This amount before VAT requires a Tax Authority allocation number. Connect to request it.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                requiredForSave
                    ? (isRtl ? 'ביטול' : 'Cancel')
                    : (isRtl ? 'להמשיך בלי חיבור' : 'Continue without it'),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isRtl ? 'התחבר לרשות המסים' : 'Connect'),
            ),
          ],
        ),
      ),
    );

    if (shouldConnect == true) {
      await widget.onConnectTaxAuthority?.call();
    }
    return false;
  }

  String _friendlySaveError(Object error) {
    final text = error.toString();
    const badStatePrefix = 'Bad state: ';
    if (text.startsWith(badStatePrefix)) {
      return text.substring(badStatePrefix.length);
    }
    return text;
  }

  Future<void> _handleSave() async {
    if (_isSaving || _isSaved) return;

    setState(() => _isSaving = true);
    try {
      if (widget.requireTaxAuthorityConnectionPrompt) {
        final connected = await widget.isTaxAuthorityConnected?.call() ?? true;
        if (!mounted) return;
        if (!connected) {
          await _showTaxAuthorityConnectionPromptIfNeeded(
            requiredForSave: true,
          );
          return;
        }
      }
      final savedPdfBytes = await widget.onSave();
      if (!mounted) return;
      setState(() {
        if (savedPdfBytes != null) {
          _pdfBytes = savedPdfBytes;
        }
        _isSaved = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlySaveError(e))));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isRtl ? 'תצוגה מקדימה לחשבונית' : 'Invoice Preview'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
        ),
        body: PdfPreview(
          canDebug: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          allowPrinting: false,
          allowSharing: false,
          useActions: false,
          initialPageFormat: pdf.PdfPageFormat.a4,
          build: (_) async => _pdfBytes,
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaved ? null : _handleSave,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(
                    _isSaved
                        ? (isRtl ? 'נשמר' : 'Saved')
                        : (_isSaving
                              ? (isRtl ? 'שומר...' : 'Saving...')
                              : (isRtl ? 'שמור' : 'Save')),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1976D2),
                    side: const BorderSide(color: Color(0xFF1976D2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_isSaved) ...[
                const SizedBox(height: 12),
                if (widget.onSendForSignature != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSendingForSignature
                          ? null
                          : _handleSendForSignature,
                      icon: _isSendingForSignature
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.draw_rounded),
                      label: Text(
                        _isSendingForSignature
                            ? (isRtl ? 'יוצר קישור...' : 'Creating link...')
                            : (isRtl ? 'שלח לחתימה' : 'Send it to be signed'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, 'send'),
                        icon: const Icon(Icons.send_rounded),
                        label: Text(isRtl ? 'שלח' : 'Send'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Printing.layoutPdf(
                            name: widget.fileName,
                            onLayout: (_) async => _pdfBytes,
                          );
                        },
                        icon: const Icon(Icons.print_rounded),
                        label: Text(isRtl ? 'הדפס' : 'Print'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Printing.sharePdf(
                            bytes: _pdfBytes,
                            filename: widget.fileName,
                          );
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: Text(isRtl ? 'שתף' : 'Share'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
