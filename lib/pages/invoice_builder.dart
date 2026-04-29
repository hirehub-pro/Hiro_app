import 'dart:developer' as dev;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:untitled1/services/subscription_access_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:untitled1/services/bkmv_export_service.dart';

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

  const InvoiceBuilderPage({
    super.key,
    required this.workerName,
    this.workerPhone,
    this.workerEmail,
    this.receiverId,
    this.receiverName,
    this.receiverPhone,
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
  });

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
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
      case 'receipt':
        return [
          {'bucket': 'receipts', 'type': 'D120'},
        ];
      case 'credit_note':
        return [
          {'bucket': 'credit_notes', 'type': 'C300'},
        ];
      case 'invoice_receipt':
        return [
          {'bucket': 'invoices', 'type': 'C100'},
          {'bucket': 'receipts', 'type': 'D120'},
        ];
      case 'invoice':
      default:
        return [
          {'bucket': 'invoices', 'type': 'C100'},
        ];
    }
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
  Future<void> _createInvoiceAndLog({required Uint8List pdfBytes}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userId = user.uid;
    final now = DateTime.now();
    final dateStr = intl.DateFormat('yyyyMMdd').format(now);
    final timestamp = FieldValue.serverTimestamp();
    final customerId = _clientNameController.text.isNotEmpty
        ? _clientNameController.text
        : null;
    final docType = _selectedDocType;
    final creditNoteLegalData = _creditNoteLegalData;
    final signedTotalAmount = docType == 'credit_note'
        ? -_totalAmount
        : _totalAmount;
    final calculatedVat = _usesVat
        ? (_totalAmount - (_totalAmount / (1 + _vatRate)))
        : 0.0;
    final vatAmount = docType == 'credit_note' ? -calculatedVat : calculatedVat;
    final logTargets = _logTargetsForDocType(docType);

    final userDoc = FirebaseFirestore.instance.collection('users').doc(userId);
    final counterRef = userDoc.collection('counters').doc('invoice');
    final invoicesRef = userDoc.collection('invoices');
    final savedInvoicesRef = userDoc.collection('saved_invoices');
    final invoiceTotalsRef = FirebaseFirestore.instance
        .collection('metadata')
        .doc('invoice_counts');
    final logEntries = logTargets.map((target) {
      final logBucketRef = FirebaseFirestore.instance
          .collection('logs')
          .doc(target['bucket']!);
      return {
        'bucket': target['bucket']!,
        'type': target['type']!,
        'bucketRef': logBucketRef,
        'fileRef': logBucketRef.collection('files').doc(),
      };
    }).toList();

    late int nextNumber;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // Get and increment counter
      final counterSnap = await transaction.get(counterRef);
      final logCounterSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final entry in logEntries) {
        final logBucketRef =
            entry['bucketRef']! as DocumentReference<Map<String, dynamic>>;
        logCounterSnaps.add(await transaction.get(logBucketRef));
      }

      nextNumber = 1;
      if (counterSnap.exists) {
        final data = counterSnap.data() as Map<String, dynamic>;
        nextNumber = (data['value'] as int? ?? 0) + 1;
      }
      transaction.set(counterRef, {'value': nextNumber});

      // Prepare invoice data
      final invoiceData = {
        'type': docType,
        'amount': signedTotalAmount,
        'vatAmount': vatAmount,
        'clientName': _clientNameController.text,
        'clientAddress': _clientAddressController.text,
        'clientPhone': _clientPhoneController.text,
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
        'discountAmount': _discountAmount,
        'notes': _notesController.text,
        'paymentMethod': _paymentMethods.isNotEmpty
            ? _paymentMethods.first.method
            : 'cash',
        'paymentMethods': _paymentMethods
            .map((entry) => entry.toMap())
            .toList(),
        'paymentAmountTotal': _paymentMethodsAmountTotal(),
        'invoiceNumber': nextNumber,
        'date': dateStr,
        'createdAt': timestamp,
        if (creditNoteLegalData != null) 'creditNoteLegal': creditNoteLegalData,
      };

      // Save invoice (metadata only, PDF upload is outside transaction)
      final invoiceDoc = invoicesRef.doc(nextNumber.toString());
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
          'type': entry['type'],
          'counter': logCounter,
          'documentNumber': nextNumber,
          'date': dateStr,
          'amount': signedTotalAmount,
          'vatAmount': vatAmount,
          'customerId': customerId,
          'clientName': _clientNameController.text,
          'fileName': '',
          'storagePath': '',
          'url': '',
          'timestamp': timestamp,
          if (creditNoteLegalData != null)
            'creditNoteLegal': creditNoteLegalData,
        };
        transaction.set(logFileRef, logData);
      }
    });

    // Upload PDF to Storage (after transaction)
    final fileName =
        'invoice_${userId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final storagePath = 'invoices/$userId/$fileName';
    final ref = firebase_storage.FirebaseStorage.instance.ref().child(
      storagePath,
    );
    await ref.putData(pdfBytes);
    final downloadUrl = await ref.getDownloadURL();

    // Update invoice doc with PDF URL
    final counterSnap = await userDoc
        .collection('counters')
        .doc('invoice')
        .get();
    final savedNumber = (counterSnap.data()?['value'] as int?) ?? 1;
    await invoicesRef.doc(savedNumber.toString()).update({
      'fileName': fileName,
      'url': downloadUrl,
    });
    final clientName = _clientNameController.text.trim();
    final savedInvoiceName = clientName.isNotEmpty
        ? '${_labelForDocType(docType)} #$savedNumber - $clientName'
        : '${_labelForDocType(docType)} #$savedNumber';
    await savedInvoicesRef.add({
      'name': savedInvoiceName,
      'fileName': fileName,
      'url': downloadUrl,
      'storagePath': storagePath,
      'amount': signedTotalAmount,
      'invoiceNumber': savedNumber,
      'docType': docType,
      'clientName': clientName,
      'date': dateStr,
      'createdAt': FieldValue.serverTimestamp(),
      if (creditNoteLegalData != null) 'creditNoteLegal': creditNoteLegalData,
    });
    await _addToTotalEarned(userId: userId, amount: signedTotalAmount);
    await Future.wait(
      logEntries.map((entry) async {
        final logFileRef =
            entry['fileRef']! as DocumentReference<Map<String, dynamic>>;
        await logFileRef.update({
          'fileName': fileName,
          'storagePath': storagePath,
          'url': downloadUrl,
        });
      }),
    );
  }

  String _labelForDocType(String docType) {
    switch (docType) {
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
  final _invoiceCounterController = TextEditingController(text: "1");
  final _itemDescController = TextEditingController();
  final _itemQtyController = TextEditingController(text: "1");
  final _itemPriceController = TextEditingController();
  final _discountController = TextEditingController();
  final _notesController = TextEditingController();
  final _creditReasonController = TextEditingController();
  final _creditOriginalInvoiceNumberController = TextEditingController();
  final _creditOriginalInvoiceDateController = TextEditingController();
  final _creditReceiptConfirmationController = TextEditingController();

  // Payment method state
  final List<_PaymentMethodEntry> _paymentMethods = [_PaymentMethodEntry()];
  String _selectedCreditDeliveryMethod = 'email_confirmation';

  final List<InvoiceItem> _items = [];
  bool _isPreparing = false;
  String _invoiceNumber = "";
  static const double _vatRate = 0.17;
  String _selectedPriceTaxMode = 'after_tax';
  bool _hasDiscount = false;

  bool get _isCreditNote => _selectedDocType == 'credit_note';
  bool get _usesVat =>
      _dealerType == 'licensed' && _selectedDocType != 'receipt';

  double _unitPriceAfterTax(InvoiceItem item) {
    if (!_usesVat) return item.price;
    return item.isPriceBeforeTax ? item.price * (1 + _vatRate) : item.price;
  }

  double _itemTotalAfterTax(InvoiceItem item) =>
      _unitPriceAfterTax(item) * item.quantity;

  double get _itemsTotalBeforeDiscount =>
      _items.fold<double>(0, (sum, item) => sum + _itemTotalAfterTax(item));

  double get _discountAmount {
    if (!_hasDiscount) return 0.0;
    final parsed = double.tryParse(
      _discountController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0) return 0.0;
    final maxDiscount = _itemsTotalBeforeDiscount;
    return parsed > maxDiscount ? maxDiscount : parsed;
  }

  double get _totalAmount {
    final total = _itemsTotalBeforeDiscount - _discountAmount;
    return total < 0 ? 0 : total;
  }

  double get _signedTotalAmount => _isCreditNote ? -_totalAmount : _totalAmount;

  double get _signedSubtotalAmount {
    final subtotal = _usesVat ? (_totalAmount / (1 + _vatRate)) : _totalAmount;
    return _isCreditNote ? -subtotal : subtotal;
  }

  double get _signedVatAmount {
    final vat = _usesVat
        ? (_totalAmount - (_totalAmount / (1 + _vatRate)))
        : 0.0;
    return _isCreditNote ? -vat : vat;
  }

  double _signedItemTotal(InvoiceItem item) =>
      _isCreditNote ? -_itemTotalAfterTax(item) : _itemTotalAfterTax(item);

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
  String? _businessId;
  String? _businessAddress;
  bool _isBusinessVerified = false;
  String _selectedDocType = 'receipt';

  pw.Font? _cachedFont;
  pw.Font? _cachedFontBold;
  pw.MemoryImage? _cachedLogo;
  Map<String, String>? _cachedStrings;
  String? _lastLocale;
  late final Future<SubscriptionAccessState> _accessFuture;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _invoiceCounterSubscription;

  @override
  void initState() {
    super.initState();
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
    // Temporary invoice number until worker info is fetched
    _invoiceNumber = "${intl.DateFormat('yyyy').format(DateTime.now())}-0000";

    // Auto-fill from widget parameters
    if (widget.receiverName != null) {
      _clientNameController.text = widget.receiverName!;
    }
    if (widget.receiverPhone != null) {
      _clientPhoneController.text = widget.receiverPhone!;
    }
    if (widget.receiverAddress != null) {
      _clientAddressController.text = widget.receiverAddress!;
    }

    _applyInitialTemplate();
    _bindInvoiceCounterLiveSync();
    _fetchWorkerInfo();
    _loadAssets();
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

  void _bindInvoiceCounterLiveSync() {
    final ref = _verificationInfoLatestRef();
    if (ref == null) return;

    _invoiceCounterSubscription?.cancel();
    _invoiceCounterSubscription = ref.snapshots().listen((snapshot) {
      final data = snapshot.data();
      final counter = (data?['invoiceCounter'] as num?)?.toInt() ?? 1;
      final safeCounter = counter < 1 ? 1 : counter;
      final counterText = safeCounter.toString();

      if (!mounted) return;

      final currentCounterText = _invoiceCounterController.text;
      final nextInvoiceNumber =
          "${intl.DateFormat('yyyy').format(DateTime.now())}-${safeCounter.toString().padLeft(4, '0')}";

      if (currentCounterText != counterText ||
          _invoiceNumber != nextInvoiceNumber) {
        setState(() {
          _invoiceCounterController.text = counterText;
          _invoiceCounterController.selection = TextSelection.fromPosition(
            TextPosition(offset: _invoiceCounterController.text.length),
          );
          _invoiceNumber = nextInvoiceNumber;
        });
      }
    });
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
            _dealerType = workerData?['dealertype'] ?? 'exempt';
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
            setState(() {
              _businessId = vData?['businessId'];
              _businessAddress = vData?['address'];

              // Sequential Invoice Counter logic
              int counter = vData?['invoiceCounter'] ?? 1;
              _invoiceCounterController.text = counter.toString();
              _invoiceNumber =
                  "${intl.DateFormat('yyyy').format(DateTime.now())}-${counter.toString().padLeft(4, '0')}";

              if (widget.initialDocType == null ||
                  widget.initialDocType!.isEmpty) {
                if (_isBusinessVerified && _dealerType == 'licensed') {
                  _selectedDocType = 'invoice_receipt';
                } else {
                  _selectedDocType = 'receipt';
                }
              }
            });
          }
        }
      } catch (e) {
        dev.log("Error fetching worker info: $e");
      }
    }
  }

  Future<void> _incrementInvoiceCounter() async {
    final currentCounter = int.tryParse(_invoiceCounterController.text) ?? 1;
    final nextCounter = (currentCounter < 1 ? 1 : currentCounter) + 1;
    await _persistInvoiceCounter(nextCounter);
  }

  DocumentReference<Map<String, dynamic>>? _verificationInfoLatestRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('verification_info')
        .doc('latest');
  }

  Future<void> _persistInvoiceCounter(int counter) async {
    final ref = _verificationInfoLatestRef();
    if (ref == null) return;

    final safeCounter = counter < 1 ? 1 : counter;
    try {
      await ref.set({'invoiceCounter': safeCounter}, SetOptions(merge: true));
    } catch (e) {
      dev.log("Error updating invoiceCounter: $e");
    }
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientAddressController.dispose();
    _clientPhoneController.dispose();
    _invoiceCounterController.dispose();
    _invoiceCounterSubscription?.cancel();
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

      try {
        final logoData = await rootBundle.load("assets/icon/app_icon.png");
        _cachedLogo = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (e) {
        dev.log("Logo load failed: $e");
      }
    } catch (e) {
      dev.log("Font load failed: $e");
    }
  }

  Map<String, String> _getLocalizedStrings(
    BuildContext context, {
    bool listen = true,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;

    if (_cachedStrings != null && _lastLocale == locale) {
      return _cachedStrings!;
    }

    _lastLocale = locale;
    switch (locale) {
      case 'he':
        _cachedStrings = {
          'title': 'מפיק מסמכים עסקיים',
          'client_info': 'פרטי הלקוח:',
          'client_name': 'שם הלקוח',
          'client_address': 'כתובת הלקוח',
          'client_phone': 'טלפון הלקוח',
          'client_details_required':
              'יש למלא את כל פרטי הלקוח: שם, טלפון וכתובת.',
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
          'entered_price_before_tax': 'לפני מע"מ',
          'entered_price_after_tax': 'כולל מע"מ',
          'add_item': 'הוסף פריט',
          'total': 'סה"כ לתשלום',
          'generate': 'תצוגה מקדימה / הדפסה',
          'empty_items': 'נא להוסיף לפחות פריט אחד',
          'worker': 'פרטי העסק:',
          'date': 'תאריך:',
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
          'receipt': 'קבלה',
          'invoice': 'חשבונית מס',
          'invoice_receipt': 'חשבונית מס / קבלה',
          'credit_note': 'הודעת זיכוי',
          'licensed_only': 'זמין לעוסק מורשה מאומת בלבד',
          'vat_id': 'ח.פ / ע.מ:',
          'vat': 'מע"מ (17%):',
          'original': 'מקור',
          'business_name': 'שם העסק:',
          'tax_invoice_num': 'חשבונית מס מס\':',
          'licensed_dealer': 'עוסק מורשה',
          'exempt_dealer': 'עוסק פטור',
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
        };
        break;
      default:
        _cachedStrings = {
          'title': 'Business Document Builder',
          'client_info': 'Client Details:',
          'client_name': 'Client Name',
          'client_address': 'Client Address',
          'client_phone': 'Client Phone',
          'client_details_required':
              'Please fill all client details: name, phone, and address.',
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
          'entered_price_before_tax': 'Before Tax',
          'entered_price_after_tax': 'After Tax',
          'add_item': 'Add Item',
          'total': 'Grand Total',
          'generate': 'Preview / Print PDF',
          'empty_items': 'Please add at least one item',
          'worker': 'Business Details:',
          'date': 'Date:',
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
          'receipt': 'Receipt',
          'invoice': 'Tax Invoice',
          'invoice_receipt': 'Tax Invoice / Receipt',
          'credit_note': 'Credit Note',
          'licensed_only': 'Verified Licensed Dealers only',
          'vat_id': 'VAT ID / Tax ID:',
          'vat': 'VAT (17%):',
          'original': 'Original',
          'business_name': 'Business Name:',
          'tax_invoice_num': 'Tax Invoice No:',
          'licensed_dealer': 'Licensed Dealer',
          'exempt_dealer': 'Exempt Dealer',
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
        };
    }
    return _cachedStrings!;
  }

  Map<String, String> _withRequiredDefaults(Map<String, String> source) {
    const defaults = {
      'title': 'Business Document Builder',
      'preparing': 'Preparing document...',
      'doc_type': 'Document Type',
      'receipt': 'Receipt',
      'invoice': 'Tax Invoice',
      'invoice_receipt': 'Tax Invoice / Receipt',
      'licensed_only': 'Verified Licensed Dealers only',
      'invoice_counter': 'Invoice Counter',
      'client_info': 'Client Details:',
      'client_name': 'Client Name',
      'client_phone': 'Client Phone',
      'client_address': 'Client Address',
      'client_details_required':
          'Please fill all client details: name, phone, and address.',
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
      'inv_no': 'Document No:',
      'tax_invoice_num': 'Tax Invoice No:',
      'original': 'Original',
      'business_address': 'Business Address:',
      'subtotal': 'Subtotal (Excl. VAT)',
      'vat': 'VAT (17%):',
      'legal_disclaimer':
          'Generated via hiro. This is a computerized document authorized by the Israel Tax Authority. Original.',
      'licensed_dealer': 'Licensed Dealer',
      'exempt_dealer': 'Exempt Dealer',
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
    };

    return {...defaults, ...source};
  }

  void _addItem() {
    if (_itemDescController.text.isEmpty || _itemPriceController.text.isEmpty)
      return;
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

  Future<void> _syncInvoiceNumberFromCounter() async {
    final counter = int.tryParse(_invoiceCounterController.text) ?? 1;
    final safeCounter = counter < 1 ? 1 : counter;
    final year = intl.DateFormat('yyyy').format(DateTime.now());
    setState(() {
      _invoiceCounterController.text = safeCounter.toString();
      _invoiceNumber = '$year-${safeCounter.toString().padLeft(4, '0')}';
    });
    await _persistInvoiceCounter(safeCounter);
  }

  Future<Uint8List?> _getGeneratedPdfBytes() async {
    if (_items.isEmpty) return null;

    try {
      if (_cachedFont == null) await _loadAssets();
      return await _generatePdf(
        pdf.PdfPageFormat.a4,
        _cachedFont!,
        _cachedFontBold!,
        _cachedLogo,
      );
    } catch (e) {
      dev.log("Error generating PDF: $e");
      return null;
    }
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
    final strings = _getLocalizedStrings(context, listen: false);
    final missingClientDetails =
        _clientNameController.text.trim().isEmpty ||
        _clientPhoneController.text.trim().isEmpty ||
        _clientAddressController.text.trim().isEmpty;

    if (!missingClientDetails) return true;

    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final fallback = (locale == 'he' || locale == 'ar')
        ? 'יש למלא את כל פרטי הלקוח: שם, טלפון וכתובת.'
        : 'Please fill all client details: name, phone, and address.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings['client_details_required'] ?? fallback)),
    );
    return false;
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

    setState(() => _isPreparing = true);

    try {
      final pdfBytes = await _getGeneratedPdfBytes();
      if (pdfBytes == null) {
        if (mounted) setState(() => _isPreparing = false);
        return;
      }

      if (!mounted) return;
      setState(() => _isPreparing = false);

      final action = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewPage(
            pdfBytes: pdfBytes,
            fileName: '$_invoiceNumber.pdf',
            onSave: () async {
              await _createInvoiceAndLog(pdfBytes: pdfBytes);
            },
          ),
        ),
      );

      if (action == 'send' && mounted) {
        if (widget.receiverId != null) {
          await _sendToContact(
            widget.receiverId!,
            widget.receiverName ?? "User",
          );
        } else {
          await _showContactPickerAndSend();
        }
      }
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

    try {
      // Prevent duplicate save/increment for the same issued invoice number.
      final existingByInvoice = await userInvoicesRef
          .where('invoiceNumber', isEqualTo: _invoiceNumber)
          .limit(1)
          .get();
      if (existingByInvoice.docs.isNotEmpty) {
        final existingData = existingByInvoice.docs.first.data();
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
          fileName: (existingData['fileName'] ?? '$_invoiceNumber.pdf')
              .toString(),
          wasCreated: false,
        );
      }

      final datePart = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
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

      await userInvoicesRef.add({
        'name': finalName,
        'baseName': baseName,
        'receiverName': receiverName,
        'fileName': '$finalName.pdf',
        'storagePath': storagePath,
        'url': downloadUrl,
        'amount': _signedTotalAmount,
        'paymentMethod': _paymentMethods.isNotEmpty
            ? _paymentMethods.first.method
            : 'cash',
        'paymentMethods': _paymentMethods
            .map((entry) => entry.toMap())
            .toList(),
        'paymentAmountTotal': _paymentMethodsAmountTotal(),
        'priceTaxModeDefault': _selectedPriceTaxMode,
        'hasDiscount': _hasDiscount,
        'discountAmount': _discountAmount,
        'invoiceNumber': _invoiceNumber,
        'createdAt': FieldValue.serverTimestamp(),
        if (_creditNoteLegalData != null)
          'creditNoteLegal': _creditNoteLegalData,
      });
      await _addToTotalEarned(
        userId: currentUser.uid,
        amount: _signedTotalAmount,
      );

      await _incrementInvoiceCounter();

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
        .collection('saved_invoices')
        .doc('TotalEarned');

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

  Future<void> _showContactPickerAndSend() async {
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
      _sendToContact(widget.receiverId!, widget.receiverName ?? "User");
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
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final rooms = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final List users = data['users'] ?? [];
                      return !users.contains('hiro_manager');
                    }).toList();

                    if (rooms.isEmpty)
                      return Center(child: Text(strings['no_contacts']!));

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
                            _sendToContact(otherId, otherName);
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

  Future<void> _sendToContact(String receiverId, String receiverName) async {
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

    setState(() => _isPreparing = true);
    final pdfBytes = await _getGeneratedPdfBytes();

    if (pdfBytes == null) {
      if (mounted) setState(() => _isPreparing = false);
      return;
    }

    try {
      final saved = await _saveInvoicePdf(
        pdfBytes,
        receiverNameOverride: receiverName,
        showFeedback: false,
      );
      if (saved == null || saved.url.isEmpty) {
        if (mounted) setState(() => _isPreparing = false);
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final ids = [currentUser.uid, receiverId]..sort();
      final roomId = ids.join('_');

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'senderId': currentUser.uid,
            'receiverId': receiverId,
            'message': 'Sent a document: $_invoiceNumber',
            'text': 'Sent a document: $_invoiceNumber',
            'type': 'file',
            'url': saved.url,
            'fileUrl': saved.url,
            'fileName': saved.fileName,
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
          });

      await FirebaseFirestore.instance.collection('chat_rooms').doc(roomId).set(
        {
          'lastMessage': 'Sent a document: $_invoiceNumber',
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
    } catch (e) {
      if (mounted) setState(() => _isPreparing = false);
      dev.log("Error sending PDF: $e");
    }
  }

  Future<Uint8List> _generatePdf(
    pdf.PdfPageFormat format,
    pw.Font font,
    pw.Font fontBold,
    pw.MemoryImage? logo,
  ) async {
    final doc = pw.Document();
    final strings = _getLocalizedStrings(context, listen: false);

    doc.addPage(
      pw.Page(
        pageFormat: format.copyWith(
          marginTop: 1.5 * pdf.PdfPageFormat.cm,
          marginBottom: 1.5 * pdf.PdfPageFormat.cm,
          marginLeft: 1.5 * pdf.PdfPageFormat.cm,
          marginRight: 1.5 * pdf.PdfPageFormat.cm,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          // Fix: determine isRtl for PDF context
          final locale = Provider.of<LanguageProvider>(
            this.context,
            listen: false,
          ).locale.languageCode;
          final isRtl = locale == 'he' || locale == 'ar';
          final isInvoice =
              _selectedDocType == 'invoice' ||
              _selectedDocType == 'invoice_receipt';
          final docTitle = _selectedDocType == 'receipt'
              ? strings['receipt']!
              : _selectedDocType == 'invoice'
              ? strings['invoice']!
              : _selectedDocType == 'invoice_receipt'
              ? strings['invoice_receipt']!
              : _selectedDocType == 'credit_note'
              ? strings['credit_note']!
              : strings['doc_type']!;
          final creditNoteLegalData = _creditNoteLegalData;

          return pw.Stack(
            children: [
              // Watermark
              pw.Positioned(
                left: 0,
                right: 0,
                top: 200,
                child: pw.Opacity(
                  opacity: 0.08,
                  child: pw.Center(
                    child: pw.Text(
                      'hiro',
                      style: pw.TextStyle(
                        fontSize: 120,
                        fontWeight: pw.FontWeight.bold,
                        color: pdf.PdfColors.blue,
                      ),
                    ),
                  ),
                ),
              ),
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Header
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
                              margin: const pw.EdgeInsets.only(left: 12),
                              child: pw.Image(logo, width: 70, height: 70),
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
                                pw.Text(
                                  isInvoice
                                      ? "${strings['tax_invoice_num']} $_invoiceNumber"
                                      : "${strings['inv_no']} $_invoiceNumber",
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 14,
                                    color: pdf.PdfColors.blueGrey800,
                                  ),
                                ),
                                pw.Text(
                                  "${strings['date']} ${intl.DateFormat('dd/MM/yyyy').format(DateTime.now())}",
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
                                  strings['worker']!,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 13,
                                    color: pdf.PdfColors.blue900,
                                  ),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                  widget.workerName,
                                  style: pw.TextStyle(
                                    fontSize: 15,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (_businessId != null &&
                                    _businessId!.isNotEmpty) ...[
                                  pw.Text(
                                    "${strings['authorized_dealer_label']} $_businessId",
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  pw.Text(
                                    "${strings['vat_id']} $_businessId",
                                    style: pw.TextStyle(fontSize: 11),
                                  ),
                                  pw.Text(
                                    _dealerType == 'licensed'
                                        ? strings['licensed_dealer']!
                                        : strings['exempt_dealer']!,
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      color: pdf.PdfColors.blueGrey800,
                                    ),
                                  ),
                                ],
                                if (_businessAddress != null &&
                                    _businessAddress!.isNotEmpty)
                                  pw.Text(
                                    "${strings['business_address']} $_businessAddress",
                                    style: pw.TextStyle(fontSize: 11),
                                  ),
                                if (widget.workerPhone != null)
                                  pw.Text(
                                    widget.workerPhone!,
                                    style: pw.TextStyle(fontSize: 11),
                                  ),
                                if (widget.workerEmail != null)
                                  pw.Text(
                                    widget.workerEmail!,
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
                                  strings['client_info']!,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 13,
                                    color: pdf.PdfColors.blue900,
                                  ),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                  _clientNameController.text,
                                  style: pw.TextStyle(
                                    fontSize: 15,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (_clientPhoneController.text.isNotEmpty)
                                  pw.Text(
                                    _clientPhoneController.text,
                                    style: pw.TextStyle(fontSize: 11),
                                  ),
                                if (_clientAddressController.text.isNotEmpty)
                                  pw.Text(
                                    _clientAddressController.text,
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
                                _dealerType == 'licensed') ...[
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
                                    strings['vat']!,
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
                            pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
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
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 24),
                    // Payment Method (אמצעי תשלום)
                    pw.Text(
                      strings['payment_method'] ??
                          (isRtl ? 'אמצעי תשלום' : 'Payment Method'),
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
                        _paymentMethodsSummaryText(isRtl),
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ),
                    pw.SizedBox(height: 16),
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
                    pw.Spacer(),
                    // Thank you & signature
                    pw.Divider(thickness: 1, color: pdf.PdfColors.blueGrey800),
                    pw.SizedBox(height: 8),
                    pw.Center(
                      child: pw.Text(
                        strings['legal_disclaimer']!,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: pdf.PdfColors.blueGrey800,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Center(
                      child: pw.Text(
                        'Thank you for your business!',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: pdf.PdfColors.blue,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 18),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Signature: ______________________',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: pdf.PdfColors.blueGrey800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
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
                              isExpanded: true,
                              value: _selectedDocType,
                              decoration: _inputStyle(
                                strings['doc_type']!,
                                Icons.description_outlined,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'receipt',
                                  child: Text(strings['receipt']!),
                                ),
                                DropdownMenuItem(
                                  value: 'invoice',
                                  enabled:
                                      _dealerType == 'licensed' &&
                                      _isBusinessVerified,
                                  child: Text(
                                    strings['invoice']! +
                                        ((_dealerType != 'licensed' ||
                                                !_isBusinessVerified)
                                            ? " (${strings['licensed_only']})"
                                            : ""),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          (_dealerType == 'licensed' &&
                                              _isBusinessVerified)
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'invoice_receipt',
                                  enabled:
                                      _dealerType == 'licensed' &&
                                      _isBusinessVerified,
                                  child: Text(
                                    strings['invoice_receipt']! +
                                        ((_dealerType != 'licensed' ||
                                                !_isBusinessVerified)
                                            ? " (${strings['licensed_only']})"
                                            : ""),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          (_dealerType == 'licensed' &&
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
                              onChanged: (val) {
                                if (val != null)
                                  setState(() => _selectedDocType = val);
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
                        if (_isCreditNote) ...[
                          _buildSectionCard(
                            title: strings['credit_note_legal']!,
                            icon: Icons.gavel_rounded,
                            children: [
                              _buildTextField(
                                _creditOriginalInvoiceNumberController,
                                strings['original_invoice_number']!,
                                Icons.receipt_long_outlined,
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
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedCreditDeliveryMethod,
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
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                        // Payment Method Section
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
                        const SizedBox(height: 20),
                        _buildSectionCard(
                          title: strings['client_info']!,
                          icon: Icons.person_add_alt_1_rounded,
                          children: [
                            _buildTextField(
                              _clientNameController,
                              strings['client_name']!,
                              Icons.person_outline,
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
                              _clientAddressController,
                              strings['client_address']!,
                              Icons.location_on_outlined,
                            ),
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
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferBranchController,
              isRtl ? 'סניף (חובה)' : 'Branch (Required)',
              Icons.store_mall_directory_outlined,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferAccountController,
              isRtl ? 'מספר חשבון (חובה)' : 'Account Number (Required)',
              Icons.account_balance,
            ),
          ],
          const SizedBox(height: 12),
          _buildTextField(
            entry.amountController,
            isRtl ? 'סכום ששולם (חובה)' : 'Amount Paid (Required)',
            Icons.payments_outlined,
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
    TextInputType keyboardType = TextInputType.text,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: _inputStyle(label, icon),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
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
  final Future<void> Function() onSave;

  const InvoicePreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.onSave,
  });

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  bool _isSaved = false;
  bool _isSaving = false;

  Future<void> _handleSave() async {
    if (_isSaving || _isSaved) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSave();
      if (!mounted) return;
      setState(() => _isSaved = true);
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
          build: (_) async => widget.pdfBytes,
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
                            onLayout: (_) async => widget.pdfBytes,
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
                            bytes: widget.pdfBytes,
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
