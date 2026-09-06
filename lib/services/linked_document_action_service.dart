import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/pages/saved_invoices_page.dart';
import 'package:untitled1/services/profile_document_service.dart';

enum _LinkedDocumentAction {
  open,
  receipt,
  creditNote,
  cancelReceipt,
  workOrder,
  transactionAccount,
  invoice,
  invoiceReceipt,
}

class LinkedDocumentActionService {
  const LinkedDocumentActionService._();

  static Future<void> show({
    required BuildContext context,
    required String userId,
    required String documentId,
    required Map<String, dynamic> documentData,
    required String locale,
  }) async {
    final strings = _ActionStrings(locale);
    final type = (documentData['docType'] ?? documentData['type'] ?? '')
        .toString()
        .trim();
    final finalized = _isFinalized(documentData);
    final cancelled = _isCancelled(documentData);
    final locked = cancelled || documentData['isLinkingLocked'] == true;
    final canCreateTaxDocuments = await _canCreateTaxDocuments(userId);
    if (!context.mounted) return;

    final actions = <_LinkedDocumentAction>[_LinkedDocumentAction.open];
    if (finalized && !locked) {
      switch (type) {
        case 'invoice':
          if (_remainingAmount(documentData) > 0.01) {
            actions.add(_LinkedDocumentAction.receipt);
          }
          actions.add(_LinkedDocumentAction.creditNote);
        case 'invoice_receipt':
          actions.add(_LinkedDocumentAction.creditNote);
        case 'receipt':
          if (documentData['isCancellationDocument'] != true) {
            actions.add(_LinkedDocumentAction.cancelReceipt);
          }
        case 'transaction_account':
          if (_remainingAmount(documentData) > 0.01) {
            actions.add(_LinkedDocumentAction.receipt);
          }
          if (canCreateTaxDocuments) {
            actions
              ..add(_LinkedDocumentAction.invoice)
              ..add(_LinkedDocumentAction.invoiceReceipt);
          }
        case 'work_order':
          actions.add(_LinkedDocumentAction.transactionAccount);
          if (canCreateTaxDocuments) {
            actions
              ..add(_LinkedDocumentAction.invoice)
              ..add(_LinkedDocumentAction.invoiceReceipt);
          }
        case 'quote':
          actions.add(_LinkedDocumentAction.workOrder);
          if (canCreateTaxDocuments) {
            actions
              ..add(_LinkedDocumentAction.invoice)
              ..add(_LinkedDocumentAction.invoiceReceipt);
          }
      }
    }

    final selected = await showModalBottomSheet<_LinkedDocumentAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.actions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _documentTitle(documentData, strings),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (type == 'invoice' || type == 'transaction_account') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: Color(0xFF1976D2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(strings.remaining)),
                        Text(
                          '${_remainingAmount(documentData).toStringAsFixed(2)} ₪',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final action in actions)
                          _ActionTile(
                            action: action,
                            strings: strings,
                            onTap: () => Navigator.pop(sheetContext, action),
                          ),
                        if (actions.length == 1 && locked)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                            child: Text(
                              cancelled
                                  ? strings.cancelledLocked
                                  : strings.creationLocked,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
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
    );
    if (selected == null || !context.mounted) return;

    await _execute(
      context: context,
      action: selected,
      userId: userId,
      documentId: documentId,
      fallbackData: documentData,
      strings: strings,
    );
  }

  static Future<void> _execute({
    required BuildContext context,
    required _LinkedDocumentAction action,
    required String userId,
    required String documentId,
    required Map<String, dynamic> fallbackData,
    required _ActionStrings strings,
  }) async {
    if (action == _LinkedDocumentAction.open) {
      await _openPreview(context, userId, documentId, fallbackData, strings);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('invoices')
          .doc(documentId)
          .get();
      final data = snapshot.data() ?? fallbackData;
      final profile = await ProfileDocumentService.load(userId);
      if (!context.mounted) return;

      switch (action) {
        case _LinkedDocumentAction.receipt:
          await _openReceipt(context, user, documentId, data, profile, strings);
        case _LinkedDocumentAction.creditNote:
          await _openCreditNote(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
          );
        case _LinkedDocumentAction.cancelReceipt:
          await _openCancellingReceipt(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
          );
        case _LinkedDocumentAction.workOrder:
          await _openDerivedDocument(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
            'work_order',
          );
        case _LinkedDocumentAction.transactionAccount:
          await _openDerivedDocument(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
            'transaction_account',
          );
        case _LinkedDocumentAction.invoice:
          await _openDerivedDocument(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
            'invoice',
          );
        case _LinkedDocumentAction.invoiceReceipt:
          await _openDerivedDocument(
            context,
            user,
            documentId,
            data,
            profile,
            strings,
            'invoice_receipt',
          );
        case _LinkedDocumentAction.open:
          break;
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.actionFailed)));
    }
  }

  static Future<void> _openReceipt(
    BuildContext context,
    User user,
    String documentId,
    Map<String, dynamic> data,
    Map<String, dynamic> profile,
    _ActionStrings strings,
  ) async {
    final remaining = _remainingAmount(data);
    if (remaining <= 0.01) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noRemainingBalance)));
      return;
    }
    final amount = await _askReceiptAmount(context, remaining, strings);
    if (amount == null || !context.mounted) return;
    final number = _documentNumber(data);
    final launch = _LaunchData(user, profile, data);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderPage(
          workerName: launch.workerName,
          workerPhone: launch.workerPhone,
          workerEmail: launch.workerEmail,
          receiverName: launch.clientName,
          receiverPhone: launch.clientPhone,
          receiverEmail: launch.clientEmail,
          receiverAddress: launch.clientAddress,
          initialSavedClientId: launch.savedClientId,
          initialClientTaxId: launch.clientTaxId,
          initialClientExternalNumber: launch.externalClientNumber,
          initialDocType: 'receipt',
          initialItems: [
            {
              'description': strings.paymentFor(number),
              'quantity': 1,
              'price': amount,
              'priceTaxMode': 'after_tax',
            },
          ],
          initialNotes: strings.receiptNote(number),
          initialPaymentAmount: amount,
          sourceInvoiceNumber: number,
          sourceInvoiceDocId: documentId,
          sourceInvoiceTotalAmount: ((data['amount'] as num?)?.toDouble() ?? 0)
              .abs(),
          initialLinkedDocuments: [_linkedSeed(documentId, data)],
        ),
      ),
    );
  }

  static Future<void> _openCreditNote(
    BuildContext context,
    User user,
    String documentId,
    Map<String, dynamic> data,
    Map<String, dynamic> profile,
    _ActionStrings strings,
  ) async {
    final number = _documentNumber(data);
    if (number.isEmpty) throw StateError('Missing document number');
    final items = _items(data);
    final launch = _LaunchData(user, profile, data);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderPage(
          workerName: launch.workerName,
          workerPhone: launch.workerPhone,
          workerEmail: launch.workerEmail,
          receiverName: launch.clientName,
          receiverPhone: launch.clientPhone,
          receiverEmail: launch.clientEmail,
          receiverAddress: launch.clientAddress,
          initialSavedClientId: launch.savedClientId,
          initialClientTaxId: launch.clientTaxId,
          initialClientExternalNumber: launch.externalClientNumber,
          initialDocType: 'credit_note',
          sourceInvoiceNumber: number,
          sourceInvoiceDocId: documentId,
          initialItems: items,
          initialNotes: (data['notes'] ?? '').toString(),
          initialPaymentMethod: (data['paymentMethod'] ?? '').toString(),
          initialCheckNumber: (data['checkNumber'] ?? '').toString(),
          initialTransferDetails: (data['transferDetails'] ?? '').toString(),
          initialCreditOriginalInvoiceNumber: number,
          initialCreditOriginalInvoiceDate: _displayDate(
            (data['date'] ?? '').toString(),
          ),
          initialCreditReason: strings.creditReason(number),
          initialCreditDeliveryMethod: 'email_confirmation',
          initialCreditReceiptConfirmation: strings.creditConfirmation(number),
          initialLinkedDocuments: [_linkedSeed(documentId, data)],
        ),
      ),
    );
  }

  static Future<void> _openCancellingReceipt(
    BuildContext context,
    User user,
    String documentId,
    Map<String, dynamic> data,
    Map<String, dynamic> profile,
    _ActionStrings strings,
  ) async {
    final amount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
    if (amount <= 0) throw StateError('Missing receipt amount');
    final number = _documentNumber(data);
    final payments = data['paymentMethods'];
    final firstPayment = payments is List && payments.isNotEmpty
        ? Map<String, dynamic>.from(payments.first as Map)
        : const <String, dynamic>{};
    final launch = _LaunchData(user, profile, data);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderPage(
          workerName: launch.workerName,
          workerPhone: launch.workerPhone,
          workerEmail: launch.workerEmail,
          receiverName: launch.clientName,
          receiverPhone: launch.clientPhone,
          receiverEmail: launch.clientEmail,
          receiverAddress: launch.clientAddress,
          initialSavedClientId: launch.savedClientId,
          initialClientTaxId: launch.clientTaxId,
          initialClientExternalNumber: launch.externalClientNumber,
          initialDocType: 'receipt',
          initialNotes: strings.cancellationNote(number),
          initialPaymentMethod:
              (firstPayment['method'] ?? data['paymentMethod'] ?? 'cash')
                  .toString(),
          initialPaymentAmount: amount,
          initialIsNegativeReceipt: true,
          cancellationSourceDocumentId: documentId,
          cancellationSourceDocumentNumber: number,
          initialLinkedDocuments: [_linkedSeed(documentId, data)],
        ),
      ),
    );
  }

  static Future<void> _openDerivedDocument(
    BuildContext context,
    User user,
    String documentId,
    Map<String, dynamic> data,
    Map<String, dynamic> profile,
    _ActionStrings strings,
    String targetType,
  ) async {
    double? paymentAmount;
    if (targetType == 'invoice_receipt') {
      final available = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
      paymentAmount = await _askReceiptAmount(context, available, strings);
      if (paymentAmount == null || !context.mounted) return;
    }
    final launch = _LaunchData(user, profile, data);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceBuilderPage(
          workerName: launch.workerName,
          workerPhone: launch.workerPhone,
          workerEmail: launch.workerEmail,
          receiverName: launch.clientName,
          receiverPhone: launch.clientPhone,
          receiverEmail: launch.clientEmail,
          receiverAddress: launch.clientAddress,
          initialSavedClientId: launch.savedClientId,
          initialClientTaxId: launch.clientTaxId,
          initialClientExternalNumber: launch.externalClientNumber,
          initialDocType: targetType,
          initialItems: _items(data),
          initialNotes: (data['notes'] ?? '').toString(),
          initialPaymentAmount: paymentAmount,
          initialLinkedDocuments: [_linkedSeed(documentId, data)],
        ),
      ),
    );
  }

  static Future<double?> _askReceiptAmount(
    BuildContext context,
    double remaining,
    _ActionStrings strings,
  ) async {
    if (remaining <= 0) return null;
    final controller = TextEditingController(
      text: remaining.toStringAsFixed(2),
    );
    String? error;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final amount = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (amount == null || amount <= 0 || amount > remaining + 0.01) {
              setDialogState(() => error = strings.invalidAmount);
              return;
            }
            Navigator.pop(dialogContext, amount);
          }

          return AlertDialog(
            title: Text(strings.createReceipt),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${strings.remaining}: ${remaining.toStringAsFixed(2)} ₪'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: strings.receiptAmount,
                    suffixText: '₪',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(strings.close),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(strings.continueText),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  static Future<void> _openPreview(
    BuildContext context,
    String userId,
    String documentId,
    Map<String, dynamic> fallbackData,
    _ActionStrings strings,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('invoices')
          .doc(documentId)
          .get();
      final data = snapshot.data() ?? fallbackData;
      final fileName =
          (data['fileName'] ?? '${_documentTitle(data, strings)}.pdf')
              .toString();
      final url = (data['url'] ?? '').toString().trim();
      final storagePath = (data['storagePath'] ?? '').toString().trim();
      final fallback = data['fallbackPreview'];
      final fallbackUrl = fallback is Map
          ? (fallback['url'] ?? '').toString().trim()
          : '';
      final fallbackPath = fallback is Map
          ? (fallback['storagePath'] ?? '').toString().trim()
          : '';
      final hasFallback =
          fallback is Map &&
          fallback['status'] == 'available' &&
          fallback['previewOnly'] == true &&
          fallbackUrl.isNotEmpty &&
          fallbackPath.isNotEmpty;
      final finalized = _isFinalized(data);
      final opensFallback = hasFallback && !finalized;
      final openingUrl = opensFallback ? fallbackUrl : url;
      final openingPath = opensFallback ? fallbackPath : storagePath;
      if (openingUrl.isEmpty && openingPath.isEmpty) {
        throw StateError('Document file unavailable');
      }
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SavedInvoicePreviewPage(
            name: opensFallback
                ? (fallback['fileName'] ?? fileName).toString()
                : fileName,
            url: openingUrl,
            invoiceDocId: documentId,
            canReportMissing: finalized,
            storagePath: openingPath,
            previewOnly: opensFallback,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.openFailed)));
    }
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> data) =>
      ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  static Map<String, dynamic> _linkedSeed(
    String documentId,
    Map<String, dynamic> data,
  ) => {
    'invoiceDocId': (data['invoiceDocId'] ?? documentId).toString(),
    'docType': data['docType'] ?? data['type'] ?? '',
    'documentNumber': data['invoiceNumber'] ?? data['documentNumber'] ?? '',
    'name': data['name'] ?? '',
    'date': data['date'] ?? '',
    'amount': data['amount'] ?? 0,
    if (data['createdAt'] != null) 'createdAt': data['createdAt'],
  };

  static bool _isFinalized(Map<String, dynamic> data) {
    final hasWorkflow =
        data['taxAuthorityAllocationRequest'] is Map ||
        data['serverDocument'] is Map;
    final recovery = data['documentRecovery'];
    final missingFinalPdf =
        recovery is Map &&
        recovery['status'] == 'needs_reconciliation' &&
        recovery['reason'] == 'missing_final_pdf';
    return (!hasWorkflow || data['documentStatus'] == 'finalized') &&
        !missingFinalPdf;
  }

  static bool _isCancelled(Map<String, dynamic> data) =>
      (data['cancellationStatus'] ?? '').toString().toLowerCase() ==
          'cancelled' ||
      (data['documentStatus'] ?? '').toString().toLowerCase() == 'cancelled';

  static double _remainingAmount(Map<String, dynamic> data) {
    final amount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
    final paid = ((data['paidAmount'] as num?)?.toDouble() ?? 0).abs();
    final credited = ((data['cancelledAmount'] as num?)?.toDouble() ?? 0)
        .abs()
        .clamp(0, amount);
    return (amount - paid - credited).clamp(0, amount).toDouble();
  }

  static Future<bool> _canCreateTaxDocuments(String userId) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId);
      final results = await Future.wait([
        userRef.get(),
        userRef.collection('verification_info').doc('latest').get(),
      ]);
      final userData = results[0].data() ?? const <String, dynamic>{};
      final verificationData = results[1].data() ?? const <String, dynamic>{};
      final dealerType =
          (verificationData['dealerType'] ??
                  userData['dealerType'] ??
                  userData['businessType'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();
      return dealerType == 'licensed' ||
          dealerType == 'company' ||
          dealerType.contains('licensed') ||
          dealerType.contains('company') ||
          dealerType.contains('מורשה') ||
          dealerType.contains('חברה');
    } catch (_) {
      return false;
    }
  }

  static String _documentNumber(Map<String, dynamic> data) =>
      (data['invoiceNumber'] ?? data['documentNumber'] ?? '').toString().trim();

  static String _documentTitle(
    Map<String, dynamic> data,
    _ActionStrings strings,
  ) {
    final type = (data['docType'] ?? data['type'] ?? '').toString();
    final number = _documentNumber(data);
    return '${strings.typeName(type)}${number.isEmpty ? '' : ' #$number'}';
  }

  static String _displayDate(String raw) {
    final value = raw.trim();
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      return '${value.substring(6, 8)}/${value.substring(4, 6)}/${value.substring(0, 4)}';
    }
    return value;
  }
}

class _LaunchData {
  _LaunchData(
    User user,
    Map<String, dynamic> profile,
    Map<String, dynamic> document,
  ) : workerName = (profile['name'] ?? user.displayName ?? 'Worker').toString(),
      workerPhone = _optional(profile['phone'] ?? profile['phoneNumber']),
      workerEmail = _optional(profile['email'] ?? user.email),
      clientName = _optional(document['clientName']),
      clientPhone = _optional(document['clientPhone']),
      clientEmail = _optional(document['clientEmail']),
      clientAddress = _optional(document['clientAddress']),
      savedClientId = _optional(
        document['savedClientId'] ?? document['clientUid'],
      ),
      clientTaxId = _optional(document['clientTaxId']),
      externalClientNumber = _optional(document['externalClientNumber']);

  final String workerName;
  final String? workerPhone;
  final String? workerEmail;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;
  final String? clientAddress;
  final String? savedClientId;
  final String? clientTaxId;
  final String? externalClientNumber;

  static String? _optional(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.strings,
    required this.onTap,
  });

  final _LinkedDocumentAction action;
  final _ActionStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final destructive =
        action == _LinkedDocumentAction.creditNote ||
        action == _LinkedDocumentAction.cancelReceipt;
    final icon = switch (action) {
      _LinkedDocumentAction.open => Icons.visibility_outlined,
      _LinkedDocumentAction.receipt => Icons.receipt_long_outlined,
      _LinkedDocumentAction.creditNote ||
      _LinkedDocumentAction.cancelReceipt => Icons.assignment_return_rounded,
      _LinkedDocumentAction.workOrder => Icons.assignment_outlined,
      _LinkedDocumentAction.transactionAccount => Icons.description_outlined,
      _LinkedDocumentAction.invoice => Icons.request_quote_outlined,
      _LinkedDocumentAction.invoiceReceipt => Icons.receipt_rounded,
    };
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: destructive
              ? const Color(0xFFDC2626)
              : const Color(0xFF1976D2),
        ),
      ),
      title: Text(
        strings.actionLabel(action),
        style: TextStyle(
          color: destructive
              ? const Color(0xFFB91C1C)
              : const Color(0xFF0F172A),
          fontWeight: FontWeight.w800,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _ActionStrings {
  _ActionStrings(this.locale);

  final String locale;
  String pick(String en, String he, String ar, String ru, String am) =>
      switch (locale) {
        'he' => he,
        'ar' => ar,
        'ru' => ru,
        'am' => am,
        _ => en,
      };

  String get actions => pick(
    'Document actions',
    'פעולות מסמך',
    'إجراءات المستند',
    'Действия с документом',
    'የሰነድ ድርጊቶች',
  );
  String get remaining =>
      pick('Remaining', 'נותר לתשלום', 'المتبقي', 'Остаток', 'ቀሪ');
  String get creationLocked => pick(
    'Creating linked documents is locked for this document.',
    'יצירת מסמכים מקושרים נעולה עבור מסמך זה.',
    'إنشاء مستندات مرتبطة مقفل لهذا المستند.',
    'Создание связанных документов заблокировано.',
    'የተገናኙ ሰነዶችን መፍጠር ተቆልፏል።',
  );
  String get cancelledLocked => pick(
    'This document is cancelled and cannot create more documents.',
    'מסמך זה בוטל ולא ניתן ליצור ממנו מסמכים נוספים.',
    'هذا المستند ملغى ولا يمكن إنشاء مستندات منه.',
    'Документ отменён; новые документы создать нельзя.',
    'ይህ ሰነድ ተሰርዟል።',
  );
  String get actionFailed => pick(
    'Could not start this document action.',
    'לא ניתן היה להתחיל את פעולת המסמך.',
    'تعذر بدء إجراء المستند.',
    'Не удалось выполнить действие.',
    'የሰነድ ድርጊቱን መጀመር አልተቻለም።',
  );
  String get openFailed => pick(
    'Could not open this document.',
    'לא ניתן לפתוח את המסמך.',
    'تعذر فتح المستند.',
    'Не удалось открыть документ.',
    'ሰነዱን መክፈት አልተቻለም።',
  );
  String get noRemainingBalance => pick(
    'This document has no remaining balance.',
    'לא נותרה יתרה לתשלום במסמך.',
    'لا يوجد رصيد متبقٍ في المستند.',
    'В документе нет остатка к оплате.',
    'በሰነዱ ላይ ቀሪ ሂሳብ የለም።',
  );
  String get createReceipt => pick(
    'Create receipt',
    'יצירת קבלה',
    'إنشاء إيصال',
    'Создать квитанцию',
    'ደረሰኝ ፍጠር',
  );
  String get receiptAmount => pick(
    'Receipt amount',
    'סכום הקבלה',
    'مبلغ الإيصال',
    'Сумма квитанции',
    'የደረሰኝ መጠን',
  );
  String get invalidAmount => pick(
    'Enter a valid amount that does not exceed the remaining balance.',
    'יש להזין סכום תקין שאינו גדול מהיתרה.',
    'أدخل مبلغاً صالحاً لا يتجاوز المتبقي.',
    'Введите сумму не больше остатка.',
    'ከቀሪው የማይበልጥ ትክክለኛ መጠን ያስገቡ።',
  );
  String get close => pick('Cancel', 'ביטול', 'إلغاء', 'Отмена', 'ሰርዝ');
  String get continueText =>
      pick('Continue', 'המשך', 'متابعة', 'Продолжить', 'ቀጥል');

  String actionLabel(_LinkedDocumentAction action) => switch (action) {
    _LinkedDocumentAction.open => pick(
      'Open document',
      'פתח מסמך',
      'فتح المستند',
      'Открыть документ',
      'ሰነድ ክፈት',
    ),
    _LinkedDocumentAction.receipt => pick(
      'Create receipt',
      'צור קבלה',
      'إنشاء إيصال',
      'Создать квитанцию',
      'ደረሰኝ ፍጠር',
    ),
    _LinkedDocumentAction.creditNote => pick(
      'Cancel document (create credit note)',
      'בטל מסמך (צור חשבונית זיכוי)',
      'إلغاء المستند (إنشاء إشعار دائن)',
      'Отменить (создать кредитовый счёт)',
      'ሰነድ ሰርዝ (የብድር ሰነድ ፍጠር)',
    ),
    _LinkedDocumentAction.cancelReceipt => pick(
      'Cancel receipt',
      'בטל קבלה',
      'إلغاء الإيصال',
      'Отменить квитанцию',
      'ደረሰኝ ሰርዝ',
    ),
    _LinkedDocumentAction.workOrder => pick(
      'Create work order',
      'צור הזמנת עבודה',
      'إنشاء أمر عمل',
      'Создать заказ на работу',
      'የሥራ ትዕዛዝ ፍጠር',
    ),
    _LinkedDocumentAction.transactionAccount => pick(
      'Create proforma invoice',
      'צור חשבון עסקה',
      'إنشاء فاتورة أولية',
      'Создать проформу',
      'የግብይት ሂሳብ ፍጠር',
    ),
    _LinkedDocumentAction.invoice => pick(
      'Create tax invoice',
      'צור חשבונית מס',
      'إنشاء فاتورة ضريبية',
      'Создать налоговый счёт',
      'የግብር ደረሰኝ ፍጠር',
    ),
    _LinkedDocumentAction.invoiceReceipt => pick(
      'Create tax invoice / receipt',
      'צור חשבונית מס / קבלה',
      'إنشاء فاتورة ضريبية / إيصال',
      'Создать налоговый счёт / квитанцию',
      'የግብር ደረሰኝ / ክፍያ ፍጠር',
    ),
  };

  String typeName(String type) => switch (type) {
    'quote' => pick(
      'Quote',
      'הצעת מחיר',
      'عرض سعر',
      'Предложение',
      'የዋጋ ማቅረቢያ',
    ),
    'work_order' => pick(
      'Work order',
      'הזמנת עבודה',
      'أمر عمل',
      'Заказ на работу',
      'የሥራ ትዕዛዝ',
    ),
    'transaction_account' => pick(
      'Proforma invoice',
      'חשבון עסקה',
      'فاتورة أولية',
      'Проформа',
      'የግብይት ሂሳብ',
    ),
    'invoice' => pick(
      'Tax invoice',
      'חשבונית מס',
      'فاتورة ضريبية',
      'Налоговый счёт',
      'የግብር ደረሰኝ',
    ),
    'invoice_receipt' => pick(
      'Tax invoice / receipt',
      'חשבונית מס / קבלה',
      'فاتورة ضريبية / إيصال',
      'Налоговый счёт / квитанция',
      'የግብር ደረሰኝ / ክፍያ',
    ),
    'receipt' => pick('Receipt', 'קבלה', 'إيصال', 'Квитанция', 'የክፍያ ደረሰኝ'),
    'credit_note' => pick(
      'Credit note',
      'חשבונית מס זיכוי',
      'إشعار دائن',
      'Кредитовый счёт',
      'የብድር ሰነድ',
    ),
    _ => pick('Document', 'מסמך', 'مستند', 'Документ', 'ሰነድ'),
  };

  String paymentFor(String number) => pick(
    'Payment for Invoice #$number',
    'תשלום עבור חשבונית מספר $number',
    'دفعة للفاتورة رقم $number',
    'Оплата счёта №$number',
    'ለደረሰኝ #$number ክፍያ',
  );
  String receiptNote(String number) => pick(
    'Receipt created from document #$number',
    'קבלה שנוצרה ממסמך #$number',
    'إيصال أُنشئ من المستند رقم $number',
    'Квитанция создана из документа №$number',
    'ከሰነድ #$number የተፈጠረ ደረሰኝ',
  );
  String creditReason(String number) => pick(
    'Tax Invoice Credit for document #$number',
    'חשבונית מס זיכוי עבור מסמך מספר $number',
    'إشعار دائن للمستند رقم $number',
    'Кредитовый счёт для документа №$number',
    'ለሰነድ #$number የብድር ሰነድ',
  );
  String creditConfirmation(String number) => pick(
    'Created from document #$number. Update with the actual delivery proof before legal use.',
    'נוצר ממסמך #$number. יש לעדכן אסמכתא למסירה בפועל לפני שימוש משפטי.',
    'أُنشئ من المستند رقم $number. حدّث إثبات التسليم قبل الاستخدام القانوني.',
    'Создано из документа №$number. Укажите подтверждение доставки.',
    'ከሰነድ #$number ተፈጥሯል። የማድረስ ማረጋገጫውን ያዘምኑ።',
  );
  String cancellationNote(String number) => pick(
    'Cancellation receipt for Receipt #$number',
    'קבלה מבטלת עבור קבלה מספר $number',
    'إيصال إلغاء للإيصال رقم $number',
    'Отмена квитанции №$number',
    'ለደረሰኝ #$number የስረዛ ደረሰኝ',
  );
}
