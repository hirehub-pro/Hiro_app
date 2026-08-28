import 'dart:developer' as dev;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf;
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
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/services/invoice_builder_lock_service.dart';
import 'package:untitled1/services/invoice_builder_verification_session.dart';
import 'package:untitled1/services/client_service.dart';
import 'package:untitled1/services/app_navigation_service.dart';
import 'package:untitled1/services/profile_document_service.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:xml/xml.dart';

class _BankBranch {
  const _BankBranch({required this.name, required this.code});

  final String name;
  final String code;

  String get label => '$name - $code';
}

class _InvoiceClient {
  const _InvoiceClient({
    required this.id,
    required this.name,
    required this.externalClientNumber,
    required this.taxId,
    required this.phone,
    required this.email,
    required this.address,
  });

  factory _InvoiceClient.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return _InvoiceClient(
      id: document.id,
      name: (data['name'] ?? '').toString().trim(),
      externalClientNumber: (data['externalClientNumber'] ?? '')
          .toString()
          .trim(),
      taxId: (data['taxId'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      email: (data['email'] ?? '').toString().trim(),
      address: (data['address'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String name;
  final String externalClientNumber;
  final String taxId;
  final String phone;
  final String email;
  final String address;

  String get searchText =>
      '$name $externalClientNumber $taxId $phone $email $address'.toLowerCase();

  String get subtitle {
    final details = [
      externalClientNumber,
      phone,
      email,
    ].where((value) => value.isNotEmpty).toList();
    if (details.isNotEmpty) return details.join(' • ');
    return address;
  }
}

class _LinkedInvoiceDocument {
  const _LinkedInvoiceDocument({
    required this.id,
    required this.docType,
    required this.documentNumber,
    required this.name,
    required this.date,
    required this.amount,
    required this.createdAt,
  });

  factory _LinkedInvoiceDocument.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => _LinkedInvoiceDocument.fromMap({
    ...document.data(),
    'invoiceDocId': document.id,
  });

  factory _LinkedInvoiceDocument.fromMap(Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    return _LinkedInvoiceDocument(
      id: (data['invoiceDocId'] ?? data['id'] ?? '').toString().trim(),
      docType: (data['docType'] ?? data['type'] ?? '').toString().trim(),
      documentNumber: (data['invoiceNumber'] ?? data['documentNumber'] ?? '')
          .toString()
          .trim(),
      name: (data['name'] ?? '').toString().trim(),
      date: (data['date'] ?? '').toString().trim(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      createdAt: rawCreatedAt is Timestamp
          ? rawCreatedAt.toDate()
          : rawCreatedAt is DateTime
          ? rawCreatedAt
          : null,
    );
  }

  final String id;
  final String docType;
  final String documentNumber;
  final String name;
  final String date;
  final double amount;
  final DateTime? createdAt;

  Map<String, dynamic> toReferenceMap() => {
    'invoiceDocId': id,
    'docType': docType,
    if (documentNumber.isNotEmpty) 'documentNumber': documentNumber,
    if (name.isNotEmpty) 'name': name,
    if (date.isNotEmpty) 'date': date,
    'amount': amount,
  };
}

Map<String, List<_BankBranch>> _parseBankBranches(String xmlText) {
  final document = XmlDocument.parse(xmlText);
  final branchesByBankId = <String, List<_BankBranch>>{};

  for (final branch in document.findAllElements('branch')) {
    final bankId = branch.getElement('id')?.innerText.trim() ?? '';
    final branchName = branch.getElement('branch_name')?.innerText.trim() ?? '';
    final branchCode = branch.getElement('branch_code')?.innerText.trim() ?? '';
    if (bankId.isEmpty || branchName.isEmpty || branchCode.isEmpty) {
      continue;
    }

    branchesByBankId
        .putIfAbsent(bankId, () => [])
        .add(_BankBranch(name: branchName, code: branchCode));
  }

  for (final branches in branchesByBankId.values) {
    branches.sort((a, b) => a.label.compareTo(b.label));
  }
  return branchesByBankId;
}

class _SavedInvoiceResult {
  final String url;
  final String fileName;

  const _SavedInvoiceResult({required this.url, required this.fileName});
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

class _ServerDocumentResult {
  final Map<String, dynamic> document;

  const _ServerDocumentResult({required this.document});

  InvoiceBuilderDraftResult? toDraftResult() {
    final url = document['url']?.toString().trim() ?? '';
    final fileName = document['fileName']?.toString().trim() ?? '';
    final invoiceDocId = document['invoiceDocId']?.toString().trim() ?? '';
    final storagePath = document['storagePath']?.toString().trim() ?? '';
    final docType = document['docType']?.toString().trim() ?? '';
    final amount = (document['amount'] as num?)?.toDouble();
    final rawItems = document['items'];
    if (url.isEmpty ||
        fileName.isEmpty ||
        invoiceDocId.isEmpty ||
        storagePath.isEmpty ||
        docType.isEmpty ||
        amount == null ||
        rawItems is! List) {
      return null;
    }
    return InvoiceBuilderDraftResult(
      url: url,
      fileName: fileName,
      invoiceDocId: invoiceDocId,
      storagePath: storagePath,
      amount: amount,
      docType: docType,
      documentNumber: document['documentNumber']?.toString(),
      items: rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
  }
}

class _LinkedDocumentsDialog extends StatefulWidget {
  const _LinkedDocumentsDialog({
    required this.strings,
    required this.loadDocuments,
    required this.initiallySelected,
    required this.documentTypeLabel,
  });

  final Map<String, String> strings;
  final Future<List<_LinkedInvoiceDocument>> Function() loadDocuments;
  final Map<String, _LinkedInvoiceDocument> initiallySelected;
  final String Function(String docType) documentTypeLabel;

  @override
  State<_LinkedDocumentsDialog> createState() => _LinkedDocumentsDialogState();
}

class _LinkedDocumentsDialogState extends State<_LinkedDocumentsDialog> {
  late final Map<String, _LinkedInvoiceDocument> _selected = Map.from(
    widget.initiallySelected,
  );
  final TextEditingController _searchController = TextEditingController();
  List<_LinkedInvoiceDocument> _documents = const [];
  bool _isLoading = true;
  Object? _loadError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _query) return;
    setState(() => _query = query);
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final documents = await widget.loadDocuments();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  String _dateLabel(_LinkedInvoiceDocument document) {
    if (document.createdAt != null) {
      return intl.DateFormat('dd/MM/yyyy').format(document.createdAt!);
    }
    final raw = document.date;
    if (RegExp(r'^\d{8}$').hasMatch(raw)) {
      return '${raw.substring(6, 8)}/${raw.substring(4, 6)}/${raw.substring(0, 4)}';
    }
    return raw;
  }

  String _title(_LinkedInvoiceDocument document) {
    final type = widget.documentTypeLabel(document.docType);
    if (document.documentNumber.isNotEmpty) {
      return '$type #${document.documentNumber}';
    }
    return document.name.isNotEmpty ? document.name : type;
  }

  Color _documentColor(String docType) {
    switch (docType) {
      case 'quote':
        return const Color(0xFF0F766E);
      case 'work_order':
        return const Color(0xFF92400E);
      case 'transaction_account':
        return const Color(0xFF6D28D9);
      case 'invoice':
        return const Color(0xFF1D4ED8);
      case 'invoice_receipt':
        return const Color(0xFF15803D);
      case 'credit_note':
        return const Color(0xFFBE185D);
      case 'receipt':
      default:
        return const Color(0xFFEA580C);
    }
  }

  IconData _documentIcon(String docType) {
    switch (docType) {
      case 'quote':
        return Icons.request_quote_outlined;
      case 'work_order':
        return Icons.assignment_outlined;
      case 'transaction_account':
        return Icons.description_outlined;
      case 'invoice':
        return Icons.receipt_long_outlined;
      case 'invoice_receipt':
        return Icons.task_alt_rounded;
      case 'credit_note':
        return Icons.currency_exchange_rounded;
      case 'receipt':
      default:
        return Icons.receipt_outlined;
    }
  }

  List<_LinkedInvoiceDocument> get _visibleDocuments {
    if (_query.isEmpty) return _documents;
    return _documents.where((document) {
      final searchText = [
        _title(document),
        widget.documentTypeLabel(document.docType),
        document.documentNumber,
        document.name,
        _dateLabel(document),
        document.amount.toStringAsFixed(2),
      ].join(' ').toLowerCase();
      return searchText.contains(_query);
    }).toList();
  }

  void _toggleDocument(_LinkedInvoiceDocument document) {
    setState(() {
      if (_selected.containsKey(document.id)) {
        _selected.remove(document.id);
      } else {
        _selected[document.id] = document;
      }
    });
  }

  Widget _buildStatusContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 16),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return _DialogEmptyState(
        icon: Icons.cloud_off_outlined,
        message: widget.strings['linked_documents_load_failed']!,
        actionLabel: widget.strings['retry']!,
        onAction: _loadDocuments,
      );
    }
    if (_documents.isEmpty) {
      return _DialogEmptyState(
        icon: Icons.folder_off_outlined,
        message: widget.strings['linked_documents_empty']!,
      );
    }

    final visibleDocuments = _visibleDocuments;
    if (visibleDocuments.isEmpty) {
      return _DialogEmptyState(
        icon: Icons.search_off_rounded,
        message: widget.strings['linked_documents_no_results']!,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: visibleDocuments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final document = visibleDocuments[index];
        final selected = _selected.containsKey(document.id);
        final color = _documentColor(document.docType);
        final date = _dateLabel(document);
        return Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleDocument(document),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.07)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? color : const Color(0xFFE2E8F0),
                    width: selected ? 1.6 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        _documentIcon(document.docType),
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title(document),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            children: [
                              if (date.isNotEmpty)
                                _DocumentMetadata(
                                  icon: Icons.calendar_today_outlined,
                                  label: date,
                                ),
                              _DocumentMetadata(
                                icon: Icons.payments_outlined,
                                label:
                                    '${document.amount.toStringAsFixed(2)} ₪',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected ? color : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? color : const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogHeight = mediaQuery.size.height * 0.86;
    final hasDocuments =
        !_isLoading && _loadError == null && _documents.isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: const Color(0xFFF8FAFC),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: dialogHeight),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.link_rounded,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.strings['linked_documents_title']!,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.strings['linked_documents_helper']!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: widget.strings['cancel'],
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
            if (hasDocuments) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.strings['linked_documents_search']!,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
            Expanded(child: _buildStatusContent()),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 17),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(widget.strings['cancel']!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_selected.values.toList()),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.link_rounded, size: 19),
                      label: Text(
                        _selected.isEmpty
                            ? widget.strings['link_documents_action']!
                            : widget.strings['link_documents_action_count']!
                                  .replaceFirst(
                                    '{count}',
                                    '${_selected.length}',
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
    );
  }
}

class _DocumentMetadata extends StatelessWidget {
  const _DocumentMetadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DialogEmptyState extends StatelessWidget {
  const _DialogEmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: const Color(0xFF3B82F6)),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
  _PaymentMethodEntry() {
    ensureCreditInstallmentCount(1);
  }

  String method = 'cash';
  bool isExpanded = true;
  final amountController = TextEditingController();

  final cardNumberController = TextEditingController();
  final cardNameController = TextEditingController();
  final cardExpirationController = TextEditingController();
  final installmentsController = TextEditingController(text: '1');
  final List<DateTime?> creditInstallmentDates = [];
  final List<TextEditingController> creditInstallmentDateControllers = [];
  final checkNumberController = TextEditingController();
  final checkPaymentDateController = TextEditingController();
  DateTime? checkPaymentDate;
  final checkBankController = TextEditingController();
  final checkBankFocusNode = FocusNode();
  final checkBranchController = TextEditingController();
  final checkBranchFocusNode = FocusNode();
  final checkAccountController = TextEditingController();
  final transferBankController = TextEditingController();
  final transferBankFocusNode = FocusNode();
  final transferBranchController = TextEditingController();
  final transferBranchFocusNode = FocusNode();
  final transferAccountController = TextEditingController();

  void ensureCreditInstallmentCount(int count) {
    final safeCount = count.clamp(1, 999);
    while (creditInstallmentDates.length < safeCount) {
      creditInstallmentDates.add(null);
      creditInstallmentDateControllers.add(TextEditingController());
    }
    while (creditInstallmentDates.length > safeCount) {
      creditInstallmentDates.removeLast();
      creditInstallmentDateControllers.removeLast().dispose();
    }
  }

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
        if (cardNumberController.text.trim().isNotEmpty) {
          data['cardNumber'] = cardNumberController.text.trim();
        }
        if (cardNameController.text.trim().isNotEmpty) {
          data['cardName'] = cardNameController.text.trim();
        }
        if (cardExpirationController.text.trim().isNotEmpty) {
          data['cardExpiration'] = cardExpirationController.text.trim();
        }
        if (installmentsController.text.trim().isNotEmpty) {
          data['installments'] = installmentsController.text.trim();
        }
        final installmentCount =
            int.tryParse(installmentsController.text.trim()) ?? 1;
        if (installmentCount > 1 &&
            creditInstallmentDates.length == installmentCount &&
            creditInstallmentDates.every((date) => date != null)) {
          data['installmentDates'] = creditInstallmentDates
              .map((date) => intl.DateFormat('yyyy-MM-dd').format(date!))
              .toList(growable: false);
        }
        break;
      case 'check':
        data['checkNumber'] = checkNumberController.text.trim();
        if (checkPaymentDate != null) {
          data['paymentDate'] = intl.DateFormat(
            'yyyy-MM-dd',
          ).format(checkPaymentDate!);
        }
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
        if (transferBankController.text.trim().isNotEmpty) {
          data['bank'] = transferBankController.text.trim();
        }
        if (transferBranchController.text.trim().isNotEmpty) {
          data['branch'] = transferBranchController.text.trim();
        }
        if (transferAccountController.text.trim().isNotEmpty) {
          data['account'] = transferAccountController.text.trim();
        }
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
    cardExpirationController.dispose();
    installmentsController.dispose();
    for (final controller in creditInstallmentDateControllers) {
      controller.dispose();
    }
    checkNumberController.dispose();
    checkPaymentDateController.dispose();
    checkBankController.dispose();
    checkBankFocusNode.dispose();
    checkBranchController.dispose();
    checkBranchFocusNode.dispose();
    checkAccountController.dispose();
    transferBankController.dispose();
    transferBankFocusNode.dispose();
    transferBranchController.dispose();
    transferBranchFocusNode.dispose();
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
  final String? initialSavedClientId;
  final String? initialClientTaxId;
  final String? initialClientExternalNumber;
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
  final bool initialIsNegativeReceipt;
  final String? cancellationSourceDocumentId;
  final String? cancellationSourceDocumentNumber;
  final List<Map<String, dynamic>> initialLinkedDocuments;
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
    this.initialSavedClientId,
    this.initialClientTaxId,
    this.initialClientExternalNumber,
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
    this.initialIsNegativeReceipt = false,
    this.cancellationSourceDocumentId,
    this.cancellationSourceDocumentNumber,
    this.initialLinkedDocuments = const [],
    this.returnDraftOnSend = false,
  });

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
  static const int _sandboxAccountingSoftwareNumber = 987654321;
  static const Set<String> _licensedOnlyDocumentTypes = {
    'invoice',
    'invoice_receipt',
    'credit_note',
  };
  static const Map<String, int> _suggestedStartingDocumentNumbers = {
    'invoice': 1001,
    'receipt': 2001,
    'invoice_receipt': 3001,
    'credit_note': 4001,
    'transaction_account': 5001,
  };
  static const List<String> _bankNames = [
    'יהב - 4',
    'U-Bank - 26',
    'בנק פאגי - 52',
    'בנק אוצר החייל - 14',
    'בנק וואן זירו - 18',
    'מזרחי-טפחות - 20',
    'מרכנתיל - 17',
    'בנק מסד - 46',
    'לאומי - 10',
    'בנק ירושלים - 54',
    'הפועלים - 12',
    'דיסקונט - 11',
    'הבינלאומי - 31',
    'בנק הדואר - 9',
    'סיטי בנק - 22',
    'בנק ישראל - 99',
  ];
  static const List<String> _creditCompanies = [
    'Diners',
    'CAL',
    'Leumi Card',
    'American Express',
    'Isracard',
  ];
  final Map<String, List<_BankBranch>> _branchesByBankId = {};
  bool _isLoadingBankBranches = true;

  final InvoiceBuilderLockService _invoiceBuilderLock =
      InvoiceBuilderLockService();
  bool _isAcquiringLock = true;
  bool _hasInvoiceBuilderLock = false;
  bool _lockLostDialogShown = false;

  // Opening the invoice builder is a sensitive action. Keep its contents and
  // its single-device lock unavailable until the signed-in user proves their
  // identity again for this visit.
  final _identityPhoneController = TextEditingController();
  final _identityPasswordController = TextEditingController();
  final _identityEmailCodeController = TextEditingController();
  bool _isIdentityVerified = false;
  bool _isVerifyingIdentity = false;
  bool _isEmailCodeSent = false;
  bool _obscureIdentityPassword = true;
  String? _identityVerificationError;
  Timer? _identityResendTimer;
  int _identityResendSecondsRemaining = 0;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'me-west1',
  );

  bool get _isLicensedDealerType =>
      _dealerType == 'licensed' || _dealerType == 'company';
  bool get _showsLicensedOnlyDocumentTypes => _isLicensedDealerType;

  String _normalizePaymentMethod(String? raw) {
    switch (raw) {
      case 'cash':
      case 'credit':
      case 'transfer':
      case 'check':
      case 'bit':
      case 'paybox':
      case 'other':
      case 'withholding_tax':
        return raw!;
      default:
        return 'cash';
    }
  }

  String _counterDocIdForType(String docType) =>
      docType == 'transaction_account'
      ? 'document_counter_transaction_account'
      : 'document_counter_$docType';

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

  String _invoiceDocIdFor(String docType, String documentNumber) {
    return '${docType}_$documentNumber';
  }

  String _labelForDocType(String docType) {
    switch (docType) {
      case 'quote':
        return 'Quote';
      case 'work_order':
        return 'Work Order';
      case 'transaction_account':
        return 'Proforma Invoice';
      case 'invoice':
        return 'Invoice';
      case 'invoice_receipt':
        return 'Invoice Receipt';
      case 'credit_note':
        return 'Tax Invoice Credit';
      case 'receipt':
      default:
        return 'Receipt';
    }
  }

  final _clientNameController = TextEditingController();
  final _clientNameFocusNode = FocusNode();
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
  final _startingDocumentNumberController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedSavedClientId;
  String? _selectedSavedClientExternalNumber;
  final Map<String, _LinkedInvoiceDocument> _linkedDocuments = {};
  bool _isAddingClient = false;

  // Payment method state
  final List<_PaymentMethodEntry> _paymentMethods = [_PaymentMethodEntry()];
  String _selectedCreditDeliveryMethod = 'email_confirmation';

  final List<InvoiceItem> _items = [];
  bool _isPreparing = false;
  bool _hasSavedDocument = false;
  late final String _serverDocumentOperationId = FirebaseFirestore.instance
      .collection('_document_operations')
      .doc()
      .id;
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
  String _selectedDiscountType = 'amount';
  bool _roundTotalEnabled = true;

  bool get _isCreditNote => _selectedDocType == 'credit_note';
  bool get _isNegativeReceipt =>
      widget.initialIsNegativeReceipt && _selectedDocType == 'receipt';
  bool get _isQuoteLike =>
      _selectedDocType == 'quote' || _selectedDocType == 'work_order';
  bool get _showsDueDateSection =>
      _selectedDocType == 'quote' ||
      _selectedDocType == 'transaction_account' ||
      _selectedDocType == 'invoice';
  bool get _requiresSequentialDocumentNumber => !_isQuoteLike;
  bool get _showsPaymentMethodSection =>
      !_isQuoteLike &&
      _selectedDocType != 'invoice' &&
      _selectedDocType != 'transaction_account' &&
      _selectedDocType != 'credit_note';
  bool get _usesVat => _isLicensedDealerType && _selectedDocType != 'receipt';
  bool get _isTaxInvoiceDocType =>
      _selectedDocType == 'invoice' || _selectedDocType == 'invoice_receipt';
  bool get _requiresTaxAuthorityAllocation =>
      _isTaxInvoiceDocType &&
      _usesVat &&
      _digitsOnly(_clientIdController.text).isNotEmpty &&
      _subtotalAmount > _allocationNumberMinAmountBeforeVat;

  bool get _returnsHomeAfterSave =>
      _hasSavedDocument && !widget.returnDraftOnSend;

  void _markDocumentSaved() {
    if (!mounted || _hasSavedDocument) return;
    setState(() => _hasSavedDocument = true);
  }

  void _handleBuilderBack() {
    if (!_returnsHomeAfterSave) {
      Navigator.of(context).maybePop();
      return;
    }
    AppNavigationService.requestHome();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  List<Map<String, dynamic>> get _linkedDocumentReferences => _linkedDocuments
      .values
      .map((document) => document.toReferenceMap())
      .toList(growable: false);

  String _linkedDocumentTitle(
    Map<String, String> strings,
    _LinkedInvoiceDocument document,
  ) {
    final type = _documentTypeDisplayName(strings, document.docType);
    if (document.documentNumber.isNotEmpty) {
      return '$type #${document.documentNumber}';
    }
    return document.name.isNotEmpty ? document.name : type;
  }

  String _linkedDocumentDate(_LinkedInvoiceDocument document) {
    if (document.createdAt != null) {
      return intl.DateFormat('dd/MM/yyyy').format(document.createdAt!);
    }
    final raw = document.date;
    if (RegExp(r'^\d{8}$').hasMatch(raw)) {
      return '${raw.substring(6, 8)}/${raw.substring(4, 6)}/${raw.substring(0, 4)}';
    }
    return raw;
  }

  Widget _buildLinkedDocumentSummary(
    Map<String, String> strings,
    _LinkedInvoiceDocument document,
  ) {
    final date = _linkedDocumentDate(document);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _linkedDocumentTitle(strings, document),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (date.isNotEmpty) date,
                    '${document.amount.toStringAsFixed(2)} ₪',
                  ].join(' • '),
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
        ],
      ),
    );
  }

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
    final grossDocumentTotal = _itemsTotalBeforeDiscount;
    final grossDiscount = _selectedDiscountType == 'percentage'
        ? grossDocumentTotal * parsed / 100
        : parsed;
    final limitedGrossDiscount = grossDiscount > grossDocumentTotal
        ? grossDocumentTotal
        : grossDiscount;
    final discountBeforeTax = _usesVat
        ? limitedGrossDiscount / (1 + _vatRate)
        : limitedGrossDiscount;
    final subtotalBeforeTax = _itemsSubtotalBeforeTax;
    return discountBeforeTax > subtotalBeforeTax
        ? subtotalBeforeTax
        : discountBeforeTax;
  }

  double get _discountAmount => _manualDiscountAmount;

  double get _maximumDiscountInput =>
      _selectedDiscountType == 'percentage' ? 100 : _itemsTotalBeforeDiscount;

  TextInputFormatter _discountInputFormatter() {
    return TextInputFormatter.withFunction((oldValue, newValue) {
      final input = newValue.text.trim();
      if (input.isEmpty) return newValue;
      if (!RegExp(r'^\d*(?:[.,]\d{0,2})?$').hasMatch(input)) {
        return oldValue;
      }
      final parsed = double.tryParse(input.replaceAll(',', '.'));
      if (parsed == null || parsed > _maximumDiscountInput) {
        return oldValue;
      }
      return newValue;
    });
  }

  void _selectDiscountType(String value) {
    final parsed = double.tryParse(
      _discountController.text.trim().replaceAll(',', '.'),
    );
    setState(() {
      _selectedDiscountType = value;
      if (parsed != null && parsed > _maximumDiscountInput) {
        _discountController.clear();
      }
    });
  }

  double get _subtotalAmount {
    if (_selectedDocType == 'receipt') {
      return _paymentMethodsAmountTotal();
    }
    final subtotal = _itemsSubtotalBeforeTax - _discountAmount;
    return subtotal < 0 ? 0 : subtotal;
  }

  double get _vatAmount => _usesVat ? _subtotalAmount * _vatRate : 0.0;

  double get _totalBeforeRoundingAmount => _subtotalAmount + _vatAmount;

  double get _roundingAmount {
    if (_selectedDocType == 'receipt') return 0.0;
    if (!_roundTotalEnabled) return 0.0;
    final totalInAgorot = (_totalBeforeRoundingAmount * 100).round() / 100;
    final roundedTotal = totalInAgorot.floorToDouble();
    final reductionNeeded = totalInAgorot - roundedTotal;
    return reductionNeeded <= 0 ? 0.0 : reductionNeeded;
  }

  double get _totalAmount => _totalBeforeRoundingAmount - _roundingAmount;

  double get _signedTotalAmount =>
      _isNegativeReceipt ? -_totalAmount : _totalAmount;

  double get _signedRoundingAmount {
    return _roundingAmount == 0
        ? 0.0
        : (_isCreditNote ? _roundingAmount : -_roundingAmount);
  }

  double _signedItemTotal(InvoiceItem item) =>
      _isNegativeReceipt ? -_itemTotalAfterTax(item) : _itemTotalAfterTax(item);

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

  String _previewFileName() {
    if (_invoiceNumber.isNotEmpty) {
      return '$_invoiceNumber.pdf';
    }
    final datePart = intl.DateFormat('yyyy-MM-dd').format(_selectedInvoiceDate);
    return '${_labelForDocType(_selectedDocType).toLowerCase().replaceAll(' ', '_')}_$datePart.pdf';
  }

  String _formattedInvoiceDate() {
    return intl.DateFormat('dd-MM-yyyy').format(_selectedInvoiceDate);
  }

  String _formattedPaymentDueDate() {
    final dueDate = _selectedPaymentDueDate;
    if (dueDate == null) return '';
    return intl.DateFormat('dd-MM-yyyy').format(dueDate);
  }

  DateTime _defaultPaymentDueDate() {
    return _selectedInvoiceDate.add(const Duration(days: 30));
  }

  Map<String, dynamic>? get _creditNoteLegalData {
    if (!_isCreditNote) return null;
    final originalInvoiceNumber = _creditOriginalInvoiceNumberController.text
        .trim();
    final originalInvoiceDate = _creditOriginalInvoiceDateController.text
        .trim();
    final creditReason = _creditReasonController.text.trim();
    final receiptConfirmation = _creditReceiptConfirmationController.text
        .trim();
    if (originalInvoiceNumber.isEmpty &&
        originalInvoiceDate.isEmpty &&
        creditReason.isEmpty &&
        receiptConfirmation.isEmpty) {
      return null;
    }
    return {
      'originalInvoiceNumber': originalInvoiceNumber,
      'originalInvoiceDate': originalInvoiceDate,
      'creditReason': creditReason,
      'deliveryMethod': _selectedCreditDeliveryMethod,
      'receiptConfirmation': receiptConfirmation,
    };
  }

  // State for dealer logic
  String _dealerType = 'exempt';
  bool _hasLoadedDealerType = false;
  String? _businessId;
  String? _workerName;
  String? _verifiedBusinessLogoUrl;
  bool _isBusinessVerified = false;
  String _selectedDocType = 'quote';
  bool _isLoadingBusinessLogo = false;
  bool _invoiceLogoTouched = false;
  Uint8List? _businessLogoBytes;

  Map<String, String>? _cachedStrings;
  String? _lastLocale;
  late final Future<SubscriptionAccessState> _accessFuture;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _savedClientsStream;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (InvoiceBuilderVerificationSession.isVerifiedFor(currentUser?.uid)) {
      _isIdentityVerified = true;
      _acquireInvoiceBuilderLock();
    }
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
    _invoiceNumber = "";
    _clientNameFocusNode.addListener(_handleClientNameFocusChanged);
    if (currentUser != null) {
      _savedClientsStream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('clients')
          .snapshots();
    }

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
    if (widget.initialClientTaxId != null) {
      _clientIdController.text = widget.initialClientTaxId!;
    }
    if (widget.initialSavedClientId?.trim().isNotEmpty == true) {
      _selectedSavedClientId = widget.initialSavedClientId!.trim();
    }
    if (widget.initialClientExternalNumber?.trim().isNotEmpty == true) {
      _selectedSavedClientExternalNumber = widget.initialClientExternalNumber!
          .trim();
    }
    _invoiceDateController.text = _formattedInvoiceDate();
    _selectedPaymentDueDate = _defaultPaymentDueDate();
    _paymentDueDateController.text = _formattedPaymentDueDate();

    _applyInitialTemplate();
    final compatibleLinkedTypes = _linkableDocumentTypes(_selectedDocType);
    for (final data in widget.initialLinkedDocuments) {
      final document = _LinkedInvoiceDocument.fromMap(data);
      if (document.id.isNotEmpty &&
          (compatibleLinkedTypes.contains(document.docType) ||
              (_isNegativeReceipt && document.docType == 'receipt'))) {
        _linkedDocuments[document.id] = document;
      }
    }
    _prefillClientBusinessIdFromReceiver();
    _fetchWorkerInfo();
    _loadVatRate();
    _loadBankBranches();
  }

  String _normalizedIsraeliPhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('972')) {
      digits = '0${digits.substring(3)}';
    }
    return digits;
  }

  static const Map<String, Map<String, String>>
  _identityVerificationTranslations = {
    'en': {
      'page_title': 'Verify your identity',
      'heading': 'Verify it’s you',
      'description':
          'For your security, enter the phone number and password for this account before opening the invoice builder.',
      'phone': 'Phone number',
      'password': 'Password',
      'show_password': 'Show password',
      'hide_password': 'Hide password',
      'code_sent': 'A verification code was sent to your email address.',
      'email_code': 'Email verification code',
      'verify_code': 'Verify code and continue',
      'send_code': 'Send email code',
      'send_again': 'Send again',
      'send_again_in': 'Send again in {seconds}s',
      'enter_phone_password':
          'Enter your phone number and password to continue.',
      'password_sign_in_unavailable':
          'This account does not have password sign-in enabled.',
      'phone_mismatch': 'The phone number does not match this account.',
      'wrong_password': 'The password is incorrect. Please try again.',
      'identity_failed': 'We could not verify your identity.',
      'enter_six_digit_code': 'Enter the six-digit code from your email.',
      'session_ended': 'Your sign-in session has ended. Please sign in again.',
      'code_requested_recently':
          'A verification code was requested recently. Please wait one minute and try again.',
      'too_many_attempts':
          'Too many attempts. Please wait one minute and try again.',
      'session_expired':
          'Your sign-in session has expired. Please sign in again.',
      'account_not_confirmed':
          'We could not confirm that this account belongs to you.',
      'check_details': 'Please check your details and try again.',
      'email_missing':
          'No email address is attached to this Firebase Authentication account.',
      'email_not_verified':
          'Firebase Authentication reports that this account’s email is not verified. Verify it, then sign out and sign in again.',
      'verification_email_sent':
          'Firebase Authentication reports that this email is not verified. We sent a verification link to your email. Open it, then return and try again.',
      'verification_email_recently_sent':
          'A verification link was sent recently. Check your inbox or wait one minute before trying again.',
      'verification_email_delivery_failed':
          'We could not deliver the email-verification link. Please try again shortly.',
      'email_delivery_failed':
          'The email provider could not deliver the verification code. Please try again shortly.',
      'cannot_send_code':
          'We cannot send a verification code right now. Please try again shortly.',
      'code_expired':
          'This verification code is no longer valid. Request a new code.',
      'service_unavailable':
          'The verification service is temporarily unavailable. Please try again.',
      'send_failed':
          'We could not send the verification code. Please try again.',
      'code_failed': 'We could not verify that code. Please try again.',
    },
    'he': {
      'page_title': 'אימות זהות',
      'heading': 'נא לאמת את זהותך',
      'description':
          'למען אבטחתך, יש להזין את מספר הטלפון והסיסמה של חשבון זה לפני פתיחת מפיק המסמכים.',
      'phone': 'מספר טלפון',
      'password': 'סיסמה',
      'show_password': 'הצגת הסיסמה',
      'hide_password': 'הסתרת הסיסמה',
      'code_sent': 'קוד אימות נשלח לכתובת הדוא״ל שלך.',
      'email_code': 'קוד אימות מהדוא״ל',
      'verify_code': 'אימות הקוד והמשך',
      'send_code': 'שליחת קוד לדוא״ל',
      'send_again': 'שליחה מחדש',
      'send_again_in': 'שליחה מחדש בעוד {seconds} שנ׳',
      'enter_phone_password': 'יש להזין מספר טלפון וסיסמה כדי להמשיך.',
      'password_sign_in_unavailable':
          'התחברות באמצעות סיסמה אינה מופעלת בחשבון זה.',
      'phone_mismatch': 'מספר הטלפון אינו תואם לחשבון זה.',
      'wrong_password': 'הסיסמה שגויה. נא לנסות שוב.',
      'identity_failed': 'לא הצלחנו לאמת את זהותך.',
      'enter_six_digit_code': 'יש להזין את הקוד בן שש הספרות שנשלח בדוא״ל.',
      'session_ended': 'תוקף ההתחברות הסתיים. יש להתחבר מחדש.',
      'code_requested_recently':
          'קוד אימות נשלח לאחרונה. יש להמתין דקה ולנסות שוב.',
      'too_many_attempts': 'יותר מדי ניסיונות. יש להמתין דקה ולנסות שוב.',
      'session_expired': 'תוקף ההתחברות פג. יש להתחבר מחדש.',
      'account_not_confirmed': 'לא הצלחנו לאשר שהחשבון הזה שייך לך.',
      'check_details': 'יש לבדוק את הפרטים ולנסות שוב.',
      'email_missing':
          'לא משויכת כתובת דוא״ל לחשבון Firebase Authentication זה.',
      'email_not_verified':
          'Firebase Authentication מדווח שכתובת הדוא״ל של החשבון אינה מאומתת. יש לאמת אותה, להתנתק ולהתחבר מחדש.',
      'verification_email_sent':
          'כתובת הדוא״ל אינה מאומתת. שלחנו אליך קישור אימות בדוא״ל. יש לפתוח אותו, לחזור לאפליקציה ולנסות שוב.',
      'verification_email_recently_sent':
          'קישור אימות נשלח לאחרונה. יש לבדוק את תיבת הדוא״ל או להמתין דקה ולנסות שוב.',
      'verification_email_delivery_failed':
          'לא הצלחנו למסור את הקישור לאימות הדוא״ל. יש לנסות שוב בעוד זמן קצר.',
      'email_delivery_failed':
          'ספק הדוא״ל לא הצליח למסור את קוד האימות. יש לנסות שוב בעוד זמן קצר.',
      'cannot_send_code':
          'לא ניתן לשלוח קוד אימות כעת. יש לנסות שוב בעוד זמן קצר.',
      'code_expired': 'קוד האימות אינו בתוקף עוד. יש לבקש קוד חדש.',
      'service_unavailable':
          'שירות האימות אינו זמין זמנית. יש לנסות שוב מאוחר יותר.',
      'send_failed': 'לא הצלחנו לשלוח את קוד האימות. יש לנסות שוב.',
      'code_failed': 'לא הצלחנו לאמת את הקוד. יש לנסות שוב.',
    },
    'ar': {
      'page_title': 'التحقق من هويتك',
      'heading': 'تحقق من هويتك',
      'description':
          'لحماية حسابك، أدخل رقم الهاتف وكلمة المرور لهذا الحساب قبل فتح منشئ المستندات.',
      'phone': 'رقم الهاتف',
      'password': 'كلمة المرور',
      'show_password': 'إظهار كلمة المرور',
      'hide_password': 'إخفاء كلمة المرور',
      'code_sent': 'تم إرسال رمز تحقق إلى بريدك الإلكتروني.',
      'email_code': 'رمز التحقق من البريد الإلكتروني',
      'verify_code': 'تحقق من الرمز وتابع',
      'send_code': 'إرسال الرمز بالبريد الإلكتروني',
      'send_again': 'إرسال مرة أخرى',
      'send_again_in': 'إرسال مرة أخرى خلال {seconds} ث',
      'enter_phone_password': 'أدخل رقم هاتفك وكلمة المرور للمتابعة.',
      'password_sign_in_unavailable':
          'تسجيل الدخول بكلمة المرور غير مفعّل لهذا الحساب.',
      'phone_mismatch': 'رقم الهاتف لا يطابق هذا الحساب.',
      'wrong_password': 'كلمة المرور غير صحيحة. حاول مرة أخرى.',
      'identity_failed': 'تعذر التحقق من هويتك.',
      'enter_six_digit_code':
          'أدخل الرمز المكوّن من ستة أرقام من بريدك الإلكتروني.',
      'session_ended': 'انتهت جلسة تسجيل الدخول. سجّل الدخول مرة أخرى.',
      'code_requested_recently':
          'تم طلب رمز تحقق مؤخرًا. انتظر دقيقة ثم حاول مرة أخرى.',
      'too_many_attempts': 'محاولات كثيرة جدًا. انتظر دقيقة ثم حاول مرة أخرى.',
      'session_expired': 'انتهت صلاحية جلسة الدخول. سجّل الدخول مرة أخرى.',
      'account_not_confirmed': 'تعذر التأكد من أن هذا الحساب يخصك.',
      'check_details': 'تحقق من بياناتك وحاول مرة أخرى.',
      'email_missing':
          'لا يوجد عنوان بريد إلكتروني مرتبط بحساب Firebase Authentication هذا.',
      'email_not_verified':
          'يشير Firebase Authentication إلى أن بريد هذا الحساب غير موثّق. وثّقه، ثم سجّل الخروج والدخول مجددًا.',
      'verification_email_sent':
          'يشير Firebase Authentication إلى أن البريد غير موثّق. أرسلنا رابط توثيق إلى بريدك. افتحه، ثم عُد إلى التطبيق وحاول مجددًا.',
      'verification_email_recently_sent':
          'تم إرسال رابط توثيق مؤخرًا. تحقق من بريدك أو انتظر دقيقة ثم حاول مجددًا.',
      'verification_email_delivery_failed':
          'تعذر تسليم رابط توثيق البريد الإلكتروني. حاول مرة أخرى بعد قليل.',
      'email_delivery_failed':
          'تعذر على مزوّد البريد تسليم رمز التحقق. حاول مرة أخرى بعد قليل.',
      'cannot_send_code':
          'لا يمكن إرسال رمز تحقق الآن. حاول مرة أخرى بعد قليل.',
      'code_expired': 'لم يعد رمز التحقق صالحًا. اطلب رمزًا جديدًا.',
      'service_unavailable':
          'خدمة التحقق غير متاحة مؤقتًا. حاول مرة أخرى لاحقًا.',
      'send_failed': 'تعذر إرسال رمز التحقق. حاول مرة أخرى.',
      'code_failed': 'تعذر التحقق من الرمز. حاول مرة أخرى.',
    },
    'ru': {
      'page_title': 'Подтвердите личность',
      'heading': 'Подтвердите, что это вы',
      'description':
          'В целях безопасности введите номер телефона и пароль этого аккаунта перед открытием конструктора документов.',
      'phone': 'Номер телефона',
      'password': 'Пароль',
      'show_password': 'Показать пароль',
      'hide_password': 'Скрыть пароль',
      'code_sent': 'Код подтверждения отправлен на вашу электронную почту.',
      'email_code': 'Код из электронной почты',
      'verify_code': 'Подтвердить код и продолжить',
      'send_code': 'Отправить код на почту',
      'send_again': 'Отправить ещё раз',
      'send_again_in': 'Повторная отправка через {seconds} с',
      'enter_phone_password':
          'Введите номер телефона и пароль, чтобы продолжить.',
      'password_sign_in_unavailable':
          'Для этого аккаунта не включён вход по паролю.',
      'phone_mismatch': 'Номер телефона не соответствует этому аккаунту.',
      'wrong_password': 'Неверный пароль. Попробуйте ещё раз.',
      'identity_failed': 'Не удалось подтвердить вашу личность.',
      'enter_six_digit_code': 'Введите шестизначный код из электронной почты.',
      'session_ended': 'Сеанс завершён. Войдите в аккаунт снова.',
      'code_requested_recently':
          'Код подтверждения уже был запрошен. Подождите минуту и повторите попытку.',
      'too_many_attempts':
          'Слишком много попыток. Подождите минуту и попробуйте снова.',
      'session_expired': 'Срок сеанса истёк. Войдите в аккаунт снова.',
      'account_not_confirmed':
          'Не удалось подтвердить, что этот аккаунт принадлежит вам.',
      'check_details': 'Проверьте введённые данные и попробуйте снова.',
      'email_missing':
          'К этой учётной записи Firebase Authentication не привязан адрес электронной почты.',
      'email_not_verified':
          'Firebase Authentication сообщает, что почта этой учётной записи не подтверждена. Подтвердите её, затем выйдите и войдите снова.',
      'verification_email_sent':
          'Firebase Authentication сообщает, что почта не подтверждена. Мы отправили ссылку для подтверждения. Откройте её, вернитесь в приложение и повторите попытку.',
      'verification_email_recently_sent':
          'Ссылка для подтверждения уже отправлена. Проверьте почту или подождите минуту и повторите попытку.',
      'verification_email_delivery_failed':
          'Не удалось доставить ссылку для подтверждения почты. Попробуйте ещё раз позже.',
      'email_delivery_failed':
          'Почтовый провайдер не смог доставить код подтверждения. Попробуйте ещё раз позже.',
      'cannot_send_code':
          'Сейчас невозможно отправить код. Попробуйте немного позже.',
      'code_expired': 'Код больше не действителен. Запросите новый код.',
      'service_unavailable':
          'Служба подтверждения временно недоступна. Попробуйте позже.',
      'send_failed': 'Не удалось отправить код. Попробуйте снова.',
      'code_failed': 'Не удалось подтвердить код. Попробуйте снова.',
    },
    'am': {
      'page_title': 'ማንነትዎን ያረጋግጡ',
      'heading': 'እርስዎ መሆንዎን ያረጋግጡ',
      'description':
          'ለደህንነትዎ፣ የሰነድ አዘጋጁን ከመክፈትዎ በፊት የዚህን መለያ ስልክ ቁጥርና የይለፍ ቃል ያስገቡ።',
      'phone': 'ስልክ ቁጥር',
      'password': 'የይለፍ ቃል',
      'show_password': 'የይለፍ ቃሉን አሳይ',
      'hide_password': 'የይለፍ ቃሉን ደብቅ',
      'code_sent': 'የማረጋገጫ ኮድ ወደ ኢሜይልዎ ተልኳል።',
      'email_code': 'የኢሜይል ማረጋገጫ ኮድ',
      'verify_code': 'ኮዱን አረጋግጥና ቀጥል',
      'send_code': 'ኮድ ወደ ኢሜይል ላክ',
      'send_again': 'እንደገና ላክ',
      'send_again_in': 'ከ{seconds} ሰከንድ በኋላ እንደገና ላክ',
      'enter_phone_password': 'ለመቀጠል ስልክ ቁጥርዎንና የይለፍ ቃልዎን ያስገቡ።',
      'password_sign_in_unavailable': 'ለዚህ መለያ በይለፍ ቃል መግባት አልነቃም።',
      'phone_mismatch': 'ስልክ ቁጥሩ ከዚህ መለያ ጋር አይዛመድም።',
      'wrong_password': 'የይለፍ ቃሉ ትክክል አይደለም። እንደገና ይሞክሩ።',
      'identity_failed': 'ማንነትዎን ማረጋገጥ አልተቻለም።',
      'enter_six_digit_code': 'ከኢሜይልዎ የተላከውን ባለስድስት አሃዝ ኮድ ያስገቡ።',
      'session_ended': 'የመግቢያ ክፍለ ጊዜዎ አብቅቷል። እንደገና ይግቡ።',
      'code_requested_recently':
          'የማረጋገጫ ኮድ በቅርቡ ተጠይቋል። አንድ ደቂቃ ጠብቀው እንደገና ይሞክሩ።',
      'too_many_attempts': 'ብዙ ሙከራዎች ተደርገዋል። አንድ ደቂቃ ጠብቀው ይሞክሩ።',
      'session_expired': 'የመግቢያ ክፍለ ጊዜዎ ጊዜ አልፏል። እንደገና ይግቡ።',
      'account_not_confirmed': 'ይህ መለያ የእርስዎ መሆኑን ማረጋገጥ አልተቻለም።',
      'check_details': 'ዝርዝሮችዎን ያረጋግጡና እንደገና ይሞክሩ።',
      'email_missing': 'ከዚህ Firebase Authentication መለያ ጋር የተያያዘ ኢሜይል የለም።',
      'email_not_verified':
          'Firebase Authentication የዚህ መለያ ኢሜይል እንዳልተረጋገጠ ያሳያል። ኢሜይሉን ያረጋግጡ፣ ከዚያ ወጥተው እንደገና ይግቡ።',
      'verification_email_sent':
          'Firebase Authentication ኢሜይሉ እንዳልተረጋገጠ ያሳያል። የማረጋገጫ አገናኝ ወደ ኢሜይልዎ ልከናል። ይክፈቱትና ወደ መተግበሪያው ተመልሰው እንደገና ይሞክሩ።',
      'verification_email_recently_sent':
          'የማረጋገጫ አገናኝ በቅርቡ ተልኳል። ኢሜይልዎን ይፈትሹ ወይም አንድ ደቂቃ ጠብቀው ይሞክሩ።',
      'verification_email_delivery_failed':
          'የኢሜይል ማረጋገጫ አገናኙን ማድረስ አልቻልንም። ትንሽ ቆይተው ይሞክሩ።',
      'email_delivery_failed':
          'የኢሜይል አቅራቢው የማረጋገጫ ኮዱን ማድረስ አልቻለም። ትንሽ ቆይተው ይሞክሩ።',
      'cannot_send_code': 'አሁን የማረጋገጫ ኮድ መላክ አይቻልም። ትንሽ ቆይተው ይሞክሩ።',
      'code_expired': 'ይህ የማረጋገጫ ኮድ ከእንግዲህ አይሰራም። አዲስ ኮድ ይጠይቁ።',
      'service_unavailable': 'የማረጋገጫ አገልግሎቱ ለጊዜው አይገኝም። እንደገና ይሞክሩ።',
      'send_failed': 'የማረጋገጫ ኮዱን መላክ አልተቻለም። እንደገና ይሞክሩ።',
      'code_failed': 'ኮዱን ማረጋገጥ አልተቻለም። እንደገና ይሞክሩ።',
    },
  };

  Map<String, String> _identityStrings({bool listen = false}) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;
    return _identityVerificationTranslations[locale] ??
        _identityVerificationTranslations['en']!;
  }

  String _friendlyIdentityVerificationError(
    Object error, {
    required bool sendingCode,
  }) {
    final strings = _identityStrings();
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final reason = details is Map ? details['reason']?.toString() : null;
      switch (error.code) {
        case 'resource-exhausted':
          if (sendingCode && reason == 'verification-email-recently-sent') {
            return strings['verification_email_recently_sent']!;
          }
          return sendingCode
              ? strings['code_requested_recently']!
              : strings['too_many_attempts']!;
        case 'unauthenticated':
          return strings['session_expired']!;
        case 'permission-denied':
          return strings['account_not_confirmed']!;
        case 'invalid-argument':
          return sendingCode
              ? strings['check_details']!
              : strings['enter_six_digit_code']!;
        case 'failed-precondition':
          if (!sendingCode) return strings['code_expired']!;
          return switch (reason) {
            'email-missing' => strings['email_missing']!,
            'email-not-verified' => strings['email_not_verified']!,
            'verification-email-sent' => strings['verification_email_sent']!,
            _ => strings['cannot_send_code']!,
          };
        case 'deadline-exceeded':
          return sendingCode
              ? strings['service_unavailable']!
              : strings['code_expired']!;
        case 'unavailable':
        case 'internal':
          if (sendingCode && reason == 'verification-email-delivery-failed') {
            return strings['verification_email_delivery_failed']!;
          }
          if (sendingCode && reason == 'email-delivery-failed') {
            return strings['email_delivery_failed']!;
          }
          return strings['service_unavailable']!;
        default:
          return sendingCode
              ? strings['send_failed']!
              : strings['code_failed']!;
      }
    }

    if (error is StateError) {
      return error.message.toString();
    }

    return sendingCode ? strings['send_failed']! : strings['code_failed']!;
  }

  void _startIdentityResendCooldown() {
    _identityResendTimer?.cancel();
    final availableAt = DateTime.now().add(const Duration(minutes: 1));
    if (!mounted) return;
    setState(() => _identityResendSecondsRemaining = 60);
    _identityResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = availableAt.difference(DateTime.now()).inSeconds + 1;
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _identityResendSecondsRemaining = 0);
        return;
      }
      setState(() => _identityResendSecondsRemaining = remaining);
    });
  }

  Future<void> _resendInvoiceBuilderEmailCode() async {
    if (_isVerifyingIdentity || _identityResendSecondsRemaining > 0) return;
    setState(() {
      _isVerifyingIdentity = true;
      _identityVerificationError = null;
    });
    try {
      await _functions
          .httpsCallable('sendInvoiceBuilderEmailCode')
          .call<void>();
      if (!mounted) return;
      _identityEmailCodeController.clear();
      setState(() => _isVerifyingIdentity = false);
      _startIdentityResendCooldown();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: true,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: true,
        );
      });
    }
  }

  Future<void> _verifyIdentityForInvoiceBuilder() async {
    if (_isVerifyingIdentity) return;
    final strings = _identityStrings();

    if (_isEmailCodeSent) {
      await _verifyInvoiceBuilderEmailCode();
      return;
    }

    final enteredPhone = _normalizedIsraeliPhone(
      _identityPhoneController.text.trim(),
    );
    final password = _identityPasswordController.text;
    if (enteredPhone.isEmpty || password.isEmpty) {
      setState(() {
        _identityVerificationError = strings['enter_phone_password']!;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email?.trim();
    final supportsPassword =
        user?.providerData.any(
          (provider) => provider.providerId == 'password',
        ) ??
        false;
    if (user == null || email == null || email.isEmpty || !supportsPassword) {
      setState(() {
        _identityVerificationError = strings['password_sign_in_unavailable']!;
      });
      return;
    }

    setState(() {
      _isVerifyingIdentity = true;
      _identityVerificationError = null;
    });

    try {
      final profileData = await ProfileDocumentService.load(user.uid);
      final registeredPhones = <String>{
        user.phoneNumber ?? '',
        (profileData['phone'] ?? '').toString(),
        (profileData['phoneNumber'] ?? '').toString(),
      }.map(_normalizedIsraeliPhone).where((phone) => phone.isNotEmpty).toSet();

      if (registeredPhones.isEmpty ||
          !registeredPhones.contains(enteredPhone)) {
        throw StateError(strings['phone_mismatch']!);
      }

      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      await _functions
          .httpsCallable('sendInvoiceBuilderEmailCode')
          .call<void>();
      if (!mounted) return;
      _identityPasswordController.clear();
      setState(() {
        _isVerifyingIdentity = false;
        _isEmailCodeSent = true;
      });
      _startIdentityResendCooldown();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError =
            error.code == 'wrong-password' || error.code == 'invalid-credential'
            ? strings['wrong_password']!
            : strings['identity_failed']!;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: true,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: true,
        );
      });
    }
  }

  Future<void> _verifyInvoiceBuilderEmailCode() async {
    final strings = _identityStrings();
    final code = _identityEmailCodeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _identityVerificationError = strings['enter_six_digit_code']!;
      });
      return;
    }

    setState(() {
      _isVerifyingIdentity = true;
      _identityVerificationError = null;
    });
    try {
      await _functions
          .httpsCallable('verifyInvoiceBuilderEmailCode')
          .call<void>({'code': code});
      if (!mounted) return;
      _identityEmailCodeController.clear();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw StateError(strings['session_ended']!);
      }
      InvoiceBuilderVerificationSession.markVerified(userId);
      _identityResendTimer?.cancel();
      setState(() {
        _isIdentityVerified = true;
        _isVerifyingIdentity = false;
        _identityResendSecondsRemaining = 0;
      });
      unawaited(_acquireInvoiceBuilderLock());
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: false,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifyingIdentity = false;
        _identityVerificationError = _friendlyIdentityVerificationError(
          error,
          sendingCode: false,
        );
      });
    }
  }

  void _temporarilySkipIdentityVerification() {
    if (!kDebugMode || _isVerifyingIdentity) return;
    _identityResendTimer?.cancel();
    setState(() {
      _isIdentityVerified = true;
      _isAcquiringLock = true;
      _isVerifyingIdentity = false;
      _identityVerificationError = null;
      _identityResendSecondsRemaining = 0;
    });
    unawaited(_acquireInvoiceBuilderLock());
  }

  Widget _buildIdentityVerificationGate(BuildContext context) {
    final strings = _identityStrings(listen: true);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(strings['page_title']!),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1976D2),
        elevation: 0,
        actions: [
          if (kDebugMode)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: 'Temporary: skip identity verification',
              onPressed: _isVerifyingIdentity
                  ? null
                  : _temporarilySkipIdentityVerification,
              icon: const Icon(Icons.bug_report_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_person_outlined,
                        color: Color(0xFF1976D2),
                        size: 42,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        strings['heading']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        strings['description']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _identityPhoneController,
                        enabled: !_isVerifyingIdentity,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: strings['phone']!,
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _identityPasswordController,
                        enabled: !_isVerifyingIdentity && !_isEmailCodeSent,
                        obscureText: _obscureIdentityPassword,
                        onSubmitted: (_) => _verifyIdentityForInvoiceBuilder(),
                        decoration: InputDecoration(
                          labelText: strings['password']!,
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscureIdentityPassword
                                ? strings['show_password']!
                                : strings['hide_password']!,
                            icon: Icon(
                              _obscureIdentityPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: _isVerifyingIdentity
                                ? null
                                : () => setState(
                                    () => _obscureIdentityPassword =
                                        !_obscureIdentityPassword,
                                  ),
                          ),
                        ),
                      ),
                      if (_isEmailCodeSent) ...[
                        const SizedBox(height: 16),
                        Text(
                          strings['code_sent']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _identityEmailCodeController,
                          enabled: !_isVerifyingIdentity,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          onSubmitted: (_) => _verifyInvoiceBuilderEmailCode(),
                          decoration: InputDecoration(
                            labelText: strings['email_code']!,
                            prefixIcon: const Icon(
                              Icons.mark_email_read_outlined,
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              !_isVerifyingIdentity &&
                                  _identityResendSecondsRemaining == 0
                              ? _resendInvoiceBuilderEmailCode
                              : null,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            _identityResendSecondsRemaining > 0
                                ? strings['send_again_in']!.replaceFirst(
                                    '{seconds}',
                                    '$_identityResendSecondsRemaining',
                                  )
                                : strings['send_again']!,
                          ),
                        ),
                      ],
                      if (_identityVerificationError != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 21,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _identityVerificationError!,
                                  style: const TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isVerifyingIdentity
                            ? null
                            : _verifyIdentityForInvoiceBuilder,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isVerifyingIdentity
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isEmailCodeSent
                                    ? strings['verify_code']!
                                    : strings['send_code']!,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadBankBranches() async {
    try {
      final xmlText = await rootBundle.loadString('assets/snifim_he.xml');
      final branchesByBankId = await compute(_parseBankBranches, xmlText);

      if (!mounted) return;
      setState(() {
        _branchesByBankId
          ..clear()
          ..addAll(branchesByBankId);
        _isLoadingBankBranches = false;
      });
    } catch (error, stackTrace) {
      dev.log(
        'Unable to load bank branches',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _isLoadingBankBranches = false);
    }
  }

  Future<void> _acquireInvoiceBuilderLock() async {
    _invoiceBuilderLock.onLeaseLost = _handleInvoiceBuilderLockLost;
    final lockResult = await _invoiceBuilderLock.acquire();
    if (!mounted) return;
    if (lockResult == InvoiceBuilderLockAcquireResult.acquired) {
      setState(() {
        _isAcquiringLock = false;
        _hasInvoiceBuilderLock = true;
      });
      return;
    }

    setState(() => _isAcquiringLock = false);
    _showInvoiceBuilderLockedMessage(
      unavailable: lockResult == InvoiceBuilderLockAcquireResult.unavailable,
    );
  }

  void _handleInvoiceBuilderLockLost(InvoiceBuilderLockLossReason reason) {
    if (!mounted || _lockLostDialogShown) return;
    setState(() => _hasInvoiceBuilderLock = false);
    _showInvoiceBuilderLockedMessage(
      unavailable: reason == InvoiceBuilderLockLossReason.unavailable,
    );
  }

  Future<void> _showInvoiceBuilderLockedMessage({
    bool unavailable = false,
  }) async {
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
          unavailable
              ? strings['invoice_builder_unavailable_title']!
              : strings['invoice_builder_locked_title']!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        content: Text(
          unavailable
              ? strings['invoice_builder_unavailable']!
              : strings['invoice_builder_locked']!,
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
    _lockLostDialogShown = false;
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

    // Receipts record payments, not service-item rows.
    if (_selectedDocType == 'receipt') return;

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
    final today = DateUtils.dateOnly(DateTime.now());
    final currentInvoiceDate = DateUtils.dateOnly(_selectedInvoiceDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: currentInvoiceDate.isAfter(today)
          ? today
          : currentInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedInvoiceDate = picked;
      _invoiceDateController.text = _formattedInvoiceDate();
      if (!_hasCustomPaymentDueDate) {
        _selectedPaymentDueDate = _defaultPaymentDueDate();
        _paymentDueDateController.text = _formattedPaymentDueDate();
      } else if (_selectedPaymentDueDate != null &&
          DateUtils.dateOnly(
            _selectedPaymentDueDate!,
          ).isBefore(_selectedInvoiceDate)) {
        _selectedPaymentDueDate = _selectedInvoiceDate;
        _paymentDueDateController.text = _formattedPaymentDueDate();
      }
    });
  }

  Future<void> _pickPaymentDueDate() async {
    final earliestDueDate = DateUtils.dateOnly(_selectedInvoiceDate);
    final preferredInitialDate =
        _selectedPaymentDueDate ??
        _selectedInvoiceDate.add(const Duration(days: 30));
    final initialDate =
        DateUtils.dateOnly(preferredInitialDate).isBefore(earliestDueDate)
        ? earliestDueDate
        : DateUtils.dateOnly(preferredInitialDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliestDueDate,
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
      final userData = await ProfileDocumentService.load(receiverId);
      final verificationDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .collection('verification_info')
          .doc('latest')
          .get();
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
        final workerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (workerDoc.exists && mounted) {
          final workerData = workerDoc.data();
          final profileData = await ProfileDocumentService.load(user.uid);
          if (!mounted) return;
          setState(() {
            _isBusinessVerified = workerData?['isapproved'] ?? false;
            _workerName = profileData['name']?.toString().trim();
          });

          // Fetch from verification_info sub-collection for business details
          final vInfoDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('verification_info')
              .doc('latest')
              .get();
          if (!mounted) return;
          final vData = vInfoDoc.data();
          final businessLogoUrl = (vData?['businessLogoUrl'] ?? '')
              .toString()
              .trim();
          final dealerType = (vData?['dealerType'] ?? 'exempt')
              .toString()
              .trim()
              .toLowerCase();
          setState(() {
            _businessId = vData?['businessId']?.toString();
            _dealerType = dealerType;
            _hasLoadedDealerType = true;
            if (!_isLicensedDealerType) {
              _selectedPriceTaxMode = 'after_tax';
            }
            _verifiedBusinessLogoUrl = businessLogoUrl.isEmpty
                ? null
                : businessLogoUrl;

            if (!_isLicensedDealerType &&
                _licensedOnlyDocumentTypes.contains(_selectedDocType)) {
              _selectedDocType = 'quote';
              _linkedDocuments.clear();
              _currentDocumentCounter = null;
              _invoiceNumber = '';
            } else if (widget.initialDocType == null ||
                widget.initialDocType!.isEmpty) {
              if (_isBusinessVerified && _isLicensedDealerType) {
                _selectedDocType = 'invoice_receipt';
              } else {
                _selectedDocType = 'quote';
              }
            }
          });
          if (vInfoDoc.exists) {
            await _loadDefaultBusinessLogo();
          }
          await _loadCurrentDocumentNumber(promptIfMissing: true);
        }
      } catch (e) {
        dev.log("Error fetching worker info: $e");
      } finally {
        if (mounted && !_hasLoadedDealerType) {
          setState(() => _hasLoadedDealerType = true);
        }
      }
    } else if (mounted) {
      setState(() => _hasLoadedDealerType = true);
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
    _identityResendTimer?.cancel();
    _identityPhoneController.dispose();
    _identityPasswordController.dispose();
    _identityEmailCodeController.dispose();
    _clientNameFocusNode.removeListener(_handleClientNameFocusChanged);
    _clientNameController.dispose();
    _clientNameFocusNode.dispose();
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
    _startingDocumentNumberController.dispose();
    for (final methodEntry in _paymentMethods) {
      methodEntry.dispose();
    }
    super.dispose();
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
    return _items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final totalAmount = _itemTotalBeforeTax(item);

      return {
        'index': index + 1,
        'description': item.description,
        'quantity': item.quantity,
        'price_per_unit': _unitPriceBeforeTax(item),
        'total_amount': totalAmount,
        'vat_rate': _vatRate * 100,
        'vat_amount': totalAmount * _vatRate,
      };
    }).toList();
  }

  Map<String, dynamic> _documentLogoServerPayload() {
    if (!_invoiceLogoTouched) {
      return const {'documentLogoMode': 'default'};
    }
    final bytes = _businessLogoBytes;
    if (bytes == null || bytes.isEmpty) {
      return const {'documentLogoMode': 'none'};
    }
    if (bytes.length > 3 * 1024 * 1024) {
      throw StateError('The selected document logo must be smaller than 3 MB.');
    }
    return {
      'documentLogoMode': 'inline',
      'documentLogoBase64': base64Encode(bytes),
    };
  }

  Future<_ServerDocumentResult> _requestTaxAuthorityAllocation() async {
    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final businessVatNumber = _digitsOnly(_businessId);
    final customerVatNumber = _digitsOnly(_clientIdController.text);
    if (businessVatNumber.isEmpty || customerVatNumber.isEmpty) {
      throw StateError(strings['tax_authority_missing_tax_ids']!);
    }

    final invoiceDocId = _invoiceDocIdFor(_selectedDocType, _invoiceNumber);
    final invoicePayload = {
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
    };
    final createDraft = _functions.httpsCallable('createTaxInvoiceDraft');
    final requestAllocation = _functions.httpsCallable(
      'requestTaxInvoiceAllocation',
    );
    final HttpsCallableResult<Map<String, dynamic>> result;
    try {
      final draftResult = await createDraft.call<Map<String, dynamic>>({
        'invoiceDocId': invoiceDocId,
        'invoice': invoicePayload,
        'presentation': {
          'clientAddress': _clientAddressController.text.trim(),
          'clientPhone': _clientPhoneController.text.trim(),
          'clientEmail': _clientEmailController.text.trim(),
          'externalClientNumber': _selectedSavedClientExternalNumber ?? '',
          if (_selectedSavedClientId != null)
            'savedClientId': _selectedSavedClientId,
          'priceTaxModeDefault': _selectedPriceTaxMode,
          'roundTotalEnabled': _roundTotalEnabled,
          if (_selectedPaymentDueDate != null)
            'paymentDueDate': intl.DateFormat(
              'yyyy-MM-dd',
            ).format(_selectedPaymentDueDate!),
          'paymentMethods': _showsPaymentMethodSection
              ? _paymentMethodsForStorage()
              : const <Map<String, dynamic>>[],
          ..._documentLogoServerPayload(),
        },
      });
      final draftId = draftResult.data['draftId']?.toString().trim();
      if (draftId == null || draftId.isEmpty) {
        throw StateError(strings['tax_authority_allocation_failed']!);
      }
      final existingStatus = draftResult.data['status']?.toString().trim();
      final existingAllocation = draftResult.data['allocation'];
      final existingDecision = draftResult.data['decision']?.toString().trim();
      if (existingDecision == 'reverse_charge') {
        return await _resumeReverseChargeTaxInvoice(draftId);
      }
      if (existingStatus == 'continued_without_allocation' ||
          (existingStatus == 'finalized' && existingAllocation == null)) {
        return await _finalizeContinuedTaxInvoice(draftId);
      }
      result = await requestAllocation.call<Map<String, dynamic>>({
        'draftId': draftId,
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
    if (data['decisionRequired'] == true) {
      return _resolveTaxAuthorityDecision(
        draftId: invoiceDocId,
        errors: data['errors'],
      );
    }
    final confirmationNumber = data['confirmationNumber']?.toString().trim();
    final reservationValue = data['reservation'];
    final reservation = reservationValue is Map
        ? Map<String, dynamic>.from(reservationValue)
        : const <String, dynamic>{};
    final payloadHash = data['payloadHash']?.toString().trim() ?? '';
    final documentValue = data['document'];
    final document = documentValue is Map
        ? Map<String, dynamic>.from(documentValue)
        : const <String, dynamic>{};

    if (data['approved'] != true ||
        confirmationNumber == null ||
        confirmationNumber.isEmpty ||
        reservation.isEmpty ||
        payloadHash.isEmpty ||
        document.isEmpty) {
      throw StateError(strings['tax_authority_allocation_failed']!);
    }

    return _ServerDocumentResult(document: document);
  }

  Future<_ServerDocumentResult> _finalizeContinuedTaxInvoice(
    String draftId,
  ) async {
    final callable = _functions.httpsCallable('finalizeTaxInvoiceDocument');
    final result = await callable.call<Map<String, dynamic>>({
      'draftId': draftId,
    });
    final documentValue = result.data['document'];
    final document = documentValue is Map
        ? Map<String, dynamic>.from(documentValue)
        : const <String, dynamic>{};
    if (result.data['finalized'] != true || document.isEmpty) {
      throw StateError(
        'The invoice could not be finalized without an allocation number.',
      );
    }
    return _ServerDocumentResult(document: document);
  }

  Future<_ServerDocumentResult> _resumeReverseChargeTaxInvoice(
    String draftId,
  ) async {
    final callable = _functions.httpsCallable('submitTaxInvoiceDecision');
    final result = await callable.call<Map<String, dynamic>>({
      'draftId': draftId,
      'decision': 'reverse_charge',
    });
    final documentValue = result.data['document'];
    final document = documentValue is Map
        ? Map<String, dynamic>.from(documentValue)
        : const <String, dynamic>{};
    if (result.data['accepted'] != true || document.isEmpty) {
      throw StateError(
        'The reverse-charge invoice could not be safely resumed.',
      );
    }
    return _ServerDocumentResult(document: document);
  }

  Future<Map<String, dynamic>?> _collectReverseChargeEvidence({
    required bool isHebrew,
  }) async {
    var dealerVerified = false;
    var customerConsented = false;
    String? consentMethod;
    final customerName = _clientNameController.text.trim();
    final customerVat = _digitsOnly(_clientIdController.text);
    const registryUrl = 'https://www.gov.il/he/service/vat-apply-online';
    final methods = <String, String>{
      'email': isHebrew ? 'דוא״ל' : 'Email',
      'signed_document': isHebrew ? 'מסמך חתום' : 'Signed document',
      'whatsapp': 'WhatsApp',
      'phone': isHebrew ? 'טלפון' : 'Phone',
      'other': isHebrew ? 'אחר' : 'Other',
    };

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canContinue =
              dealerVerified && customerConsented && consentMethod != null;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              isHebrew ? 'אישור היפוך חיוב' : 'Confirm reverse charge',
              textAlign: TextAlign.center,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName.isEmpty ? '—' : customerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isHebrew
                              ? 'מספר עוסק: $customerVat'
                              : 'VAT number: $customerVat',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isHebrew
                        ? 'יש לבדוק באתר הרשמי שהלקוח רשום כעוסק מורשה ושהשם תואם.'
                        : 'Use the official registry to confirm that the customer is a licensed dealer and the registered name matches.',
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse(registryUrl);
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw StateError('Could not open the Tax Authority.');
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(
                      isHebrew
                          ? 'פתיחת בדיקת עוסק ברשות המסים'
                          : 'Open Tax Authority dealer lookup',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: dealerVerified,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setDialogState(() => dealerVerified = value == true),
                    title: Text(
                      isHebrew
                          ? 'בדקתי ואישרתי שהלקוח הוא עוסק מורשה פעיל.'
                          : 'I checked and confirmed that the customer is an active licensed dealer.',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: customerConsented,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setDialogState(() => customerConsented = value == true),
                    title: Text(
                      isHebrew
                          ? 'אני מאשר שהלקוח הסכים לקבל על עצמו את דיווח המע״מ.'
                          : 'I confirm that the customer agreed to report the VAT.',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: consentMethod,
                    decoration: InputDecoration(
                      labelText: isHebrew
                          ? 'כיצד התקבלה הסכמת הלקוח?'
                          : 'How did the customer consent?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: methods.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setDialogState(() => consentMethod = value),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isHebrew
                        ? 'לאחר האישור, החשבונית המקורית תבוטל ותופק חשבונית חדשה בשיעור מע״מ אפס. הלקוח יפיק חשבונית עצמית במערכת שלו.'
                        : 'After approval, the original invoice will be cancelled and a new zero-VAT invoice will be issued. The customer creates the self-invoice in their own system.',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(isHebrew ? 'חזרה' : 'Back'),
              ),
              FilledButton(
                onPressed: canContinue
                    ? () => Navigator.pop(dialogContext, {
                        'dealerVerificationConfirmed': true,
                        'customerConsentConfirmed': true,
                        'consentMethod': consentMethod,
                      })
                    : null,
                child: Text(
                  isHebrew
                      ? 'המשך להיפוך חיוב'
                      : 'Continue with reverse charge',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_ServerDocumentResult> _resolveTaxAuthorityDecision({
    required String draftId,
    required dynamic errors,
  }) async {
    if (!mounted) {
      throw StateError('The invoice is awaiting a Tax Authority decision.');
    }
    final languageCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isHebrew = languageCode == 'he';
    final isRtl = isHebrew || languageCode == 'ar';
    final authorityMessage = _taxAuthorityErrorMessageFromDetails(errors);
    final decision = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              10,
              22,
              22 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: IconButton(
                          tooltip: isHebrew ? 'סגירה' : 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 36,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isHebrew
                      ? 'לא התקבל מספר הקצאה'
                      : 'No allocation number was issued',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isHebrew
                      ? 'רשות המסים עיכבה את החשבונית. בחרו כיצד להמשיך.'
                      : 'The Tax Authority held this invoice. Choose how you want to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                if (authorityMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            authorityMessage,
                            style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, 'further_objection'),
                  icon: const Icon(Icons.support_agent_rounded),
                  label: Text(isHebrew ? 'בקשת שימוע' : 'Request a hearing'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'continue'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    isHebrew
                        ? 'המשך ללא מספר הקצאה'
                        : 'Continue without an allocation number',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: const Color(0xFFB45309),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHebrew
                      ? 'החשבונית תופק ללא מספר הקצאה.'
                      : 'The invoice will be issued without an allocation number.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(sheetContext, 'reverse_charge'),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(
                    isHebrew
                        ? 'היפוך חיוב – הלקוח מדווח את המע״מ'
                        : 'Reverse charge — customer reports VAT',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: const Color(0xFF6D28D9),
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHebrew
                      ? 'זמין רק ללקוח עוסק מורשה שהסכים להיפוך החיוב.'
                      : 'Available only when the customer is a licensed dealer and has agreed.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(
                    isHebrew
                        ? 'ביטול והפקת חשבונית מס זיכוי'
                        : 'Cancel and create a Tax Invoice Credit',
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: const Color(0xFFB91C1C),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  isHebrew
                      ? 'החשבונית המקורית תישמר, ולאחר מכן תופק חשבונית מס זיכוי אוטומטית.'
                      : 'The original invoice will be saved, then a linked Tax Invoice Credit will be generated automatically.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (decision == null || !mounted) {
      throw StateError(
        isHebrew
            ? 'החשבונית נשמרה וממתינה להחלטה.'
            : 'The invoice remains saved and is awaiting a decision.',
      );
    }

    if (decision == 'cancel') {
      final hasCreditCounter = await _ensureCancellationCreditNoteCounter();
      if (!hasCreditCounter) {
        throw StateError(
          isHebrew
              ? 'הביטול לא נשלח. יש להגדיר מספר התחלתי לחשבונית מס זיכוי כדי להמשיך.'
              : 'The cancellation was not submitted. Set the starting Tax Invoice Credit number to continue.',
        );
      }
    }

    Map<String, dynamic>? reverseChargeEvidence;
    if (decision == 'reverse_charge') {
      reverseChargeEvidence = await _collectReverseChargeEvidence(
        isHebrew: isHebrew,
      );
      if (reverseChargeEvidence == null) {
        throw StateError(
          isHebrew
              ? 'היפוך החיוב לא נשלח. החשבונית עדיין ממתינה לבחירה.'
              : 'Reverse charge was not submitted. The invoice is still awaiting a decision.',
        );
      }
      final hasCreditCounter = await _ensureCancellationCreditNoteCounter();
      if (!hasCreditCounter) {
        throw StateError(
          isHebrew
              ? 'היפוך החיוב לא נשלח. יש להגדיר מספר התחלתי לחשבונית מס זיכוי.'
              : 'Reverse charge was not submitted. Set the starting Tax Invoice Credit number first.',
        );
      }
    }

    final callable = _functions.httpsCallable('submitTaxInvoiceDecision');
    final result = await callable.call<Map<String, dynamic>>({
      'draftId': draftId,
      'decision': decision,
      ...?(reverseChargeEvidence == null
          ? null
          : {'reverseChargeEvidence': reverseChargeEvidence}),
    });
    if (result.data['accepted'] != true) {
      throw StateError(
        isHebrew
            ? 'רשות המסים לא אישרה את הבחירה.'
            : 'The Tax Authority did not accept the selected action.',
      );
    }
    if (decision == 'continue' ||
        decision == 'cancel' ||
        decision == 'reverse_charge') {
      final documentValue = result.data['document'];
      final document = documentValue is Map
          ? Map<String, dynamic>.from(documentValue)
          : const <String, dynamic>{};
      if (document.isEmpty) {
        if (decision == 'cancel' || decision == 'reverse_charge') {
          throw StateError(
            isHebrew
                ? 'החשבונית בוטלה, אך לא ניתן היה להפיק את החשבונית ואת חשבונית מס הזיכוי.'
                : 'The cancellation was accepted, but the invoice and Tax Invoice Credit could not be generated.',
          );
        }
        return await _finalizeContinuedTaxInvoice(draftId);
      }
      if (decision == 'cancel' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isHebrew
                  ? 'החשבונית נשמרה וחשבונית מס זיכוי נוצרה אוטומטית.'
                  : 'The invoice was saved and a Tax Invoice Credit was created automatically.',
            ),
          ),
        );
      }
      if (decision == 'reverse_charge' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isHebrew
                  ? 'החשבונית המקורית בוטלה, וחשבונית חדשה בשיעור מע״מ אפס הופקה.'
                  : 'The original invoice was cancelled and a new zero-VAT invoice was issued.',
            ),
          ),
        );
      }
      return _ServerDocumentResult(document: document);
    }
    throw StateError(
      isHebrew
          ? 'בקשת השימוע נרשמה. החשבונית ממתינה לבדיקה.'
          : 'The hearing request was recorded. The invoice is awaiting review.',
    );
  }

  Map<String, dynamic> _serverDocumentRequestPayload() {
    return {
      'operationId': _serverDocumentOperationId,
      'docType': _selectedDocType,
      'documentNumber': _invoiceNumber.trim(),
      'sequenceNumber': _currentDocumentCounter,
      'date': _invoiceDateIsoValue(),
      if (_selectedPaymentDueDate != null)
        'paymentDueDate': intl.DateFormat(
          'yyyy-MM-dd',
        ).format(_selectedPaymentDueDate!),
      'client': {
        'id': _clientIdController.text.trim(),
        'name': _clientNameController.text.trim(),
        'address': _clientAddressController.text.trim(),
        'phone': _clientPhoneController.text.trim(),
        'email': _clientEmailController.text.trim(),
        'externalClientNumber': _selectedSavedClientExternalNumber ?? '',
        if (_selectedSavedClientId != null)
          'savedClientId': _selectedSavedClientId,
      },
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
          .toList(growable: false),
      'discountAmount': _manualDiscountAmount,
      'roundTotalEnabled': _roundTotalEnabled,
      'priceTaxModeDefault': _selectedPriceTaxMode,
      'notes': _notesController.text.trim(),
      'paymentMethods': _showsPaymentMethodSection
          ? _paymentMethods
                .map((entry) => entry.toMap())
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
      'linkedDocuments': _linkedDocumentReferences,
      'sourceInvoiceNumber': widget.sourceInvoiceNumber,
      'sourceInvoiceDocId': widget.sourceInvoiceDocId,
      'isNegativeReceipt': _isNegativeReceipt,
      'cancellationSourceDocumentId': widget.cancellationSourceDocumentId,
      'cancellationSourceDocumentNumber':
          widget.cancellationSourceDocumentNumber,
      if (_creditNoteLegalData != null) 'creditNoteLegal': _creditNoteLegalData,
      ..._documentLogoServerPayload(),
    };
  }

  Future<Uint8List> _createServerDocumentPreview() async {
    final callable = _functions.httpsCallable('previewServerDocument');
    final result = await callable.call<Map<String, dynamic>>(
      _serverDocumentRequestPayload(),
    );
    final encoded = result.data['pdfBase64']?.toString().trim();
    if (result.data['previewOnly'] != true ||
        encoded == null ||
        encoded.isEmpty) {
      throw StateError('The server did not return a document preview.');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
      throw StateError('The server returned an invalid document preview.');
    }
    return bytes;
  }

  Future<_ServerDocumentResult> _createServerDocument() async {
    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final callable = _functions.httpsCallable('createServerDocument');
    final result = await callable.call<Map<String, dynamic>>(
      _serverDocumentRequestPayload(),
    );
    final documentValue = result.data['document'];
    final document = documentValue is Map
        ? Map<String, dynamic>.from(documentValue)
        : const <String, dynamic>{};
    if (result.data['finalized'] != true || document.isEmpty) {
      throw StateError(
        strings['tax_authority_allocation_failed'] ??
            'The document could not be generated.',
      );
    }
    return _ServerDocumentResult(document: document);
  }

  Future<_ServerDocumentResult> _finalizeDocumentOnServer({
    bool showAllocationFeedback = true,
  }) async {
    if (!_requiresTaxAuthorityAllocation) {
      return _createServerDocument();
    }

    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final connected = await _isTaxAuthorityConnected();
    if (!connected) {
      throw StateError(strings['tax_authority_not_connected']!);
    }
    if (showAllocationFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings['tax_authority_requesting_allocation']!),
        ),
      );
    }
    return _requestTaxAuthorityAllocation();
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
    });
  }

  void _removeBusinessLogo() {
    setState(() {
      _invoiceLogoTouched = true;
      _businessLogoBytes = null;
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
              'יוצר החשבוניות פתוח כעת במכשיר אחר. סגרו אותו במכשיר האחר, המתינו מספר שניות ולאחר מכן נסו שוב.',
          'invoice_builder_locked_action': 'חזרה',
          'ok': 'אישור',
          'client_info': 'פרטי הלקוח:',
          'client_name': 'שם הלקוח',
          'client_id': 'מס\' עוסק / ת.ז. / ח.פ.',
          'client_address': 'כתובת הלקוח',
          'client_phone': 'טלפון הלקוח',
          'client_email': 'דוא״ל הלקוח',
          'linked_documents': 'מסמך מקושר',
          'linked_documents_title': 'בחירת מסמך לקישור',
          'linked_documents_selected': 'מסמך מקושר',
          'linked_documents_empty': 'אין מסמכים מתאימים ללקוח זה.',
          'linked_documents_load_failed': 'לא ניתן לטעון את המסמכים.',
          'link_documents_action': 'קישור מסמך',
          'linked_documents_helper':
              'בחרו מסמך אחד או יותר לקישור למסמך הנוכחי.',
          'linked_documents_search': 'חיפוש לפי סוג, מספר, תאריך או סכום',
          'linked_documents_count': '{count} נבחרו',
          'linked_documents_no_results': 'לא נמצאו מסמכים התואמים לחיפוש.',
          'select_all': 'בחר הכל',
          'clear_selection': 'נקה',
          'retry': 'נסה שוב',
          'link_documents_action_count': 'קישור ({count})',
          'add_client': 'הוסף לקוח',
          'save_client': 'שמור לקוח',
          'client_added': 'הלקוח נוסף ונבחר.',
          'client_save_failed': 'לא ניתן לשמור את הלקוח. נסה שוב.',
          'invalid_email': 'יש להזין כתובת דוא״ל תקינה.',
          'external_client_number': 'מס׳ לקוח בהנה״ח חיצונית',
          'external_client_number_hint': '1–10 ספרות',
          'external_client_number_invalid':
              'יש להזין 1–10 ספרות. שדה זה הוא חובה.',
          'client_number_duplicate': 'מספר לקוח זה כבר משויך ללקוח אחר.',
          'generate_client_number': 'צור מספר לקוח חדש',
          'client_details_required': 'יש למלא לפחות את שם הלקוח.',
          'client_id_invalid_length': 'מספר הלקוח חייב להיות בן 9 ספרות.',
          'client_id_invalid': 'מספר הלקוח אינו תקין.',
          'client_id_duplicate': 'מספר זיהוי זה כבר משויך ללקוח אחר.',
          'items': 'פירוט פריטים ושירותים',
          'desc': 'תיאור השירות/מוצר',
          'qty': 'כמות',
          'price': 'מחיר ליח\'',
          'price_tax_mode': 'מחיר כולל/לפני מע"מ',
          'price_before_tax': 'לפני מע"מ',
          'price_after_tax': 'כולל מע"מ',
          'has_discount': 'האם יש הנחה?',
          'discount_amount': 'סכום הנחה',
          'discount_type': 'סוג',
          'discount_invalid':
              'יש להזין אחוז הנחה בין 0 ל-100 או סכום הנחה שאינו גדול מהסכום הכולל המקורי של המסמך.',
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
          'transaction_account': 'חשבון עסקה',
          'receipt': 'קבלה',
          'invoice': 'חשבונית מס',
          'invoice_receipt': 'חשבונית מס / קבלה',
          'credit_note': 'חשבונית מס זיכוי',
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
          'credit_note_legal': 'פרטי חשבונית מס זיכוי',
          'credit_reason': 'סיבת הזיכוי',
          'original_invoice_number': 'מספר חשבונית מקור',
          'original_invoice_date': 'תאריך חשבונית מקור',
          'delivery_method': 'אופן מסירת חשבונית מס הזיכוי',
          'receipt_confirmation': 'אסמכתא למסירה / אישור קבלה',
          'pick_date': 'בחירת תאריך',
          'delivery_registered_mail': 'דואר רשום',
          'delivery_email_confirmation': 'אישור דוא"ל',
          'delivery_customer_signature': 'חתימת לקוח',
          'delivery_manual': 'מסירה ידנית',
          'credit_note_missing_fields':
              'לחשבונית מס זיכוי יש למלא מספר חשבונית מקור, תאריך מקור, סיבת זיכוי ואסמכתא למסירה.',
          'credit_note_legal_hint':
              'לשימוש תקין בישראל יש לשמור קישור לחשבונית המקור ואסמכתא למסירת חשבונית מס הזיכוי ללקוח.',
          'doc_start_title': 'מספר פתיחה למסמך',
          'doc_start_message':
              'זו הפעם הראשונה שאתה משתמש ב-{docType}. הזן את המספר שממנו המסמך הזה צריך להתחיל.',
          'doc_start_warning':
              'חשוב להזין את המספר הנכון. אם תזין מספר שגוי, האחריות היא שלך ולא תוכל לשנות אותו אחר כך.',
          'doc_start_field': 'מספר פתיחה',
          'doc_start_invalid': 'יש להזין מספר תקין גדול מ-0',
          'doc_start_confirm_title': 'אישור מספר הפתיחה',
          'doc_start_confirm_message':
              'האם ברצונך להתחיל את מספור {docType} במספר {number}?',
          'doc_start_confirm_warning':
              'לאחר האישור מספר הפתיחה יינעל ולא ניתן יהיה לשנות אותו.',
          'doc_start_confirm_action': 'אישור ושמירה',
          'allocation_number': 'מספר הקצאה',
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
              'منشئ الفواتير مفتوح حاليًا على جهاز آخر. أغلقه على الجهاز الآخر، وانتظر بضع ثوانٍ، ثم حاول مرة أخرى.',
          'invoice_builder_locked_action': 'رجوع',
          'ok': 'حسنًا',
          'client_info': 'تفاصيل العميل:',
          'client_name': 'اسم العميل',
          'client_id': 'رقم النشاط / الهوية / الرقم الضريبي',
          'client_address': 'عنوان العميل',
          'client_phone': 'هاتف العميل',
          'client_email': 'البريد الإلكتروني للعميل',
          'linked_documents': 'المستند المرتبط',
          'linked_documents_title': 'اختر مستندًا للربط',
          'linked_documents_selected': 'تم ربط مستند',
          'linked_documents_empty': 'لا توجد مستندات متوافقة لهذا العميل.',
          'linked_documents_load_failed': 'تعذر تحميل المستندات.',
          'link_documents_action': 'ربط المستند',
          'linked_documents_helper':
              'اختر مستندًا واحدًا أو أكثر لربطه بالمستند الحالي.',
          'linked_documents_search':
              'ابحث حسب النوع أو الرقم أو التاريخ أو المبلغ',
          'linked_documents_count': 'تم اختيار {count}',
          'linked_documents_no_results': 'لا توجد مستندات مطابقة لبحثك.',
          'select_all': 'تحديد الكل',
          'clear_selection': 'مسح',
          'retry': 'إعادة المحاولة',
          'link_documents_action_count': 'ربط ({count})',
          'add_client': 'إضافة عميل',
          'save_client': 'حفظ العميل',
          'client_added': 'تمت إضافة العميل واختياره.',
          'client_save_failed': 'تعذر حفظ العميل. حاول مرة أخرى.',
          'invalid_email': 'يرجى إدخال بريد إلكتروني صحيح.',
          'external_client_number': 'رقم العميل في المحاسبة الخارجية',
          'external_client_number_hint': 'من 1 إلى 10 أرقام',
          'external_client_number_invalid':
              'أدخل من 1 إلى 10 أرقام. هذا الحقل مطلوب.',
          'client_number_duplicate': 'رقم العميل مستخدم بالفعل لعميل آخر.',
          'generate_client_number': 'إنشاء رقم عميل جديد',
          'client_details_required': 'يرجى إدخال اسم العميل على الأقل.',
          'client_id_invalid_length': 'يجب أن يتكون رقم العميل من 9 أرقام.',
          'client_id_invalid': 'رقم العميل غير صالح.',
          'client_id_duplicate': 'رقم الهوية هذا مستخدم بالفعل لعميل آخر.',
          'items': 'تفاصيل الخدمات والمنتجات',
          'desc': 'الوصف',
          'qty': 'الكمية',
          'price': 'سعر الوحدة',
          'price_tax_mode': 'حالة السعر الضريبية',
          'price_before_tax': 'قبل الضريبة',
          'price_after_tax': 'شامل الضريبة',
          'has_discount': 'هل يوجد خصم؟',
          'discount_amount': 'مبلغ الخصم',
          'discount_type': 'النوع',
          'discount_invalid':
              'أدخل نسبة خصم بين 0 و100 أو مبلغًا لا يتجاوز الإجمالي الأصلي للمستند.',
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
          'transaction_account': 'فاتورة مبدئية',
          'receipt': 'إيصال',
          'invoice': 'فاتورة ضريبية',
          'invoice_receipt': 'فاتورة ضريبية / إيصال',
          'credit_note': 'فاتورة ضريبية دائنة',
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
          'credit_note_legal': 'تفاصيل الفاتورة الضريبية الدائنة',
          'credit_reason': 'سبب الفاتورة الضريبية الدائنة',
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
              'تتطلب الفاتورة الضريبية الدائنة رقم الفاتورة الأصلية وتاريخها وسبب الائتمان وإثبات التسليم.',
          'credit_note_legal_hint':
              'للامتثال في إسرائيل، احتفظ بمرجع الفاتورة الأصلية وإثبات تسليم الفاتورة الضريبية الدائنة إلى العميل.',
          'doc_start_title': 'رقم بداية المستند',
          'doc_start_message':
              'هذه هي المرة الأولى التي تستخدم فيها {docType}. أدخل الرقم الذي يجب أن يبدأ منه هذا النوع من المستندات.',
          'doc_start_warning':
              'من المهم إدخال الرقم الصحيح. إذا أدخلت رقمًا خاطئًا، فستتحمل المسؤولية ولن تتمكن من تغييره لاحقًا.',
          'doc_start_field': 'رقم البداية',
          'doc_start_invalid': 'أدخل رقمًا صحيحًا أكبر من 0',
          'doc_start_confirm_title': 'تأكيد رقم البداية',
          'doc_start_confirm_message':
              'هل تريد أن يبدأ ترقيم {docType} من الرقم {number}؟',
          'doc_start_confirm_warning':
              'بعد التأكيد سيتم تثبيت رقم البداية ولن تتمكن من تغييره.',
          'doc_start_confirm_action': 'تأكيد وحفظ',
          'continue': 'متابعة',
          'cancel': 'إلغاء',
        };
        break;
      case 'ru':
        _cachedStrings = {
          'title': 'Конструктор бизнес-документов',
          'invoice_builder_locked_title': 'Конструктор счетов уже используется',
          'invoice_builder_locked':
              'Конструктор счетов сейчас открыт на другом устройстве. Закройте его там, подождите несколько секунд и повторите попытку.',
          'invoice_builder_locked_action': 'Назад',
          'ok': 'ОК',
          'client_info': 'Данные клиента:',
          'client_name': 'Имя клиента',
          'client_id': 'Номер бизнеса / ID / налоговый номер',
          'client_address': 'Адрес клиента',
          'client_phone': 'Телефон клиента',
          'client_email': 'Электронная почта клиента',
          'linked_documents': 'Связанный документ',
          'linked_documents_title': 'Выберите документ для связи',
          'linked_documents_selected': 'Документ связан',
          'linked_documents_empty':
              'Для этого клиента нет подходящих документов.',
          'linked_documents_load_failed': 'Не удалось загрузить документы.',
          'link_documents_action': 'Связать документ',
          'linked_documents_helper':
              'Выберите один или несколько документов для связи с текущим.',
          'linked_documents_search': 'Поиск по типу, номеру, дате или сумме',
          'linked_documents_count': 'Выбрано: {count}',
          'linked_documents_no_results': 'По вашему запросу ничего не найдено.',
          'select_all': 'Выбрать все',
          'clear_selection': 'Очистить',
          'retry': 'Повторить',
          'link_documents_action_count': 'Связать ({count})',
          'add_client': 'Добавить клиента',
          'save_client': 'Сохранить клиента',
          'client_added': 'Клиент добавлен и выбран.',
          'client_save_failed': 'Не удалось сохранить клиента.',
          'invalid_email': 'Введите действительный адрес электронной почты.',
          'external_client_number': 'Номер клиента во внешней бухгалтерии',
          'external_client_number_hint': 'От 1 до 10 цифр',
          'external_client_number_invalid':
              'Введите от 1 до 10 цифр. Поле обязательно.',
          'client_number_duplicate':
              'Этот номер уже используется другим клиентом.',
          'generate_client_number': 'Создать новый номер клиента',
          'client_details_required':
              'Пожалуйста, укажите как минимум имя клиента.',
          'client_id_invalid_length': 'ID клиента должен состоять из 9 цифр.',
          'client_id_invalid': 'ID клиента недействителен.',
          'client_id_duplicate': 'Этот ID уже используется другим клиентом.',
          'items': 'Товары и услуги',
          'desc': 'Описание',
          'qty': 'Кол-во',
          'price': 'Цена за единицу',
          'price_tax_mode': 'Режим цены по налогу',
          'price_before_tax': 'До налога',
          'price_after_tax': 'С налогом',
          'has_discount': 'Применить скидку?',
          'discount_amount': 'Сумма скидки',
          'discount_type': 'Тип',
          'discount_invalid':
              'Введите скидку от 0 до 100% или сумму не больше первоначальной общей суммы документа.',
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
          'transaction_account': 'Счёт-проформа',
          'receipt': 'Квитанция',
          'invoice': 'Налоговый счет',
          'invoice_receipt': 'Налоговый счет / квитанция',
          'credit_note': 'Кредитовый налоговый счёт',
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
          'credit_note_legal': 'Данные кредитового налогового счёта',
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
              'Для кредитового налогового счёта необходимы номер и дата исходного счёта, причина кредита и подтверждение доставки.',
          'credit_note_legal_hint':
              'Для соответствия требованиям в Израиле храните ссылку на исходный счёт и подтверждение вручения кредитового налогового счёта клиенту.',
          'doc_start_title': 'Начальный номер документа',
          'doc_start_message':
              'Вы впервые используете {docType}. Введите номер, с которого должен начинаться этот тип документа.',
          'doc_start_warning':
              'Важно ввести правильный номер. Если вы введете неправильный номер, ответственность будет на вас, и позже его нельзя будет изменить.',
          'doc_start_field': 'Начальный номер',
          'doc_start_invalid': 'Введите корректный номер больше 0',
          'doc_start_confirm_title': 'Подтвердите начальный номер',
          'doc_start_confirm_message':
              'Начать нумерацию документа «{docType}» с номера {number}?',
          'doc_start_confirm_warning':
              'После подтверждения начальный номер будет заблокирован, и изменить его будет нельзя.',
          'doc_start_confirm_action': 'Подтвердить и сохранить',
          'continue': 'Продолжить',
          'cancel': 'Отмена',
        };
        break;
      case 'am':
        _cachedStrings = {
          'title': 'የንግድ ሰነድ አዘጋጅ',
          'invoice_builder_locked_title': 'የኢንቮይስ አዘጋጁ በጥቅም ላይ ነው',
          'invoice_builder_locked':
              'የኢንቮይስ አዘጋጁ አሁን በሌላ መሣሪያ ላይ ክፍት ነው። በዚያ መሣሪያ ላይ ይዝጉት፣ ጥቂት ሰከንዶች ይጠብቁና እንደገና ይሞክሩ።',
          'invoice_builder_locked_action': 'ተመለስ',
          'ok': 'እሺ',
          'client_info': 'የደንበኛ ዝርዝሮች:',
          'client_name': 'የደንበኛ ስም',
          'client_id': 'የንግድ ቁጥር / መታወቂያ / የግብር ቁጥር',
          'client_address': 'የደንበኛ አድራሻ',
          'client_phone': 'የደንበኛ ስልክ',
          'client_email': 'የደንበኛ ኢሜይል',
          'linked_documents': 'የተገናኘ ሰነድ',
          'linked_documents_title': 'የሚገናኝ ሰነድ ይምረጡ',
          'linked_documents_selected': 'ሰነድ ተገናኝቷል',
          'linked_documents_empty': 'ለዚህ ደንበኛ ተስማሚ ሰነዶች የሉም።',
          'linked_documents_load_failed': 'ሰነዶቹን መጫን አልተቻለም።',
          'link_documents_action': 'ሰነድ አገናኝ',
          'linked_documents_helper':
              'ከአሁኑ ሰነድ ጋር ለማገናኘት አንድ ወይም ከዚያ በላይ ሰነዶችን ይምረጡ።',
          'linked_documents_search': 'በአይነት፣ ቁጥር፣ ቀን ወይም መጠን ይፈልጉ',
          'linked_documents_count': '{count} ተመርጧል',
          'linked_documents_no_results': 'ከፍለጋዎ ጋር የሚዛመድ ሰነድ የለም።',
          'select_all': 'ሁሉንም ምረጥ',
          'clear_selection': 'አጽዳ',
          'retry': 'እንደገና ሞክር',
          'link_documents_action_count': 'አገናኝ ({count})',
          'add_client': 'ደንበኛ ጨምር',
          'save_client': 'ደንበኛ አስቀምጥ',
          'client_added': 'ደንበኛው ተጨምሮ ተመርጧል።',
          'client_save_failed': 'ደንበኛውን ማስቀመጥ አልተቻለም።',
          'invalid_email': 'ትክክለኛ ኢሜይል ያስገቡ።',
          'external_client_number': 'የውጭ ሂሳብ የደንበኛ ቁጥር',
          'external_client_number_hint': 'ከ1–10 ቁጥሮች',
          'external_client_number_invalid': 'ከ1–10 ቁጥሮች ያስገቡ። ይህ መስክ ያስፈልጋል።',
          'client_number_duplicate': 'ይህ የደንበኛ ቁጥር በሌላ ደንበኛ ጥቅም ላይ ነው።',
          'generate_client_number': 'አዲስ የደንበኛ ቁጥር ፍጠር',
          'client_details_required': 'ቢያንስ የደንበኛውን ስም ያስገቡ።',
          'client_id_invalid_length': 'የደንበኛ መታወቂያ 9 አሃዞች መሆን አለበት።',
          'client_id_invalid': 'የደንበኛ መታወቂያው ትክክል አይደለም።',
          'client_id_duplicate': 'ይህ መታወቂያ በሌላ ደንበኛ ጥቅም ላይ ነው።',
          'items': 'የአገልግሎት እና የእቃ ዝርዝሮች',
          'desc': 'መግለጫ',
          'qty': 'ብዛት',
          'price': 'የአንዱ ዋጋ',
          'price_tax_mode': 'የዋጋ ግብር ሁኔታ',
          'price_before_tax': 'ከግብር በፊት',
          'price_after_tax': 'ግብር ጨምሮ',
          'has_discount': 'ቅናሽ አለ?',
          'discount_amount': 'የቅናሽ መጠን',
          'discount_type': 'ዓይነት',
          'discount_invalid':
              'ከ0 እስከ 100% የሆነ ቅናሽ ወይም ከሰነዱ የመጀመሪያ ጠቅላላ ድምር ያልበለጠ መጠን ያስገቡ።',
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
          'transaction_account': 'ፕሮፎርማ ደረሰኝ',
          'receipt': 'ደረሰኝ',
          'invoice': 'የግብር ደረሰኝ',
          'invoice_receipt': 'የግብር ደረሰኝ / ደረሰኝ',
          'credit_note': 'የግብር ደረሰኝ ክሬዲት',
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
          'credit_note_legal': 'የግብር ደረሰኝ ክሬዲት ዝርዝሮች',
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
              'ለግብር ደረሰኝ ክሬዲት የመጀመሪያው ደረሰኝ ቁጥር፣ ቀን፣ ምክንያት እና የማድረስ ማረጋገጫ ያስፈልጋሉ።',
          'credit_note_legal_hint':
              'በእስራኤል ደንብ መሰረት የመጀመሪያውን ደረሰኝ ማጣቀሻ እና የግብር ደረሰኝ ክሬዲቱ ለደንበኛው እንደደረሰ ማረጋገጫ ያስቀምጡ።',
          'doc_start_title': 'የመነሻ ሰነድ ቁጥር',
          'doc_start_message':
              'ይህን {docType} ለመጀመሪያ ጊዜ እየተጠቀሙ ነው። ይህ የሰነድ አይነት የሚጀምርበትን ቁጥር ያስገቡ።',
          'doc_start_warning':
              'ትክክለኛውን ቁጥር ማስገባት አስፈላጊ ነው። የተሳሳተ ቁጥር ካስገቡ ኃላፊነቱ የእርስዎ ነው እና በኋላ መቀየር አይቻልም።',
          'doc_start_field': 'የመነሻ ቁጥር',
          'doc_start_invalid': 'ከ0 በላይ የሆነ ትክክለኛ ቁጥር ያስገቡ',
          'doc_start_confirm_title': 'የመነሻ ቁጥርን ያረጋግጡ',
          'doc_start_confirm_message': 'የ{docType} ቁጥር ከ{number} እንዲጀምር ይፈልጋሉ?',
          'doc_start_confirm_warning':
              'ካረጋገጡ በኋላ የመነሻ ቁጥሩ ይቆለፋል እና መቀየር አይቻልም።',
          'doc_start_confirm_action': 'አረጋግጥና አስቀምጥ',
          'continue': 'ቀጥል',
          'cancel': 'ሰርዝ',
        };
        break;
      default:
        _cachedStrings = {
          'title': 'Business Document Builder',
          'invoice_builder_locked_title': 'Invoice Builder Is In Use',
          'invoice_builder_locked':
              'Invoice Builder is currently open on another device. Close it there, wait a few seconds, then try again.',
          'invoice_builder_locked_action': 'Back',
          'ok': 'OK',
          'client_info': 'Client Details:',
          'client_name': 'Client Name',
          'client_id': 'Business No. / ID / Tax ID',
          'client_address': 'Client Address',
          'client_phone': 'Client Phone',
          'client_email': 'Client Email',
          'linked_documents': 'Linked document',
          'linked_documents_title': 'Select a document to link',
          'linked_documents_selected': 'Document linked',
          'linked_documents_empty':
              'There are no compatible documents for this client.',
          'linked_documents_load_failed': 'Could not load the documents.',
          'link_documents_action': 'Link document',
          'linked_documents_helper':
              'Choose one or more documents to connect to this document.',
          'linked_documents_search': 'Search by type, number, date, or amount',
          'linked_documents_count': '{count} selected',
          'linked_documents_no_results': 'No documents match your search.',
          'select_all': 'Select all',
          'clear_selection': 'Clear',
          'retry': 'Try again',
          'link_documents_action_count': 'Link ({count})',
          'add_client': 'Add Client',
          'save_client': 'Save Client',
          'client_added': 'Client added and selected.',
          'client_save_failed': 'Could not save the client. Please try again.',
          'invalid_email': 'Please enter a valid email address.',
          'external_client_number': 'Client number in external accountancy',
          'external_client_number_hint': '1–10 digits',
          'external_client_number_invalid':
              'Enter 1–10 digits. This field is required.',
          'client_number_duplicate':
              'This client number is already used by another client.',
          'generate_client_number': 'Generate a new client number',
          'client_details_required': 'Please fill at least the client name.',
          'client_id_invalid_length': 'Client ID must be 9 digits.',
          'client_id_invalid': 'Client ID is not valid.',
          'client_id_duplicate': 'This ID is already used by another client.',
          'items': 'Service Items & Details',
          'desc': 'Description',
          'qty': 'Qty',
          'price': 'Unit Price',
          'price_tax_mode': 'Price Tax Mode',
          'price_before_tax': 'Before Tax',
          'price_after_tax': 'After Tax',
          'has_discount': 'Apply Discount?',
          'discount_amount': 'Discount Amount',
          'discount_type': 'Type',
          'discount_invalid':
              'Enter a discount from 0 to 100%, or an amount no greater than the original document total.',
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
          'transaction_account': 'Proforma Invoice',
          'receipt': 'Receipt',
          'invoice': 'Tax Invoice',
          'invoice_receipt': 'Tax Invoice / Receipt',
          'credit_note': 'Tax Invoice Credit',
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
          'credit_note_legal': 'Tax Invoice Credit Details',
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
              'Tax Invoice Credits require the original invoice number, original invoice date, reason for credit, and delivery proof.',
          'credit_note_legal_hint':
              'For Israeli compliance, keep the original invoice reference and proof that the Tax Invoice Credit was delivered to the customer.',
          'doc_start_title': 'Starting Document Number',
          'doc_start_message':
              'This is your first time using {docType}. Enter the number this document type should start from.',
          'doc_start_warning':
              'It is important to enter the correct number. If you enter the wrong number, it is your responsibility and you will not be able to change it later.',
          'doc_start_field': 'Starting Number',
          'doc_start_invalid': 'Enter a valid number greater than 0',
          'doc_start_confirm_title': 'Confirm starting number',
          'doc_start_confirm_message':
              'Do you want {docType} numbering to start at {number}?',
          'doc_start_confirm_warning':
              'After confirmation, this starting number will be locked and cannot be changed.',
          'doc_start_confirm_action': 'Confirm and save',
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
          'Invoice Builder is currently open on another device. Close it there, wait a few seconds, then try again.',
      'invoice_builder_locked_action': 'Back',
      'invoice_builder_unavailable_title': 'Invoice Builder Unavailable',
      'invoice_builder_unavailable':
          'The lock could not be verified. Check your connection and permissions, then try again.',
      'ok': 'OK',
      'preparing': 'Preparing document...',
      'doc_type': 'Document Type',
      'quote': 'Quote',
      'work_order': 'Work Order',
      'transaction_account': 'Proforma Invoice',
      'receipt': 'Receipt',
      'invoice': 'Tax Invoice',
      'invoice_receipt': 'Tax Invoice / Receipt',
      'credit_note': 'Tax Invoice Credit',
      'licensed_only': 'Verified Licensed Dealers only',
      'invoice_counter': 'Invoice Counter',
      'client_info': 'Client Details:',
      'client_name': 'Client Name',
      'client_id': 'Business No. / ID / Tax ID',
      'client_phone': 'Client Phone',
      'client_email': 'Client Email',
      'client_address': 'Client Address',
      'linked_documents': 'Linked document',
      'linked_documents_title': 'Select a document to link',
      'linked_documents_selected': 'Document linked',
      'linked_documents_empty':
          'There are no compatible documents for this client.',
      'linked_documents_load_failed': 'Could not load the documents.',
      'link_documents_action': 'Link document',
      'linked_documents_helper':
          'Choose one or more documents to connect to this document.',
      'linked_documents_search': 'Search by type, number, date, or amount',
      'linked_documents_count': '{count} selected',
      'linked_documents_no_results': 'No documents match your search.',
      'select_all': 'Select all',
      'clear_selection': 'Clear',
      'retry': 'Try again',
      'link_documents_action_count': 'Link ({count})',
      'add_client': 'Add Client',
      'save_client': 'Save Client',
      'client_added': 'Client added and selected.',
      'client_save_failed': 'Could not save the client. Please try again.',
      'invalid_email': 'Please enter a valid email address.',
      'external_client_number': 'Client number in external accountancy',
      'external_client_number_hint': '1–10 digits',
      'external_client_number_invalid':
          'Enter 1–10 digits. This field is required.',
      'client_number_duplicate':
          'This client number is already used by another client.',
      'generate_client_number': 'Generate a new client number',
      'client_details_required': 'Please fill at least the client name.',
      'client_id_invalid_length': 'Client ID must be 9 digits.',
      'client_id_invalid': 'Client ID is not valid.',
      'client_id_duplicate': 'This ID is already used by another client.',
      'items': 'Service Items & Details',
      'desc': 'Description',
      'qty': 'Qty',
      'price': 'Unit Price',
      'price_tax_mode': 'Price Tax Mode',
      'price_before_tax': 'Before Tax',
      'price_after_tax': 'After Tax',
      'has_discount': 'Apply Discount?',
      'discount_amount': 'Discount Amount',
      'discount_type': 'Type',
      'discount_invalid':
          'Enter a discount from 0 to 100%, or an amount no greater than the original document total.',
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
      'credit_note_legal': 'Tax Invoice Credit Details',
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
          'Tax Invoice Credits require the original invoice number, original invoice date, reason for credit, and delivery proof.',
      'credit_note_legal_hint':
          'For Israeli compliance, keep the original invoice reference and proof that the Tax Invoice Credit was delivered to the customer.',
      'doc_start_title': 'Starting Document Number',
      'doc_start_message':
          'This is your first time using {docType}. Enter the number this document type should start from.',
      'doc_start_warning':
          'It is important to enter the correct number. If you enter the wrong number, it is your responsibility and you will not be able to change it later.',
      'doc_start_field': 'Starting Number',
      'doc_start_invalid': 'Enter a valid number greater than 0',
      'doc_start_confirm_title': 'Confirm starting number',
      'doc_start_confirm_message':
          'Do you want {docType} numbering to start at {number}?',
      'doc_start_confirm_warning':
          'After confirmation, this starting number will be locked and cannot be changed.',
      'doc_start_confirm_action': 'Confirm and save',
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

  void _clearServiceItems() {
    _items.clear();
    _itemDescController.clear();
    _itemQtyController.text = '1';
    _itemPriceController.clear();
    _discountController.clear();
    _hasDiscount = false;
    _selectedDiscountType = 'amount';
    _selectedPriceTaxMode = 'after_tax';
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

  Future<bool> _confirmStartingDocumentNumber({
    required BuildContext context,
    required Map<String, String> strings,
    required int number,
    String? docType,
  }) async {
    final targetDocType = docType ?? _selectedDocType;
    final documentType = _documentTypeDisplayName(strings, targetDocType);
    final message = strings['doc_start_confirm_message']!
        .replaceFirst('{docType}', documentType)
        .replaceFirst('{number}', number.toString());

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (confirmationContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFC2410C),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings['doc_start_confirm_title']!,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      number.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFB91C1C),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings['doc_start_confirm_warning']!,
                            style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(confirmationContext, false),
                  child: Text(strings['cancel']!),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(confirmationContext, true),
                  icon: const Icon(Icons.lock_rounded, size: 18),
                  label: Text(strings['doc_start_confirm_action']!),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _promptForStartingDocumentNumber({String? docType}) async {
    final targetDocType = docType ?? _selectedDocType;
    final ref = _counterRefForDocType(targetDocType);
    if (ref == null || !mounted) return false;

    final strings = _withRequiredDefaults(
      _getLocalizedStrings(context, listen: false),
    );
    final suggestedNumber = _suggestedStartingDocumentNumbers[targetDocType];
    final controller = _startingDocumentNumberController;
    controller.text = suggestedNumber?.toString() ?? '';
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 36,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Material(
                  color: Colors.white,
                  elevation: 20,
                  shadowColor: const Color(0x330F172A),
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC)],
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1976D2),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x331976D2),
                                      blurRadius: 12,
                                      offset: Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.receipt_long_rounded,
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                strings['doc_start_title']!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  _documentTypeDisplayName(
                                    strings,
                                    targetDocType,
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF1D4ED8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                strings['doc_start_message']!.replaceFirst(
                                  '{docType}',
                                  _documentTypeDisplayName(
                                    strings,
                                    targetDocType,
                                  ),
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: controller,
                                autofocus: true,
                                selectAllOnFocus: true,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                                onChanged: (_) {
                                  if (errorText != null) {
                                    setDialogState(() => errorText = null);
                                  }
                                },
                                decoration: InputDecoration(
                                  labelText: strings['doc_start_field']!,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  errorText: errorText,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  prefixIcon: const Icon(
                                    Icons.tag_rounded,
                                    color: Color(0xFF1976D2),
                                    size: 20,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1976D2),
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFDC2626),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFED7AA),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: Color(0xFFC2410C),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        strings['doc_start_warning']!,
                                        style: const TextStyle(
                                          color: Color(0xFF9A3412),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      icon: const BackButtonIcon(),
                                      label: Text(
                                        MaterialLocalizations.of(
                                          dialogContext,
                                        ).backButtonTooltip,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF475569,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFCBD5E1),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        final parsed = int.tryParse(
                                          controller.text.trim(),
                                        );
                                        if (parsed == null || parsed < 1) {
                                          setDialogState(() {
                                            errorText =
                                                strings['doc_start_invalid']!;
                                          });
                                          return;
                                        }
                                        final shouldSave =
                                            await _confirmStartingDocumentNumber(
                                              context: dialogContext,
                                              strings: strings,
                                              number: parsed,
                                              docType: targetDocType,
                                            );
                                        if (!shouldSave ||
                                            !dialogContext.mounted) {
                                          return;
                                        }
                                        Navigator.pop(dialogContext, true);
                                      },
                                      icon: const Icon(Icons.check_rounded),
                                      label: Text(strings['continue']!),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF1976D2,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) {
      return false;
    }

    final startNumber = int.parse(controller.text.trim());
    try {
      final callable = _functions.httpsCallable('initializeDocumentCounter');
      final result = await callable.call<Map<String, dynamic>>({
        'docType': targetDocType,
        'startNumber': startNumber,
      });
      final assignedNumber = (result.data['value'] as num?)?.toInt();
      if (assignedNumber == null || assignedNumber < 1) return false;

      if (!mounted) return false;
      if (targetDocType == _selectedDocType) {
        setState(() {
          _currentDocumentCounter = assignedNumber;
          _invoiceNumber = _formatDocumentNumber(assignedNumber);
          _isLoadingCounterAssignment = false;
        });
      }
      return true;
    } catch (e) {
      dev.log('Error saving starting document counter: $e');
      return false;
    }
  }

  Future<bool> _ensureCancellationCreditNoteCounter() async {
    final ref = _counterRefForDocType('credit_note');
    if (ref == null) return false;
    final snapshot = await ref.get();
    final value = (snapshot.data()?['value'] as num?)?.toInt();
    if (value != null && value > 0) return true;
    return _promptForStartingDocumentNumber(docType: 'credit_note');
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
      case 'transaction_account':
        return strings['transaction_account']!;
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

  Future<Uint8List?> _getGeneratedPdfBytes() async {
    if (_items.isEmpty && _selectedDocType != 'receipt') return null;
    return _createServerDocumentPreview();
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
    final isValid =
        parsed != null &&
        parsed > 0 &&
        (_selectedDiscountType == 'percentage'
            ? parsed <= 100
            : parsed <= _itemsTotalBeforeDiscount);
    if (!isValid) {
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
      case 'bit':
        return 'Bit';
      case 'paybox':
        return 'PayBox';
      case 'other':
        return isRtl ? 'אחר' : 'Other';
      case 'withholding_tax':
        return isRtl ? 'ניכוי מס במקור' : 'Withholding Tax';
      case 'cash':
      default:
        return isRtl ? 'מזומן' : 'Cash';
    }
  }

  String _creditCompanyLabel(String company, bool isRtl) {
    if (!isRtl) return company;
    switch (company) {
      case 'Diners':
        return 'דיינרס';
      case 'CAL':
        return 'כאל';
      case 'Leumi Card':
        return 'לאומי קארד';
      case 'American Express':
        return 'אמריקן אקספרס';
      case 'Isracard':
        return 'ישראכרט';
      default:
        return company;
    }
  }

  TextEditingValue _formatCardExpiration(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();

    if (digits[0].compareTo('1') > 0) {
      digits = '0$digits';
    } else if (digits.length >= 2) {
      final month = int.tryParse(digits.substring(0, 2)) ?? 0;
      if (month > 12) {
        digits = '01${digits.substring(1)}';
      }
    }

    if (digits.length > 4) digits = digits.substring(0, 4);
    final text = digits.length >= 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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

  List<Map<String, dynamic>> _paymentMethodsForStorage() {
    return _paymentMethods.map((entry) {
      final data = entry.toMap();
      final amount = data['amount'];
      if (_isNegativeReceipt && amount is num) {
        data['amount'] = -amount.toDouble().abs();
      }
      return data;
    }).toList();
  }

  Future<void> _pickCheckPaymentDate(_PaymentMethodEntry entry) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.checkPaymentDate ?? _selectedInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      entry.checkPaymentDate = picked;
      entry.checkPaymentDateController.text = intl.DateFormat(
        'dd/MM/yyyy',
      ).format(picked);
    });
  }

  Future<void> _pickCreditInstallmentDate(
    _PaymentMethodEntry entry,
    int installmentIndex,
  ) async {
    final previousDate = installmentIndex > 0
        ? entry.creditInstallmentDates[installmentIndex - 1]
        : null;
    final picked = await showDatePicker(
      context: context,
      initialDate:
          entry.creditInstallmentDates[installmentIndex] ??
          previousDate?.add(const Duration(days: 30)) ??
          _selectedInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      entry.creditInstallmentDates[installmentIndex] = picked;
      entry.creditInstallmentDateControllers[installmentIndex].text =
          intl.DateFormat('dd/MM/yyyy').format(picked);
    });
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

      if (methodEntry.method == 'check' &&
          methodEntry.checkPaymentDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'בשיטת צ׳ק חובה לבחור תאריך פירעון (שורה ${i + 1}).'
                  : 'A due date is required for check payments (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'check' &&
          methodEntry.checkBankController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'בשיטת צ׳ק חובה לבחור בנק (שורה ${i + 1}).'
                  : 'A bank is required for check payments (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'check' &&
          methodEntry.checkBranchController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'בשיטת צ׳ק חובה לבחור סניף (שורה ${i + 1}).'
                  : 'A branch is required for check payments (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'check' &&
          methodEntry.checkAccountController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRtl
                  ? 'בשיטת צ׳ק חובה למלא חשבון בנק (שורה ${i + 1}).'
                  : 'A bank account is required for check payments (row ${i + 1}).',
            ),
          ),
        );
        return false;
      }

      if (methodEntry.method == 'credit') {
        final installments = methodEntry.installmentsController.text.trim();
        final parsed = int.tryParse(installments);
        if (installments.isNotEmpty &&
            (parsed == null || parsed < 1 || parsed > 999)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRtl
                    ? 'מספר התשלומים חייב להיות מספר תקין (שורה ${i + 1}).'
                    : 'Number of payments must be valid (row ${i + 1}).',
              ),
            ),
          );
          return false;
        }
        if (parsed != null && parsed > 1) {
          methodEntry.ensureCreditInstallmentCount(parsed);
          if (methodEntry.creditInstallmentDates.any((date) => date == null)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isRtl
                      ? 'חובה לבחור תאריך פירעון לכל תשלום באשראי (שורה ${i + 1}).'
                      : 'Select a due date for every credit-card installment (row ${i + 1}).',
                ),
              ),
            );
            return false;
          }
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

  Future<void> _openPreviewPage() async {
    if (_items.isEmpty && _selectedDocType != 'receipt') {
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
      Future<Uint8List?> saveServerResult(
        _ServerDocumentResult serverResult,
      ) async {
        savedDraftResult = serverResult.toDraftResult();
        if (savedDraftResult == null) {
          throw StateError('The server did not return a final document.');
        }
        final finalPdfBytes = await firebase_storage.FirebaseStorage.instance
            .ref()
            .child(savedDraftResult!.storagePath)
            .getData(25 * 1024 * 1024);
        if (finalPdfBytes == null || finalPdfBytes.length < 4) {
          throw StateError(
            'The final server document could not be downloaded.',
          );
        }
        _markDocumentSaved();
        _showInvoiceEmailDeliveryToast(savedDraftResult!);
        return finalPdfBytes;
      }

      final builderRoute = ModalRoute.of(context);
      final navigator = Navigator.of(context);
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
            onReturnAfterSave: widget.returnDraftOnSend
                ? null
                : _handleBuilderBack,
            onSave: () async {
              final serverResult = await _finalizeDocumentOnServer();
              return saveServerResult(serverResult);
            },
            onSaveWithoutAllocation: () async {
              final serverResult = await _createServerDocument();
              return saveServerResult(serverResult);
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
            onSend: widget.returnDraftOnSend
                ? null
                : () async {
                    MapEntry<String, String>? recipient;
                    final returnsToExistingChat = widget.receiverId != null;

                    if (widget.receiverId != null && savedDraftResult != null) {
                      final sent = await _sendSavedInvoiceToContact(
                        widget.receiverId!,
                        widget.receiverName ?? 'User',
                        savedDraftResult!,
                      );
                      if (sent) {
                        recipient = MapEntry(
                          widget.receiverId!,
                          widget.receiverName ?? 'User',
                        );
                      }
                    } else if (widget.receiverId != null) {
                      final sent = await _sendToContact(
                        widget.receiverId!,
                        widget.receiverName ?? 'User',
                      );
                      if (sent) {
                        recipient = MapEntry(
                          widget.receiverId!,
                          widget.receiverName ?? 'User',
                        );
                      }
                    } else {
                      recipient = await _showContactPickerAndSend(
                        savedInvoice: savedDraftResult,
                      );
                    }

                    if (recipient == null) return;
                    final selectedRecipient = recipient;

                    if (builderRoute != null && builderRoute.isActive) {
                      navigator.removeRoute(builderRoute);
                    }
                    if (returnsToExistingChat) {
                      navigator.pop();
                    } else {
                      unawaited(
                        navigator.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              receiverId: selectedRecipient.key,
                              receiverName: selectedRecipient.value,
                            ),
                          ),
                        ),
                      );
                    }
                  },
          ),
        ),
      );

      if (!mounted) return;

      if (action == 'send') {
        if (widget.returnDraftOnSend) {
          Navigator.pop(context, savedDraftResult);
          return;
        }
        return;
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

  Future<void> _showInvoiceEmailDeliveryToast(
    InvoiceBuilderDraftResult saved,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final invoiceRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices')
          .doc(saved.invoiceDocId);
      final snapshot = await invoiceRef
          .snapshots()
          .firstWhere((document) {
            final status = (document.data()?['invoiceEmailStatus'] ?? '')
                .toString()
                .trim();
            return status == 'sent' ||
                status == 'failed' ||
                status == 'skipped';
          })
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;

      final status = (snapshot.data()?['invoiceEmailStatus'] ?? '')
          .toString()
          .trim();
      if (status == 'sent') {
        final clientEmail = _clientEmailController.text.trim();
        final sentToClient =
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(clientEmail) &&
            clientEmail.toLowerCase() != (user.email ?? '').toLowerCase();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sentToClient
                  ? 'Document was sent to your email and the client’s email.'
                  : 'Document was sent to your email.',
            ),
          ),
        );
      } else if (status == 'failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the document email.')),
        );
      }
    } on TimeoutException {
      // The email may still be processing; do not show a false success toast.
    } catch (error) {
      dev.log('Unable to read invoice email status: $error');
    }
  }

  Future<_SavedInvoiceResult?> _saveInvoicePdf({
    bool showFeedback = true,
  }) async {
    final assigned = await _ensureDocumentNumberAssigned();
    if (!assigned) return null;

    try {
      final serverResult = await _finalizeDocumentOnServer(
        showAllocationFeedback: showFeedback,
      );
      final saved = serverResult.toDraftResult();
      if (saved == null || saved.url.isEmpty) {
        throw StateError('The server did not return a final document.');
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

      _markDocumentSaved();
      _showInvoiceEmailDeliveryToast(saved);

      return _SavedInvoiceResult(url: saved.url, fileName: saved.fileName);
    } catch (e) {
      dev.log('Save invoice error: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save invoice.')));
      return null;
    }
  }

  Future<MapEntry<String, String>?> _showContactPickerAndSend({
    InvoiceBuilderDraftResult? savedInvoice,
  }) async {
    if (_items.isEmpty && _selectedDocType != 'receipt') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _getLocalizedStrings(context, listen: false)['empty_items']!,
          ),
        ),
      );
      return null;
    }

    if (widget.receiverId != null) {
      bool sent;
      if (savedInvoice != null) {
        sent = await _sendSavedInvoiceToContact(
          widget.receiverId!,
          widget.receiverName ?? "User",
          savedInvoice,
        );
      } else {
        sent = await _sendToContact(
          widget.receiverId!,
          widget.receiverName ?? "User",
        );
      }
      return sent
          ? MapEntry(widget.receiverId!, widget.receiverName ?? 'User')
          : null;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final strings = _getLocalizedStrings(context, listen: false);

    final recipient = await showModalBottomSheet<MapEntry<String, String>>(
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
                        final otherId = (data['users'] as List)
                            .firstWhere((id) => id != user.uid)
                            .toString();
                        final otherName =
                            data['user_names']?[otherId]?.toString() ?? "User";

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF1976D2,
                            ).withValues(alpha: 0.1),
                            child: Text(
                              (otherName.isEmpty ? '?' : otherName[0])
                                  .toUpperCase(),
                              style: const TextStyle(color: Color(0xFF1976D2)),
                            ),
                          ),
                          title: Text(otherName),
                          onTap: () => Navigator.pop(
                            context,
                            MapEntry(otherId, otherName),
                          ),
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

    if (!mounted || recipient == null) return null;

    final sent = savedInvoice != null
        ? await _sendSavedInvoiceToContact(
            recipient.key,
            recipient.value,
            savedInvoice,
          )
        : await _sendToContact(recipient.key, recipient.value);
    return sent ? recipient : null;
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

    try {
      final saved = await _saveInvoicePdf(showFeedback: false);
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

  @override
  Widget build(BuildContext context) {
    if (!_isIdentityVerified) {
      return _buildIdentityVerificationGate(context);
    }
    if (_isAcquiringLock) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasInvoiceBuilderLock) {
      return const SizedBox.shrink();
    }
    if (!_hasLoadedDealerType) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          child: PopScope(
            canPop: !_returnsHomeAfterSave,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _returnsHomeAfterSave) {
                _handleBuilderBack();
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              appBar: AppBar(
                leading: BackButton(onPressed: _handleBuilderBack),
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
                                    value: 'transaction_account',
                                    child: Text(
                                      strings['transaction_account']!,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'receipt',
                                    child: Text(strings['receipt']!),
                                  ),
                                  if (_showsLicensedOnlyDocumentTypes) ...[
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
                                      enabled:
                                          _isLicensedDealerType &&
                                          _isBusinessVerified,
                                      child: Text(
                                        strings['credit_note']! +
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
                                  ],
                                ],
                                onChanged: (val) async {
                                  if (val == null) return;
                                  setState(() {
                                    if (val == 'receipt' &&
                                        _selectedDocType != 'receipt') {
                                      _clearServiceItems();
                                    }
                                    _selectedDocType = val;
                                    _linkedDocuments.clear();
                                    _currentDocumentCounter = null;
                                    _invoiceNumber = '';
                                  });
                                  await _loadCurrentDocumentNumber(
                                    promptIfMissing: true,
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildBusinessLogoSection(strings),
                          const SizedBox(height: 20),
                          // Client information
                          _buildSectionCard(
                            title: strings['client_info']!,
                            icon: Icons.person_add_alt_1_rounded,
                            children: [
                              _buildClientPicker(strings),
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
                                enabled: false,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                _clientPhoneController,
                                strings['client_phone']!,
                                Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                enabled: false,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                _clientEmailController,
                                strings['client_email']!,
                                Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                enabled: false,
                              ),
                              const SizedBox(height: 12),
                              _buildTextField(
                                _clientAddressController,
                                strings['client_address']!,
                                Icons.location_on_outlined,
                                enabled: false,
                              ),
                            ],
                          ),

                          if (_selectedDocType != 'quote') ...[
                            const SizedBox(height: 20),
                            _buildSectionCard(
                              title: strings['linked_documents']!,
                              icon: Icons.link_rounded,
                              children: [
                                if (_linkedDocuments.isNotEmpty) ...[
                                  ..._linkedDocuments.values.map(
                                    (document) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: _buildLinkedDocumentSummary(
                                        strings,
                                        document,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _selectedSavedClientId == null
                                        ? null
                                        : () => _showLinkedDocumentsPopup(
                                            strings,
                                          ),
                                    icon: const Icon(Icons.link_rounded),
                                    label: Text(
                                      _linkedDocuments.isEmpty
                                          ? strings['linked_documents_title']!
                                          : strings['linked_documents_count']!
                                                .replaceFirst(
                                                  '{count}',
                                                  '${_linkedDocuments.length}',
                                                ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFF1976D2),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

                          if (_selectedDocType != 'receipt') ...[
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
                                if (_isLicensedDealerType) ...[
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
                                        child: Text(
                                          strings['price_after_tax']!,
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'before_tax',
                                        child: Text(
                                          strings['price_before_tax']!,
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(
                                        () => _selectedPriceTaxMode = value,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
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
                          ],

                          if (_showsPaymentMethodSection) ...[
                            const SizedBox(height: 20),
                            _buildSectionCard(
                              title: isRtl ? 'אמצעי תשלום' : 'Payment Method',
                              icon: Icons.payment,
                              children: [
                                ...List.generate(_paymentMethods.length, (
                                  index,
                                ) {
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom:
                                          index == _paymentMethods.length - 1
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
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        for (final methodEntry
                                            in _paymentMethods) {
                                          methodEntry.isExpanded = false;
                                        }
                                        _paymentMethods.add(
                                          _PaymentMethodEntry(),
                                        );
                                      });
                                    },
                                    icon: const Icon(Icons.add_rounded),
                                    label: Text(
                                      isRtl
                                          ? 'הוסף אמצעי תשלום'
                                          : 'Add Payment Method',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_selectedDocType != 'receipt' &&
                              _items.isNotEmpty) ...[
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
                                      "${item.quantity} x ${item.price.toStringAsFixed(2)} ₪${_isLicensedDealerType ? ' (${item.isPriceBeforeTax ? strings['entered_price_before_tax']! : strings['entered_price_after_tax']!})' : ''}",
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
                          if (_items.isNotEmpty ||
                              (_selectedDocType == 'receipt' &&
                                  _paymentMethodsAmountTotal() > 0)) ...[
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
                                        _selectedDocType == 'receipt'
                                            ? (isRtl
                                                  ? 'סה״כ שולם'
                                                  : 'Total Paid')
                                            : strings['total']!,
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
                                  if (_selectedDocType != 'receipt') ...[
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
                                    SwitchListTile.adaptive(
                                      contentPadding: EdgeInsets.zero,
                                      value: _hasDiscount,
                                      onChanged: (value) {
                                        setState(() {
                                          _hasDiscount = value;
                                          if (!value) {
                                            _discountController.clear();
                                          }
                                        });
                                      },
                                      secondary: const Icon(
                                        Icons.discount_outlined,
                                        color: Colors.white,
                                      ),
                                      activeThumbColor: Colors.white,
                                      activeTrackColor: Colors.white54,
                                      title: Text(
                                        strings['has_discount']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_hasDiscount) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _buildTextField(
                                              _discountController,
                                              strings['discount_amount']!,
                                              Icons.discount_outlined,
                                              required: true,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              inputFormatters: [
                                                _discountInputFormatter(),
                                              ],
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          SizedBox(
                                            width: 96,
                                            child: DropdownButtonFormField<String>(
                                              initialValue:
                                                  _selectedDiscountType,
                                              isExpanded: true,
                                              dropdownColor: Colors.white,
                                              decoration: InputDecoration(
                                                labelText:
                                                    strings['discount_type']!,
                                                filled: true,
                                                fillColor: Colors.white,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 16,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 'percentage',
                                                  child: Text('%'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 'amount',
                                                  child: Text('₪'),
                                                ),
                                              ],
                                              onChanged: (value) {
                                                if (value == null) return;
                                                _selectDiscountType(value);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
    final methodLabel = _paymentMethodLabel(isRtl, entry.method);
    final methodIcon = switch (entry.method) {
      'credit' => Icons.credit_card_rounded,
      'transfer' => Icons.account_balance_rounded,
      'check' => Icons.payments_outlined,
      'bit' || 'paybox' => Icons.phone_iphone_rounded,
      'withholding_tax' => Icons.percent_rounded,
      'other' => Icons.more_horiz_rounded,
      _ => Icons.payments_rounded,
    };

    if (!entry.isExpanded) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => entry.isExpanded = true),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(methodIcon, color: const Color(0xFF1976D2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRtl
                            ? 'אמצעי תשלום ${index + 1}'
                            : 'Payment method ${index + 1}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        parsedAmount == null
                            ? methodLabel
                            : '$methodLabel  •  ${parsedAmount.toStringAsFixed(2)} ₪',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_paymentMethods.length > 1)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        final removed = _paymentMethods.removeAt(index);
                        removed.dispose();
                      });
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: const Color(0xFFDC2626),
                    tooltip: isRtl ? 'הסר' : 'Remove',
                  ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1976D2),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(methodIcon, color: const Color(0xFF1976D2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRtl
                          ? 'אמצעי תשלום ${index + 1}'
                          : 'Payment method ${index + 1}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      methodLabel,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => entry.isExpanded = false);
                },
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                tooltip: isRtl ? 'כווץ' : 'Collapse',
              ),
              if (_paymentMethods.length > 1)
                IconButton(
                  onPressed: () {
                    setState(() {
                      final removed = _paymentMethods.removeAt(index);
                      removed.dispose();
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFDC2626),
                  tooltip: isRtl ? 'הסר' : 'Remove',
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: entry.method,
            decoration: _inputStyle(
              isRtl ? 'אמצעי תשלום' : 'Payment Method',
              methodIcon,
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
              const DropdownMenuItem(value: 'bit', child: Text('Bit')),
              const DropdownMenuItem(value: 'paybox', child: Text('PayBox')),
              DropdownMenuItem(
                value: 'other',
                child: Text(isRtl ? 'אחר' : 'Other'),
              ),
              DropdownMenuItem(
                value: 'withholding_tax',
                child: Text(isRtl ? 'ניכוי מס במקור' : 'Withholding Tax'),
              ),
              DropdownMenuItem(
                value: 'check',
                child: Text(isRtl ? 'צ׳ק' : 'Check'),
              ),
            ],
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                entry.method = val;
                if (val == 'credit' &&
                    entry.installmentsController.text.isEmpty) {
                  entry.installmentsController.text = '1';
                }
              });
            },
          ),
          if (entry.method == 'credit') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('credit-company-${entry.cardNameController.text}'),
              isExpanded: true,
              initialValue:
                  _creditCompanies.contains(entry.cardNameController.text)
                  ? entry.cardNameController.text
                  : null,
              decoration: _inputStyle(
                isRtl
                    ? 'חברת סליקה (אופציונלי)'
                    : 'Clearing Company (Optional)',
                Icons.badge_outlined,
              ),
              hint: Text(isRtl ? 'בחר חברת סליקה' : 'Select clearing company'),
              items: _creditCompanies
                  .map(
                    (company) => DropdownMenuItem(
                      value: company,
                      child: Text(
                        _creditCompanyLabel(company, isRtl),
                        textDirection: isRtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (company) {
                if (company == null) return;
                setState(() => entry.cardNameController.text = company);
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.cardNumberController,
              isRtl ? 'מספר כרטיס (אופציונלי)' : 'Card Number (Optional)',
              Icons.credit_card,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              entry.cardExpirationController,
              isRtl ? 'תוקף (MM/YY)' : 'Expiry Date (MM/YY)',
              Icons.date_range_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                TextInputFormatter.withFunction(_formatCardExpiration),
              ],
            ),
            const SizedBox(height: 12),
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus &&
                    entry.installmentsController.text.trim().isEmpty) {
                  setState(() => entry.installmentsController.text = '1');
                }
              },
              child: _buildTextField(
                entry.installmentsController,
                isRtl
                    ? 'מספר תשלומים (אופציונלי)'
                    : 'Number of Payments (Optional)',
                Icons.format_list_numbered,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final value = int.tryParse(newValue.text);
                    if (newValue.text.isNotEmpty &&
                        (value == null || value < 1)) {
                      return const TextEditingValue(
                        text: '1',
                        selection: TextSelection.collapsed(offset: 1),
                      );
                    }
                    return newValue;
                  }),
                ],
                onChanged: (value) {
                  final count = int.tryParse(value);
                  if (count == null || count < 1 || count > 999) return;
                  setState(() => entry.ensureCreditInstallmentCount(count));
                },
              ),
            ),
            if ((int.tryParse(entry.installmentsController.text.trim()) ?? 1) >
                1) ...[
              const SizedBox(height: 12),
              ...List.generate(
                entry.creditInstallmentDateControllers.length,
                (installmentIndex) => Padding(
                  padding: EdgeInsets.only(
                    bottom:
                        installmentIndex ==
                            entry.creditInstallmentDateControllers.length - 1
                        ? 0
                        : 12,
                  ),
                  child: _buildTextField(
                    entry.creditInstallmentDateControllers[installmentIndex],
                    isRtl
                        ? 'תאריך פירעון תשלום ${installmentIndex + 1}'
                        : 'Installment ${installmentIndex + 1} Due Date',
                    Icons.event_outlined,
                    required: true,
                    readOnly: true,
                    onTap: () =>
                        _pickCreditInstallmentDate(entry, installmentIndex),
                    suffixIcon: IconButton(
                      tooltip: isRtl ? 'בחירת תאריך' : 'Select date',
                      onPressed: () =>
                          _pickCreditInstallmentDate(entry, installmentIndex),
                      icon: const Icon(Icons.calendar_month_outlined),
                    ),
                  ),
                ),
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
              entry.checkPaymentDateController,
              isRtl ? 'תאריך פירעון (חובה)' : 'Check Due Date (Required)',
              Icons.event_outlined,
              required: true,
              readOnly: true,
              onTap: () => _pickCheckPaymentDate(entry),
              suffixIcon: IconButton(
                tooltip: isRtl ? 'בחירת תאריך' : 'Select date',
                onPressed: () => _pickCheckPaymentDate(entry),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ),
            const SizedBox(height: 12),
            _buildBankAutocomplete(entry, isRtl, isCheck: true),
            const SizedBox(height: 12),
            _buildBranchAutocomplete(entry, isRtl, isCheck: true),
            const SizedBox(height: 12),
            _buildTextField(
              entry.checkAccountController,
              isRtl ? 'חשבון בנק (חובה)' : 'Bank Account (Required)',
              Icons.account_balance_wallet_outlined,
              required: true,
            ),
          ],
          if (entry.method == 'transfer') ...[
            const SizedBox(height: 12),
            _buildBankAutocomplete(entry, isRtl),
            const SizedBox(height: 12),
            _buildBranchAutocomplete(entry, isRtl),
            const SizedBox(height: 12),
            _buildTextField(
              entry.transferAccountController,
              isRtl ? 'מספר חשבון (אופציונלי)' : 'Account Number (Optional)',
              Icons.account_balance,
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: _buildTextField(
              entry.amountController,
              isRtl ? 'סכום ששולם (חובה)' : 'Amount Paid (Required)',
              Icons.payments_outlined,
              required: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                FocusScope.of(context).unfocus();
                setState(() => entry.isExpanded = false);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankAutocomplete(
    _PaymentMethodEntry entry,
    bool isRtl, {
    bool isCheck = false,
  }) {
    final bankController = isCheck
        ? entry.checkBankController
        : entry.transferBankController;
    final bankFocusNode = isCheck
        ? entry.checkBankFocusNode
        : entry.transferBankFocusNode;
    final branchController = isCheck
        ? entry.checkBranchController
        : entry.transferBranchController;
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _clearInvalidBank(entry, isCheck: isCheck);
      },
      child: Autocomplete<String>(
        textEditingController: bankController,
        focusNode: bankFocusNode,
        displayStringForOption: (bank) => bank,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return _bankNames;
          return _bankNames.where((bank) => bank.toLowerCase().contains(query));
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) {
              setState(branchController.clear);
            },
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            decoration: _inputStyle(
              isCheck
                  ? (isRtl ? 'בנק (חובה)' : 'Bank Name (Required)')
                  : (isRtl ? 'בנק (אופציונלי)' : 'Bank Name (Optional)'),
              Icons.account_balance,
              required: isCheck,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final bankOptions = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  maxWidth: 420,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: bankOptions.length,
                  itemBuilder: (context, index) {
                    final bank = bankOptions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        bank,
                        textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        textDirection: isRtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                      ),
                      onTap: () => onSelected(bank),
                    );
                  },
                ),
              ),
            ),
          );
        },
        onSelected: (_) {
          setState(branchController.clear);
        },
      ),
    );
  }

  void _clearInvalidBank(_PaymentMethodEntry entry, {bool isCheck = false}) {
    final bankController = isCheck
        ? entry.checkBankController
        : entry.transferBankController;
    final branchController = isCheck
        ? entry.checkBranchController
        : entry.transferBranchController;
    final bank = bankController.text.trim();
    if (bank.isEmpty || _bankNames.contains(bank)) return;
    setState(() {
      bankController.clear();
      branchController.clear();
    });
  }

  String? _bankIdFromSelection(String bankName) {
    final matches = RegExp(r'\d+').allMatches(bankName).toList();
    return matches.isEmpty ? null : matches.last.group(0);
  }

  Widget _buildBranchAutocomplete(
    _PaymentMethodEntry entry,
    bool isRtl, {
    bool isCheck = false,
  }) {
    final bankController = isCheck
        ? entry.checkBankController
        : entry.transferBankController;
    final branchController = isCheck
        ? entry.checkBranchController
        : entry.transferBranchController;
    final branchFocusNode = isCheck
        ? entry.checkBranchFocusNode
        : entry.transferBranchFocusNode;
    final bankId = _bankIdFromSelection(bankController.text);
    final branches = bankId == null
        ? const <_BankBranch>[]
        : _branchesByBankId[bankId] ?? const <_BankBranch>[];
    final isBankSelected = bankId != null;

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _clearInvalidBranch(entry, isCheck: isCheck);
      },
      child: Autocomplete<_BankBranch>(
        key: ValueKey('${isCheck ? 'check' : 'transfer'}-branch-$bankId'),
        textEditingController: branchController,
        focusNode: branchFocusNode,
        displayStringForOption: (branch) => branch.label,
        optionsBuilder: (textEditingValue) {
          if (!isBankSelected) return const Iterable<_BankBranch>.empty();
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return branches;
          return branches.where(
            (branch) => branch.label.toLowerCase().contains(query),
          );
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: isBankSelected,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            decoration:
                _inputStyle(
                  isCheck
                      ? (isRtl ? 'סניף (חובה)' : 'Branch (Required)')
                      : (isRtl ? 'סניף (אופציונלי)' : 'Branch (Optional)'),
                  Icons.store_mall_directory_outlined,
                  required: isCheck,
                ).copyWith(
                  hintText: _isLoadingBankBranches
                      ? (isRtl ? 'טוען סניפים...' : 'Loading branches...')
                      : !isBankSelected
                      ? (isRtl ? 'בחר בנק תחילה' : 'Select a bank first')
                      : branches.isEmpty
                      ? (isRtl ? 'לא נמצאו סניפים' : 'No branches found')
                      : null,
                ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final branchOptions = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  maxWidth: 420,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: branchOptions.length,
                  itemBuilder: (context, index) {
                    final branch = branchOptions[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        branch.label,
                        textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        textDirection: isRtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                      ),
                      onTap: () => onSelected(branch),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _clearInvalidBranch(_PaymentMethodEntry entry, {bool isCheck = false}) {
    final bankController = isCheck
        ? entry.checkBankController
        : entry.transferBankController;
    final branchController = isCheck
        ? entry.checkBranchController
        : entry.transferBranchController;
    final branch = branchController.text.trim();
    if (branch.isEmpty) return;
    final bankId = _bankIdFromSelection(bankController.text);
    final branches = bankId == null
        ? const <_BankBranch>[]
        : _branchesByBankId[bankId] ?? const <_BankBranch>[];
    if (branches.any((availableBranch) => availableBranch.label == branch)) {
      return;
    }
    setState(branchController.clear);
  }

  Set<String> _linkableDocumentTypes(String docType) {
    switch (docType) {
      case 'quote':
        return const {};
      case 'work_order':
        return const {'quote'};
      case 'transaction_account':
        return const {'quote', 'work_order'};
      case 'invoice':
        return const {'quote', 'work_order', 'transaction_account'};
      case 'invoice_receipt':
        return const {'quote', 'work_order', 'transaction_account'};
      case 'credit_note':
        return const {'invoice', 'invoice_receipt'};
      case 'receipt':
      default:
        return const {'invoice', 'transaction_account'};
    }
  }

  bool _documentBelongsToSelectedClient(Map<String, dynamic> data) {
    final selectedClientId = _selectedSavedClientId?.trim() ?? '';
    if (selectedClientId.isEmpty) return false;

    final savedClientId = (data['savedClientId'] ?? '').toString().trim();
    if (savedClientId.isNotEmpty) return savedClientId == selectedClientId;

    final selectedExternalNumber =
        _selectedSavedClientExternalNumber?.trim() ?? '';
    final externalNumber = (data['externalClientNumber'] ?? '')
        .toString()
        .trim();
    if (selectedExternalNumber.isNotEmpty && externalNumber.isNotEmpty) {
      return selectedExternalNumber == externalNumber;
    }

    final selectedTaxId = _clientIdController.text.trim();
    final taxId = (data['clientTaxId'] ?? '').toString().trim();
    if (selectedTaxId.isNotEmpty && taxId.isNotEmpty) {
      return selectedTaxId == taxId;
    }

    final selectedName = _clientNameController.text.trim().toLowerCase();
    final clientName = (data['clientName'] ?? data['receiverName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return selectedName.isNotEmpty && selectedName == clientName;
  }

  bool _isInvoiceFullyPaid(Map<String, dynamic> data) {
    final paymentStatus = (data['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (paymentStatus == 'paid') return true;

    final totalAmount = ((data['amount'] as num?)?.toDouble() ?? 0).abs();
    final paidAmount = ((data['paidAmount'] as num?)?.toDouble() ?? 0).abs();
    return totalAmount > 0 && paidAmount + 0.01 >= totalAmount;
  }

  Set<String> _linkedIdsFromDocument(Map<String, dynamic> data) {
    final ids = <String>{};
    final rawIds = data['linkedDocumentIds'];
    if (rawIds is Iterable) {
      ids.addAll(
        rawIds
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
      );
    }

    final rawReferences = data['linkedDocuments'];
    if (rawReferences is Iterable) {
      for (final reference in rawReferences) {
        if (reference is! Map) continue;
        final id = (reference['invoiceDocId'] ?? reference['id'] ?? '')
            .toString()
            .trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  Future<List<_LinkedInvoiceDocument>> _loadLinkableDocuments() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedSavedClientId == null) return const [];

    final compatibleTypes = _linkableDocumentTypes(_selectedDocType);
    if (compatibleTypes.isEmpty) return const [];
    final queryTypes = _selectedDocType == 'receipt'
        ? {...compatibleTypes, 'invoice_receipt'}
        : compatibleTypes;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('invoices')
        .where('docType', whereIn: queryTypes.toList())
        .get();

    final clientDocuments = snapshot.docs
        .where((document) => _documentBelongsToSelectedClient(document.data()))
        .toList();
    final proformasLinkedToInvoices = <String>{};
    if (_selectedDocType == 'receipt') {
      for (final document in clientDocuments) {
        final docType = (document.data()['docType'] ?? '').toString();
        if (docType == 'invoice' || docType == 'invoice_receipt') {
          proformasLinkedToInvoices.addAll(
            _linkedIdsFromDocument(document.data()),
          );
        }
      }
    }

    final documents = clientDocuments
        .where((document) {
          final data = document.data();
          final docType = (data['docType'] ?? '').toString();
          if (!compatibleTypes.contains(docType)) return false;
          if (_selectedDocType != 'receipt') return true;
          if (docType == 'invoice') return !_isInvoiceFullyPaid(data);
          if (docType == 'transaction_account') {
            return !proformasLinkedToInvoices.contains(document.id);
          }
          return true;
        })
        .map(_LinkedInvoiceDocument.fromDocument)
        .toList();
    documents.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return documents;
  }

  Future<void> _showLinkedDocumentsPopup(Map<String, String> strings) async {
    if (_selectedSavedClientId == null || !mounted) return;

    _clientNameFocusNode.unfocus();
    final selected = await showDialog<List<_LinkedInvoiceDocument>>(
      context: context,
      builder: (dialogContext) => _LinkedDocumentsDialog(
        strings: strings,
        loadDocuments: _loadLinkableDocuments,
        initiallySelected: _linkedDocuments,
        documentTypeLabel: (docType) =>
            _documentTypeDisplayName(strings, docType),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _linkedDocuments
        ..clear()
        ..addEntries(
          selected.map((document) => MapEntry(document.id, document)),
        );
    });
  }

  void _applySavedClient(_InvoiceClient client) {
    setState(() {
      if (_selectedSavedClientId != client.id) {
        _linkedDocuments.clear();
      }
      _selectedSavedClientId = client.id;
      _selectedSavedClientExternalNumber = client.externalClientNumber;
      _clientNameController.text = client.name;
      _clientIdController.text = client.taxId;
      _clientPhoneController.text = client.phone;
      _clientEmailController.text = client.email;
      _clientAddressController.text = client.address;
    });
    _clientNameFocusNode.unfocus();
  }

  Future<void> _showAddClientPopup(Map<String, String> strings) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isAddingClient) return;

    _isAddingClient = true;
    final initialName = _clientNameController.text.trim();
    _clientNameFocusNode.unfocus();

    final client = await showDialog<_InvoiceClient>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AddInvoiceClientDialog(
        strings: strings,
        initialName: initialName,
        userId: user.uid,
      ),
    );

    _isAddingClient = false;
    if (!mounted) return;
    if (client != null) {
      _applySavedClient(client);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings['client_added']!),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (_selectedSavedClientId == null) {
      setState(() {
        _clientNameController.clear();
        _clientIdController.clear();
        _clientPhoneController.clear();
        _clientEmailController.clear();
        _clientAddressController.clear();
      });
    }
  }

  void _handleClientNameChanged(String _) {
    if (_selectedSavedClientId == null) return;
    setState(() {
      _selectedSavedClientId = null;
      _selectedSavedClientExternalNumber = null;
      _linkedDocuments.clear();
      _clientIdController.clear();
      _clientPhoneController.clear();
      _clientEmailController.clear();
      _clientAddressController.clear();
    });
  }

  void _handleClientNameFocusChanged() {
    if (_clientNameFocusNode.hasFocus ||
        _selectedSavedClientId != null ||
        _isAddingClient) {
      return;
    }
    if (_clientNameController.text.isEmpty) return;

    setState(() {
      _linkedDocuments.clear();
      _clientNameController.clear();
      _clientIdController.clear();
      _clientPhoneController.clear();
      _clientEmailController.clear();
      _clientAddressController.clear();
    });
  }

  Widget _buildClientPicker(Map<String, String> strings) {
    final clientsStream = _savedClientsStream;
    if (clientsStream == null) {
      return _buildTextField(
        _clientNameController,
        strings['client_name']!,
        Icons.person_outline,
        required: true,
        focusNode: _clientNameFocusNode,
        onChanged: _handleClientNameChanged,
        suffixIcon: IconButton(
          tooltip: strings['add_client'],
          onPressed: () => _showAddClientPopup(strings),
          icon: const Icon(Icons.add_rounded),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: clientsStream,
      builder: (context, snapshot) {
        final clients =
            snapshot.data?.docs
                .map(_InvoiceClient.fromDocument)
                .where((client) => client.name.isNotEmpty)
                .toList() ??
            <_InvoiceClient>[];
        clients.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            return RawAutocomplete<_InvoiceClient>(
              textEditingController: _clientNameController,
              focusNode: _clientNameFocusNode,
              displayStringForOption: (client) => client.name,
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.trim().toLowerCase();
                if (query.isEmpty) return const <_InvoiceClient>[];
                return clients
                    .where((client) => client.searchText.contains(query))
                    .take(6);
              },
              onSelected: _applySavedClient,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    return _buildTextField(
                      controller,
                      strings['client_name']!,
                      Icons.person_outline,
                      required: true,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: _handleClientNameChanged,
                      onSubmitted: (_) => onFieldSubmitted(),
                      suffixIcon: IconButton(
                        tooltip: strings['add_client'],
                        onPressed: () => _showAddClientPopup(strings),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    );
                  },
              optionsViewBuilder: (context, onSelected, options) {
                final matches = options.toList();
                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    color: Colors.white,
                    elevation: 10,
                    shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: matches.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 64,
                            endIndent: 12,
                          ),
                          itemBuilder: (context, index) {
                            final client = matches[index];
                            return ListTile(
                              onTap: () => onSelected(client),
                              leading: CircleAvatar(
                                radius: 19,
                                backgroundColor: const Color(0xFFEAF4FF),
                                child: Text(
                                  client.name.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF1976D2),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              title: Text(
                                client.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              subtitle: client.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      client.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: const Icon(
                                Icons.north_west_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
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
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: _inputStyle(
        label,
        icon,
        required: required,
      ).copyWith(suffixIcon: suffixIcon),
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

class _AddInvoiceClientDialog extends StatefulWidget {
  const _AddInvoiceClientDialog({
    required this.strings,
    required this.initialName,
    required this.userId,
  });

  final Map<String, String> strings;
  final String initialName;
  final String userId;

  @override
  State<_AddInvoiceClientDialog> createState() =>
      _AddInvoiceClientDialogState();
}

class _AddInvoiceClientDialogState extends State<_AddInvoiceClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _externalClientNumberController;
  final _taxIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _externalClientNumberController = TextEditingController(
      text: ClientService.generateExternalClientNumber(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _externalClientNumberController.dispose();
    _taxIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final taxId = _taxIdController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final address = _addressController.text.trim();
    final externalClientNumber = ClientService.normalizeExternalClientNumber(
      _externalClientNumberController.text,
    );

    try {
      final clientId = await ClientService.saveClient(
        userId: widget.userId,
        externalClientNumber: externalClientNumber,
        clientData: {
          'name': name,
          'nameLowercase': name.toLowerCase(),
          'taxId': taxId,
          'phone': phone,
          'email': email,
          'address': address,
          'notes': '',
        },
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _InvoiceClient(
          id: clientId,
          name: name,
          externalClientNumber: externalClientNumber,
          taxId: taxId,
          phone: phone,
          email: email,
          address: address,
        ),
      );
    } on ClientNumberConflictException {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = widget.strings['client_number_duplicate'];
      });
    } on ClientTaxIdConflictException {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = widget.strings['client_id_duplicate'];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = widget.strings['client_save_failed'];
      });
    }
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final availableHeight = (MediaQuery.sizeOf(context).height - 48).clamp(
      360.0,
      720.0,
    );

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 520,
        height: availableHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.2),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings['add_client']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings['client_info']!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: strings['cancel'],
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: 0.08,
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF1976D2),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                strings['client_details_required']!,
                                style: const TextStyle(
                                  color: Color(0xFF1E40AF),
                                  fontSize: 13,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        autofocus: widget.initialName.isEmpty,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          '${strings['client_name']!} *',
                          Icons.person_outline_rounded,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? strings['client_details_required']
                            : null,
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _taxIdController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        decoration: _decoration(
                          strings['client_id']!,
                          Icons.badge_outlined,
                        ),
                        validator: (value) {
                          final id = value?.trim() ?? '';
                          if (id.isEmpty) return null;
                          if (id.length != 9) {
                            return strings['client_id_invalid_length'];
                          }
                          return isValidIsraeliId(id)
                              ? null
                              : strings['client_id_invalid'];
                        },
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          strings['client_phone']!,
                          Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          strings['client_email']!,
                          Icons.email_outlined,
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return null;
                          return RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(email)
                              ? null
                              : strings['invalid_email'];
                        },
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _addressController,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          strings['client_address']!,
                          Icons.location_on_outlined,
                        ),
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: _externalClientNumberController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: _decoration(
                          '${strings['external_client_number']!} *',
                          Icons.tag_rounded,
                          helperText: strings['external_client_number_hint'],
                        ),
                        validator: (value) =>
                            ClientService.isValidExternalClientNumber(
                              value ?? '',
                            )
                            ? null
                            : strings['external_client_number_invalid'],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFCFF),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: Text(strings['cancel']!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(strings['save_client']!),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(
                          0xFF1976D2,
                        ).withValues(alpha: 0.6),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TaxAuthorityConnectionChoice {
  alreadyConnected,
  continueWithoutAllocation,
  connect,
}

class InvoicePreviewPage extends StatefulWidget {
  final Uint8List pdfBytes;
  final String fileName;
  final Future<Uint8List?> Function() onSave;
  final Future<Uint8List?> Function()? onSaveWithoutAllocation;
  final bool requireTaxAuthorityConnectionPrompt;
  final Future<bool> Function()? isTaxAuthorityConnected;
  final Future<void> Function()? onConnectTaxAuthority;
  final Future<void> Function()? onSendForSignature;
  final Future<void> Function()? onSend;
  final VoidCallback? onReturnAfterSave;

  const InvoicePreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.onSave,
    this.onSaveWithoutAllocation,
    this.requireTaxAuthorityConnectionPrompt = false,
    this.isTaxAuthorityConnected,
    this.onConnectTaxAuthority,
    this.onSendForSignature,
    this.onSend,
    this.onReturnAfterSave,
  });

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage>
    with WidgetsBindingObserver {
  bool _isSaved = false;
  bool _isSaving = false;
  bool _isSending = false;
  bool _isSendingForSignature = false;
  bool _waitingForTaxAuthorityReturn = false;
  late Uint8List _pdfBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pdfBytes = widget.pdfBytes;
    if (widget.requireTaxAuthorityConnectionPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTaxAuthorityConnectionPromptIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForTaxAuthorityReturn) {
      unawaited(_refreshTaxAuthorityConnectionAfterReturn());
    }
  }

  Future<void> _refreshTaxAuthorityConnectionAfterReturn() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final connected = await widget.isTaxAuthorityConnected?.call() ?? false;
    if (!mounted) return;
    _waitingForTaxAuthorityReturn = false;
    if (!connected) return;

    final languageCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = languageCode == 'he' || languageCode == 'ar';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isRtl
              ? 'החיבור לרשות המסים הושלם. אפשר לשמור את החשבונית עם מספר הקצאה.'
              : 'Tax Authority connected. You can now save the invoice with an allocation number.',
        ),
      ),
    );
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

  Future<void> _handleSend() async {
    if (_isSending) return;
    if (widget.onSend == null) {
      Navigator.pop(context, 'send');
      return;
    }

    setState(() => _isSending = true);
    try {
      await widget.onSend!.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlySaveError(e))));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _handleBack() {
    if (_isSaved && widget.onReturnAfterSave != null) {
      widget.onReturnAfterSave!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Widget _buildTaxAuthorityConnectionSheet(
    BuildContext sheetContext, {
    required bool isRtl,
    required bool requiredForSave,
  }) {
    final title = isRtl ? 'חיבור לרשות המסים' : 'Connect to the Tax Authority';
    final message = requiredForSave
        ? (isRtl
              ? 'אינך מחובר לרשות המסים, ולכן לא ניתן לקבל מספר הקצאה לחשבונית הזו. אפשר להמשיך ולשמור ללא מספר הקצאה, או להתחבר לרשות המסים כדי לקבל מספר.'
              : 'You are not connected to the Tax Authority, so this invoice cannot receive an allocation number. You can continue and save without one, or connect to the Tax Authority to receive one.')
        : (isRtl
              ? 'החשבונית הזו מחייבת מספר הקצאה מרשות המסים. התחברו כדי לקבל אותו ולהמשיך בתהליך.'
              : 'This invoice requires a Tax Authority allocation number. Connect to receive it and continue.');
    final continueLabel = isRtl
        ? 'להמשיך ללא מספר הקצאה'
        : 'Continue without an allocation number';

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Color(0xFF1976D2),
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 23,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_new_rounded,
                      color: Color(0xFF0284C7),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      isRtl
                          ? 'ייפתח עמוד מאובטח של רשות המסים. לאחר השלמת החיבור חזרו ל-Hiro.'
                          : 'A secure Tax Authority page will open. Return to Hiro after completing the connection.',
                      style: const TextStyle(
                        color: Color(0xFF075985),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                sheetContext,
                _TaxAuthorityConnectionChoice.continueWithoutAllocation,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 21),
              label: Text(continueLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                sheetContext,
                _TaxAuthorityConnectionChoice.connect,
              ),
              icon: const Icon(Icons.link_rounded, size: 21),
              label: Text(
                isRtl ? 'התחברות לרשות המסים' : 'Connect to Tax Authority',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<_TaxAuthorityConnectionChoice?>
  _showTaxAuthorityConnectionPromptIfNeeded({
    bool requiredForSave = false,
  }) async {
    if (!mounted) return null;
    final isConnected = await widget.isTaxAuthorityConnected?.call() ?? true;
    if (!mounted || isConnected) {
      return _TaxAuthorityConnectionChoice.alreadyConnected;
    }

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

    final choice = await showModalBottomSheet<_TaxAuthorityConnectionChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: _buildTaxAuthorityConnectionSheet(
          sheetContext,
          isRtl: isRtl,
          requiredForSave: requiredForSave,
        ),
      ),
    );

    if (choice == _TaxAuthorityConnectionChoice.connect) {
      _waitingForTaxAuthorityReturn = true;
      try {
        await widget.onConnectTaxAuthority?.call();
      } catch (_) {
        _waitingForTaxAuthorityReturn = false;
        rethrow;
      }
    }
    return choice;
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
          final choice = await _showTaxAuthorityConnectionPromptIfNeeded(
            requiredForSave: true,
          );
          if (choice !=
              _TaxAuthorityConnectionChoice.continueWithoutAllocation) {
            return;
          }
        }
      }
      final connected = await widget.isTaxAuthorityConnected?.call() ?? true;
      final saveWithoutAllocation =
          widget.requireTaxAuthorityConnectionPrompt && !connected;
      if (saveWithoutAllocation && widget.onSaveWithoutAllocation == null) {
        throw StateError('Saving without an allocation number is unavailable.');
      }
      final savedPdfBytes = saveWithoutAllocation
          ? await widget.onSaveWithoutAllocation!.call()
          : await widget.onSave();
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
      child: PopScope(
        canPop: !(_isSaved && widget.onReturnAfterSave != null),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _isSaved && widget.onReturnAfterSave != null) {
            widget.onReturnAfterSave!();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: _handleBack),
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
                          onPressed: _isSending ? null : _handleSend,
                          icon: _isSending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(
                            _isSending
                                ? (isRtl ? 'שולח...' : 'Sending...')
                                : (isRtl ? 'שלח' : 'Send'),
                          ),
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
      ),
    );
  }
}
