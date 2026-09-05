import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/profile_document_service.dart';
import 'package:untitled1/utils/tax_authority_error_localizer.dart';

class SavedInvoicesPage extends StatefulWidget {
  const SavedInvoicesPage({super.key, this.initialSearchQuery = ''});

  final String initialSearchQuery;

  @override
  State<SavedInvoicesPage> createState() => _SavedInvoicesPageState();
}

class _SavedInvoicesPageState extends State<SavedInvoicesPage> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _invoicesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _receivedInvoicesStream;
  bool _isLoadingReceivedInvoices = true;
  bool _hasReceivedInvoicePhone = false;
  bool _canCreateTaxDocuments = false;
  String _searchQuery = '';
  String _selectedDocType = 'all';
  DateTimeRange? _selectedDateRange;
  _InvoiceScope _selectedScope = _InvoiceScope.createdByMe;
  final Set<String> _generatingSigningLinks = <String>{};
  final Set<String> _retryingDocuments = <String>{};
  final Set<String> _expandedCreateActions = <String>{};
  final Set<String> _updatingDocumentLocks = <String>{};

  String _paymentStatusLabel(String? status, bool isRtl) {
    switch (status) {
      case 'paid':
        return isRtl ? 'שולם' : 'Paid';
      case 'partial':
        return isRtl ? 'שולם חלקית' : 'Partly Paid';
      case 'unpaid':
      default:
        return isRtl ? 'עדיין לא שולם' : 'Still Not Paid';
    }
  }

  Color _paymentStatusColor(String? status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF15803D);
      case 'partial':
        return const Color(0xFFD97706);
      case 'unpaid':
      default:
        return const Color(0xFFB91C1C);
    }
  }

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery.trim();
    _searchController = TextEditingController(text: _searchQuery);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _invoicesStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices')
          .orderBy('createdAt', descending: true)
          .snapshots();
      _loadReceivedInvoicesStream(user);
      _loadTaxDocumentEligibility(user.uid);
    }
    _searchController.addListener(_handleSearchChanged);
  }

  Future<void> _loadTaxDocumentEligibility(String userId) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId);
      final results = await Future.wait([
        userRef.get(),
        userRef.collection('verification_info').doc('latest').get(),
      ]);
      final userData = results[0].data() ?? <String, dynamic>{};
      final verificationData = results[1].data() ?? <String, dynamic>{};
      final dealerType =
          (verificationData['dealerType'] ??
                  userData['dealerType'] ??
                  userData['businessType'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();
      if (!mounted) return;
      setState(() {
        _canCreateTaxDocuments =
            dealerType == 'licensed' ||
            dealerType == 'company' ||
            dealerType.contains('licensed') ||
            dealerType.contains('company') ||
            dealerType.contains('מורשה') ||
            dealerType.contains('חברה');
      });
    } catch (_) {
      // Tax-document actions stay hidden until the business type is known.
    }
  }

  Future<void> _loadReceivedInvoicesStream(User user) async {
    final rawPhones = <String>{user.phoneNumber ?? ''};

    try {
      final userData = await ProfileDocumentService.load(user.uid);
      rawPhones
        ..add((userData['phone'] ?? '').toString())
        ..add((userData['phoneNumber'] ?? '').toString());
    } catch (_) {
      // The auth phone is enough for the common path; profile loading is a
      // best-effort expansion for older data formats.
    }

    final phoneCandidates = <String>{};
    for (final phone in rawPhones) {
      phoneCandidates.addAll(_phoneCandidates(phone));
    }

    if (phoneCandidates.isNotEmpty) {
      await _syncReceivedInvoices();
    }

    if (!mounted) return;
    setState(() {
      _hasReceivedInvoicePhone = phoneCandidates.isNotEmpty;
      _isLoadingReceivedInvoices = false;
      _receivedInvoicesStream = phoneCandidates.isEmpty
          ? null
          : FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('receivedInvoices')
                .orderBy('createdAt', descending: true)
                .snapshots();
    });
  }

  Future<void> _syncReceivedInvoices() async {
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('syncReceivedInvoices').call();
    } catch (_) {
      // Sync is best effort. The stream below still shows anything already
      // mirrored by the backend trigger.
    }
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text;
    if (_searchQuery == nextQuery) return;
    setState(() {
      _searchQuery = nextQuery;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleDocumentLinkLock({
    required String invoiceDocId,
    required String documentName,
    required bool isCurrentlyLocked,
    required bool isRtl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _updatingDocumentLocks.contains(invoiceDocId)) return;

    final nextIsLocked = !isCurrentlyLocked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IconButton(
                      tooltip: isRtl ? 'סגירה' : 'Close',
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF64748B),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: nextIsLocked
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFFEFF6FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        nextIsLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: nextIsLocked
                            ? const Color(0xFF334155)
                            : const Color(0xFF1976D2),
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    nextIsLocked
                        ? (isRtl ? 'לנעול את המסמך?' : 'Lock this document?')
                        : (isRtl
                              ? 'לפתוח את נעילת המסמך?'
                              : 'Unlock this document?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    nextIsLocked
                        ? (isRtl
                              ? 'המסמך יוסתר מרשימת המסמכים לקישור, ולא יהיה ניתן ליצור ממנו מסמכים נוספים.'
                              : 'This document will be hidden from linked documents and you will not be able to create another document from it.')
                        : (isRtl
                              ? 'המסמך יהיה זמין שוב לקישור וליצירת מסמכים נוספים.'
                              : 'This document will be available again for linking and creating related documents.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  if (documentName.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.description_outlined,
                            color: Color(0xFF64748B),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              documentName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF475569),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(isRtl ? 'ביטול' : 'Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: nextIsLocked
                                ? const Color(0xFF334155)
                                : const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: Icon(
                            nextIsLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 19,
                          ),
                          label: Text(
                            nextIsLocked
                                ? (isRtl ? 'נעילת מסמך' : 'Lock Document')
                                : (isRtl ? 'פתיחת נעילה' : 'Unlock Document'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final wasExpanded = _expandedCreateActions.contains(invoiceDocId);
    setState(() {
      _updatingDocumentLocks.add(invoiceDocId);
      if (nextIsLocked) {
        _expandedCreateActions.remove(invoiceDocId);
      }
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('invoices')
          .doc(invoiceDocId)
          .update({
            'isLinkingLocked': nextIsLocked,
            'linkLockUpdatedAt': FieldValue.serverTimestamp(),
          });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasExpanded) _expandedCreateActions.add(invoiceDocId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא ניתן לעדכן את נעילת המסמך. נסו שוב.'
                : 'Could not update the document lock. Please try again.',
          ),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
      debugPrint('Document link lock update failed: ${error.code}');
    } finally {
      if (mounted) {
        setState(() => _updatingDocumentLocks.remove(invoiceDocId));
      }
    }
  }

  String _docTypeLabel(String? docType, bool isRtl) {
    switch (docType) {
      case 'quote':
        return isRtl ? 'הצעת מחיר' : 'Quote';
      case 'work_order':
        return isRtl ? 'הזמנת עבודה' : 'Work Order';
      case 'transaction_account':
        return isRtl ? 'חשבון עסקה' : 'Proforma Invoice';
      case 'invoice':
        return isRtl ? 'חשבונית' : 'Invoice';
      case 'invoice_receipt':
        return isRtl ? 'חשבונית / קבלה' : 'Invoice / Receipt';
      case 'credit_note':
        return isRtl ? 'זיכוי' : 'Credit Note';
      case 'receipt':
        return isRtl ? 'קבלה' : 'Receipt';
      default:
        return isRtl ? 'מסמך' : 'Document';
    }
  }

  Color _docTypeColor(String? docType) {
    switch (docType) {
      case 'quote':
        return const Color(0xFF00897B);
      case 'work_order':
        return const Color(0xFF6D4C41);
      case 'transaction_account':
        return const Color(0xFF5E35B1);
      case 'invoice':
        return const Color(0xFF1565C0);
      case 'invoice_receipt':
        return const Color(0xFF2E7D32);
      case 'credit_note':
        return const Color(0xFF8E24AA);
      case 'receipt':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF546E7A);
    }
  }

  String _signatureStatusLabel(String status, bool isRtl) {
    switch (status) {
      case 'signed':
        return isRtl ? 'נחתם' : 'Signed';
      case 'pending':
        return isRtl ? 'ממתין לחתימה' : 'Awaiting Signature';
      default:
        return isRtl ? 'טרם נחתם' : 'Not Signed';
    }
  }

  Color _signatureStatusColor(String status) {
    switch (status) {
      case 'signed':
        return const Color(0xFF15803D);
      case 'pending':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _documentWorkflowLabel(String status, bool isRtl) {
    switch (status) {
      case 'generation_failed':
        return isRtl ? 'הפקת המסמך נכשלה' : 'Generation failed';
      case 'reserved':
        return isRtl ? 'המספר נשמר' : 'Number reserved';
      case 'allocating':
        return isRtl ? 'מבקש הקצאה' : 'Requesting allocation';
      case 'allocation_approved':
        return isRtl ? 'ממתין לסיום' : 'Finishing document';
      case 'allocation_failed':
        return isRtl ? 'ההקצאה נכשלה' : 'Allocation failed';
      case 'decision_required':
        return isRtl ? 'נדרשת החלטה' : 'Decision required';
      case 'hearing_requested':
        return isRtl ? 'ממתין לשימוע' : 'Awaiting hearing';
      case 'reverse_charge_requested':
      case 'reverse_charge_reserved':
        return isRtl ? 'היפוך חיוב בתהליך' : 'Reverse charge in progress';
      case 'reverse_charge_rejected':
        return isRtl ? 'היפוך החיוב נדחה' : 'Reverse charge rejected';
      case 'allocation_cancelled':
        return isRtl ? 'בקשת ההקצאה בוטלה' : 'Allocation cancelled';
      case 'continued_without_allocation':
        return isRtl ? 'המשך ללא הקצאה' : 'Continued without allocation';
      case 'needs_reconciliation':
        return isRtl ? 'נדרשת בדיקה' : 'Needs review';
      case 'finalized':
        return isRtl ? 'הושלם' : 'Finalized';
      default:
        return isRtl ? 'בתהליך' : 'Processing';
    }
  }

  Color _documentWorkflowColor(String status) {
    switch (status) {
      case 'finalized':
        return const Color(0xFF15803D);
      case 'allocation_failed':
      case 'generation_failed':
      case 'needs_reconciliation':
      case 'allocation_cancelled':
      case 'reverse_charge_rejected':
        return const Color(0xFFB91C1C);
      case 'continued_without_allocation':
      case 'decision_required':
      case 'hearing_requested':
      case 'reverse_charge_requested':
      case 'reverse_charge_reserved':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFFD97706);
    }
  }

  bool _canRetryDocumentGeneration(Map<String, dynamic> data) {
    if (data['serverDocument'] is! Map) return false;
    final status = (data['documentStatus'] ?? '').toString().trim();
    if (status == 'generation_failed') return true;
    if (status != 'processing') return false;
    final serverDocument = Map<String, dynamic>.from(
      data['serverDocument'] as Map,
    );
    final startedAt = serverDocument['startedAt'];
    if (startedAt is! Timestamp) return true;
    return DateTime.now().difference(startedAt.toDate()) >=
        const Duration(minutes: 5);
  }

  Future<void> _retryDocumentGeneration(String invoiceDocId, bool isRtl) async {
    if (_retryingDocuments.contains(invoiceDocId)) return;
    setState(() => _retryingDocuments.add(invoiceDocId));
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'me-west1',
      ).httpsCallable('createServerDocument');
      final result = await callable.call<Map<String, dynamic>>({
        'retryInvoiceDocId': invoiceDocId,
      });
      final document = result.data['document'];
      if (result.data['finalized'] != true || document is! Map) {
        throw StateError('The recovered document was not finalized.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'המסמך הופק בהצלחה עם המספר המקורי.'
                : 'The document was generated with its original number.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final details = error is FirebaseFunctionsException
          ? error.details
          : null;
      final requiresReview =
          details is Map && details['needsReconciliation'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requiresReview && isRtl
                ? 'המסמך הועבר לבדיקה. המספר נשמר ואין ליצור מסמך חדש במקומו.'
                : requiresReview
                ? 'The document was sent for review. Its number remains reserved; do not create a replacement.'
                : isRtl
                ? 'הניסיון החוזר נכשל. המספר עדיין שמור ואפשר לנסות שוב מאוחר יותר.'
                : 'Retry failed. The number remains reserved; try again later.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _retryingDocuments.remove(invoiceDocId));
      }
    }
  }

  Future<void> _retryTaxAuthorityAllocation(
    String invoiceDocId,
    bool isRtl,
  ) async {
    if (_retryingDocuments.contains(invoiceDocId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isRtl ? 'לבקש מספר הקצאה שוב?' : 'Request allocation again?',
        ),
        content: Text(
          isRtl
              ? 'הבקשה תישלח עם פרטי החשבונית השמורים, ללא שינוי במספר החשבונית או בפרטי העסקה. יש לבצע פעולה זו רק לאחר שהשימוע ברשות המסים הסתיים.'
              : 'The request will use the saved invoice details without changing its number or transaction details. Only do this after the Tax Authority hearing has finished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isRtl ? 'ביטול' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isRtl ? 'בקש שוב' : 'Request again'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _retryingDocuments.add(invoiceDocId));
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'me-west1')
          .httpsCallable('requestTaxInvoiceAllocation')
          .call<Map<String, dynamic>>({'draftId': invoiceDocId});
      if (!mounted) return;
      if (result.data['decisionRequired'] == true) {
        await _showTaxAuthorityDecision(
          invoiceDocId: invoiceDocId,
          isRtl: isRtl,
          errors: result.data['errors'],
        );
        return;
      }
      final approved = result.data['approved'] == true;
      final document = result.data['document'];
      if (!approved || document is! Map) {
        throw StateError(
          'The Tax Authority did not return an allocation number.',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'מספר ההקצאה התקבל והחשבונית הופקה.'
                : 'The allocation number was received and the invoice was generated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FirebaseFunctionsException
          ? error.message
          : error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא ניתן היה לבקש מספר הקצאה מחדש: ${message ?? ''}'
                : 'Could not request an allocation number again: ${message ?? ''}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _retryingDocuments.remove(invoiceDocId));
    }
  }

  Future<void> _showTaxAuthorityDecision({
    required String invoiceDocId,
    required bool isRtl,
    required dynamic errors,
  }) async {
    final errorText = errors is List
        ? errors
              .map(
                (error) =>
                    error is Map ? (error['message'] ?? error['code']) : error,
              )
              .whereType<Object>()
              .join('\n')
        : '';
    final decision = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isRtl
                    ? 'לא התקבל מספר הקצאה'
                    : 'No allocation number was issued',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isRtl
                    ? 'רשות המסים עיכבה את החשבונית. בחרו כיצד להמשיך.'
                    : 'The Tax Authority held this invoice. Choose how you want to continue.',
                textAlign: TextAlign.center,
              ),
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  errorText,
                  style: const TextStyle(color: Color(0xFF92400E)),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(sheetContext, 'further_objection'),
                child: Text(isRtl ? 'בקשת שימוע' : 'Request a hearing'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, 'continue'),
                child: Text(
                  isRtl
                      ? 'המשך ללא מספר הקצאה'
                      : 'Continue without an allocation number',
                ),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, 'reverse_charge'),
                child: Text(
                  isRtl
                      ? 'היפוך חיוב – הלקוח מדווח את המע״מ'
                      : 'Reverse charge — customer reports VAT',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                child: Text(
                  isRtl
                      ? 'ביטול והפקת חשבונית מס זיכוי'
                      : 'Cancel and create a Tax Invoice Credit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (decision == null || !mounted) return;

    Map<String, dynamic>? reverseChargeEvidence;
    if (decision == 'reverse_charge') {
      reverseChargeEvidence = await _collectReverseChargeEvidence(isRtl);
      if (reverseChargeEvidence == null || !mounted) return;
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'me-west1')
          .httpsCallable('submitTaxInvoiceDecision')
          .call<Map<String, dynamic>>({
            'draftId': invoiceDocId,
            'decision': decision,
            ...?(reverseChargeEvidence == null
                ? null
                : {'reverseChargeEvidence': reverseChargeEvidence}),
          });
      if (!mounted || result.data['accepted'] != true) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'further_objection'
                ? (isRtl
                      ? 'בקשת השימוע נרשמה. החשבונית ממתינה לבדיקה.'
                      : 'The hearing request was recorded. The invoice is awaiting review.')
                : (isRtl
                      ? 'הבחירה נשלחה לרשות המסים.'
                      : 'Your decision was sent to the Tax Authority.'),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final languageCode = Provider.of<LanguageProvider>(
        context,
        listen: false,
      ).locale.languageCode;
      final message =
          localizedTaxAuthorityConnectionError(error, languageCode) ??
          error.message ??
          taxAuthorityActionFailedMessage(languageCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 10)),
      );
    }
  }

  Future<Map<String, dynamic>?> _collectReverseChargeEvidence(
    bool isRtl,
  ) async {
    var dealerVerified = false;
    var customerConsented = false;
    String? consentMethod;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(isRtl ? 'אישור היפוך חיוב' : 'Confirm reverse charge'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: dealerVerified,
                onChanged: (value) =>
                    setDialogState(() => dealerVerified = value == true),
                title: Text(
                  isRtl
                      ? 'אישרתי שהלקוח עוסק מורשה פעיל.'
                      : 'I confirmed the customer is an active licensed dealer.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: customerConsented,
                onChanged: (value) =>
                    setDialogState(() => customerConsented = value == true),
                title: Text(
                  isRtl
                      ? 'אישרתי שהלקוח הסכים להיפוך החיוב.'
                      : 'I confirmed the customer agreed to reverse charge.',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: consentMethod,
                decoration: InputDecoration(
                  labelText: isRtl ? 'אופן קבלת ההסכמה' : 'Consent method',
                ),
                items:
                    const [
                          'email',
                          'signed_document',
                          'whatsapp',
                          'phone',
                          'other',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setDialogState(() => consentMethod = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(isRtl ? 'ביטול' : 'Cancel'),
            ),
            FilledButton(
              onPressed:
                  dealerVerified && customerConsented && consentMethod != null
                  ? () => Navigator.pop(dialogContext, {
                      'dealerVerificationConfirmed': true,
                      'customerConsentConfirmed': true,
                      'consentMethod': consentMethod,
                    })
                  : null,
              child: Text(isRtl ? 'המשך' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSigningLink(String invoiceDocId, bool isRtl) async {
    if (_generatingSigningLinks.contains(invoiceDocId)) return;

    setState(() => _generatingSigningLinks.add(invoiceDocId));
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createDocumentSigningRequest');
      final result = await callable.call(<String, dynamic>{
        'invoiceDocId': invoiceDocId,
      });
      final link = (result.data as Map<Object?, Object?>?)?['url']?.toString();
      if (link == null || link.isEmpty) {
        throw StateError('The signing link could not be created.');
      }

      await SharePlus.instance.share(
        ShareParams(
          text: isRtl
              ? 'נא לפתוח את המסמך ולחתום עליו:\n$link'
              : 'Please open and sign the document:\n$link',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא הצלחנו ליצור קישור לחתימה.'
                : 'Could not generate a signing link.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingSigningLinks.remove(invoiceDocId));
      }
    }
  }

  Future<void> _pickDateRange(bool isRtl) async {
    final now = DateTime.now();
    final initialRange =
        _selectedDateRange ??
        DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
      helpText: isRtl ? 'בחר טווח תאריכים' : 'Select date range',
      cancelText: isRtl ? 'ביטול' : 'Cancel',
      confirmText: isRtl ? 'אישור' : 'Apply',
      saveText: isRtl ? 'אישור' : 'Apply',
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedDateRange = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        ),
      );
    });
  }

  String _formatOriginalInvoiceDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length == 8) {
      try {
        final parsed = intl.DateFormat('yyyyMMdd').parseStrict(trimmed);
        return intl.DateFormat('dd/MM/yyyy').format(parsed);
      } catch (_) {}
    }
    return trimmed;
  }

  Map<String, dynamic> _linkedDocumentSeed(
    String sourceDocId,
    Map<String, dynamic> data,
  ) {
    final storedId = (data['invoiceDocId'] ?? '').toString().trim();
    return {
      'invoiceDocId': storedId.isEmpty ? sourceDocId : storedId,
      'docType': data['docType'] ?? data['type'] ?? '',
      'documentNumber': data['invoiceNumber'] ?? data['documentNumber'] ?? '',
      'name': data['name'] ?? '',
      'date': data['date'] ?? '',
      'amount': data['amount'] ?? 0,
      if (data['createdAt'] != null) 'createdAt': data['createdAt'],
    };
  }

  Future<void> _openCreditNoteFromDocument(
    String sourceDocId,
    Map<String, dynamic> savedData,
    bool isRtl,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final invoiceNumber = (savedData['invoiceNumber'] ?? '').toString().trim();
    final invoiceDocId = (savedData['invoiceDocId'] ?? sourceDocId)
        .toString()
        .trim();
    if (invoiceNumber.isEmpty) return;

    try {
      final navigator = Navigator.of(context);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final detailRef = userRef.collection('invoices').doc(invoiceDocId);

      final detailSnap = await detailRef.get();

      final userData = await ProfileDocumentService.load(currentUser.uid);
      final detailData = detailSnap.data() ?? <String, dynamic>{};
      final originalDocType = (savedData['docType'] ?? '').toString();
      final sourceDate = (detailData['date'] ?? savedData['date'] ?? '')
          .toString();
      final clientName =
          (detailData['clientName'] ?? savedData['clientName'] ?? '')
              .toString();
      final clientPhone = (detailData['clientPhone'] ?? '').toString();
      final clientEmail = (detailData['clientEmail'] ?? '').toString();
      final clientAddress = (detailData['clientAddress'] ?? '').toString();
      final items = ((detailData['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from((e as Map)))
          .toList();
      final workerName =
          (userData['name'] ?? currentUser.displayName ?? 'Worker').toString();
      final workerPhone = (userData['phone'] ?? userData['phoneNumber'] ?? '')
          .toString();
      final workerEmail = (userData['email'] ?? currentUser.email ?? '')
          .toString();
      final label = _docTypeLabel(originalDocType, isRtl);
      final originalDateFormatted = _formatOriginalInvoiceDate(sourceDate);
      final autoReason = isRtl
          ? 'זיכוי עבור $label מספר $invoiceNumber'
          : 'Credit for $label #$invoiceNumber';
      final autoReceiptConfirmation = isRtl
          ? 'נוצר אוטומטית ממסמך שמור #$invoiceNumber. יש לעדכן אסמכתא למסירה בפועל לפני שימוש משפטי.'
          : 'Auto-created from saved document #$invoiceNumber. Update with the actual delivery proof before legal use.';

      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceBuilderPage(
            workerName: workerName,
            workerPhone: workerPhone.isEmpty ? null : workerPhone,
            workerEmail: workerEmail.isEmpty ? null : workerEmail,
            receiverName: clientName.isEmpty ? null : clientName,
            receiverPhone: clientPhone.isEmpty ? null : clientPhone,
            receiverEmail: clientEmail.isEmpty ? null : clientEmail,
            receiverAddress: clientAddress.isEmpty ? null : clientAddress,
            initialSavedClientId:
                (detailData['savedClientId'] ?? detailData['clientUid'] ?? '')
                    .toString(),
            initialClientTaxId: (detailData['clientTaxId'] ?? '').toString(),
            initialClientExternalNumber:
                (detailData['externalClientNumber'] ?? '').toString(),
            initialDocType: 'credit_note',
            sourceInvoiceNumber: invoiceNumber,
            sourceInvoiceDocId: invoiceDocId,
            initialItems: items,
            initialNotes: (detailData['notes'] ?? '').toString(),
            initialPaymentMethod: (detailData['paymentMethod'] ?? '')
                .toString(),
            initialCheckNumber: (detailData['checkNumber'] ?? '').toString(),
            initialTransferDetails: (detailData['transferDetails'] ?? '')
                .toString(),
            initialCreditOriginalInvoiceNumber: invoiceNumber,
            initialCreditOriginalInvoiceDate: originalDateFormatted,
            initialCreditReason: autoReason,
            initialCreditDeliveryMethod: 'email_confirmation',
            initialCreditReceiptConfirmation: autoReceiptConfirmation,
            initialLinkedDocuments: [
              _linkedDocumentSeed(invoiceDocId, detailData),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא הצלחנו לפתוח הודעת זיכוי אוטומטית למסמך הזה.'
                : 'Could not open an automatic credit note for this document.',
          ),
        ),
      );
    }
  }

  Future<void> _openReceiptFromInvoice(
    String invoiceDocId,
    Map<String, dynamic> savedData,
    bool isRtl,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final invoiceNumber = (savedData['invoiceNumber'] ?? '').toString().trim();
    final resolvedInvoiceDocId = (savedData['invoiceDocId'] ?? invoiceDocId)
        .toString()
        .trim();
    if (invoiceNumber.isEmpty) return;

    final invoiceAmount = ((savedData['amount'] as num?)?.toDouble() ?? 0.0)
        .abs();
    final paidAmount = (savedData['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final creditedAmount =
        ((savedData['cancelledAmount'] as num?)?.toDouble() ?? 0.0).abs().clamp(
          0.0,
          invoiceAmount,
        );
    final remainingAmount = (invoiceAmount - paidAmount - creditedAmount).clamp(
      0.0,
      invoiceAmount,
    );
    if (remainingAmount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא נותרה יתרה לתשלום בחשבונית הזו.'
                : 'This invoice has no remaining balance to pay.',
          ),
        ),
      );
      return;
    }

    final paymentDraft = await _showReceiptPaymentDialog(
      isRtl: isRtl,
      remainingAmount: remainingAmount,
    );
    if (paymentDraft == null || !mounted) return;

    try {
      final navigator = Navigator.of(context);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final detailRef = userRef
          .collection('invoices')
          .doc(resolvedInvoiceDocId);
      final detailSnap = await detailRef.get();

      final userData = await ProfileDocumentService.load(currentUser.uid);
      final detailData = detailSnap.data() ?? <String, dynamic>{};
      final clientName =
          (detailData['clientName'] ?? savedData['clientName'] ?? '')
              .toString();
      final clientPhone = (detailData['clientPhone'] ?? '').toString();
      final clientEmail = (detailData['clientEmail'] ?? '').toString();
      final clientAddress = (detailData['clientAddress'] ?? '').toString();
      final workerName =
          (userData['name'] ?? currentUser.displayName ?? 'Worker').toString();
      final workerPhone = (userData['phone'] ?? userData['phoneNumber'] ?? '')
          .toString();
      final workerEmail = (userData['email'] ?? currentUser.email ?? '')
          .toString();
      final itemDescription = isRtl
          ? 'תשלום עבור חשבונית מספר $invoiceNumber'
          : 'Payment for Invoice #$invoiceNumber';
      final paymentNote = isRtl
          ? 'קבלה שנוצרה מחשבונית שמורה #$invoiceNumber'
          : 'Receipt created from saved invoice #$invoiceNumber';

      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceBuilderPage(
            workerName: workerName,
            workerPhone: workerPhone.isEmpty ? null : workerPhone,
            workerEmail: workerEmail.isEmpty ? null : workerEmail,
            receiverName: clientName.isEmpty ? null : clientName,
            receiverPhone: clientPhone.isEmpty ? null : clientPhone,
            receiverEmail: clientEmail.isEmpty ? null : clientEmail,
            receiverAddress: clientAddress.isEmpty ? null : clientAddress,
            initialSavedClientId:
                (detailData['savedClientId'] ?? detailData['clientUid'] ?? '')
                    .toString(),
            initialClientTaxId: (detailData['clientTaxId'] ?? '').toString(),
            initialClientExternalNumber:
                (detailData['externalClientNumber'] ?? '').toString(),
            initialDocType: 'receipt',
            initialItems: [
              {
                'description': itemDescription,
                'quantity': 1,
                'price': paymentDraft.amount,
                'priceTaxMode': 'after_tax',
              },
            ],
            initialNotes: paymentNote,
            initialPaymentAmount: paymentDraft.amount,
            sourceInvoiceNumber: invoiceNumber,
            sourceInvoiceDocId: resolvedInvoiceDocId,
            sourceInvoiceTotalAmount: invoiceAmount,
            initialLinkedDocuments: [
              _linkedDocumentSeed(resolvedInvoiceDocId, detailData),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא הצלחנו לפתוח קבלה אוטומטית עבור החשבונית.'
                : 'Could not open an automatic receipt for this invoice.',
          ),
        ),
      );
    }
  }

  Future<void> _openNegativeReceiptFromReceipt(
    String sourceDocId,
    Map<String, dynamic> savedData,
    bool isRtl,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final navigator = Navigator.of(context);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final resolvedSourceDocId = (savedData['invoiceDocId'] ?? sourceDocId)
          .toString()
          .trim();
      final detailRef = userRef.collection('invoices').doc(resolvedSourceDocId);
      final detailSnap = await detailRef.get();
      final userData = await ProfileDocumentService.load(currentUser.uid);
      final detailData = detailSnap.data() ?? savedData;
      final amount = ((detailData['amount'] as num?)?.toDouble() ?? 0).abs();
      if (amount <= 0) {
        throw StateError('The receipt amount is missing.');
      }

      final invoiceNumber = (detailData['invoiceNumber'] ?? '')
          .toString()
          .trim();
      final paymentMethods = detailData['paymentMethods'];
      final firstPayment = paymentMethods is List && paymentMethods.isNotEmpty
          ? Map<String, dynamic>.from(paymentMethods.first as Map)
          : const <String, dynamic>{};
      final paymentMethod =
          (firstPayment['method'] ?? detailData['paymentMethod'] ?? 'cash')
              .toString();
      final clientName = (detailData['clientName'] ?? '').toString();
      final clientPhone = (detailData['clientPhone'] ?? '').toString();
      final clientEmail = (detailData['clientEmail'] ?? '').toString();
      final clientAddress = (detailData['clientAddress'] ?? '').toString();
      final workerName =
          (userData['name'] ?? currentUser.displayName ?? 'Worker').toString();
      final workerPhone = (userData['phone'] ?? userData['phoneNumber'] ?? '')
          .toString();
      final workerEmail = (userData['email'] ?? currentUser.email ?? '')
          .toString();
      final cancellationNote = isRtl
          ? 'קבלה מבטלת עבור קבלה מספר $invoiceNumber'
          : 'Cancellation receipt for Receipt #$invoiceNumber';

      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceBuilderPage(
            workerName: workerName,
            workerPhone: workerPhone.isEmpty ? null : workerPhone,
            workerEmail: workerEmail.isEmpty ? null : workerEmail,
            receiverName: clientName.isEmpty ? null : clientName,
            receiverPhone: clientPhone.isEmpty ? null : clientPhone,
            receiverEmail: clientEmail.isEmpty ? null : clientEmail,
            receiverAddress: clientAddress.isEmpty ? null : clientAddress,
            initialSavedClientId:
                (detailData['savedClientId'] ?? detailData['clientUid'] ?? '')
                    .toString(),
            initialClientTaxId: (detailData['clientTaxId'] ?? '').toString(),
            initialClientExternalNumber:
                (detailData['externalClientNumber'] ?? '').toString(),
            initialDocType: 'receipt',
            initialNotes: cancellationNote,
            initialPaymentMethod: paymentMethod,
            initialPaymentAmount: amount,
            initialIsNegativeReceipt: true,
            cancellationSourceDocumentId: resolvedSourceDocId,
            cancellationSourceDocumentNumber: invoiceNumber,
            initialLinkedDocuments: [
              _linkedDocumentSeed(resolvedSourceDocId, detailData),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא הצלחנו לפתוח קבלה מבטלת עבור המסמך הזה.'
                : 'Could not open a cancellation receipt for this document.',
          ),
        ),
      );
    }
  }

  Future<void> _openDocumentFromSavedDocument({
    required String sourceDocId,
    required Map<String, dynamic> savedData,
    required String docType,
    required bool isRtl,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final navigator = Navigator.of(context);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final detailRef = userRef.collection('invoices').doc(sourceDocId);
      final detailSnap = await detailRef.get();
      final userData = await ProfileDocumentService.load(currentUser.uid);
      final detailData = detailSnap.data() ?? savedData;
      final items = ((detailData['items'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final amount = (detailData['amount'] as num?)?.toDouble() ?? 0.0;

      _ReceiptPaymentDraft? paymentDraft;
      if (docType == 'invoice_receipt') {
        paymentDraft = await _showReceiptPaymentDialog(
          isRtl: isRtl,
          remainingAmount: amount.abs(),
        );
        if (paymentDraft == null || !mounted) return;
      }

      final workerName =
          (userData['name'] ?? currentUser.displayName ?? 'Worker').toString();
      final workerPhone = (userData['phone'] ?? userData['phoneNumber'] ?? '')
          .toString();
      final workerEmail = (userData['email'] ?? currentUser.email ?? '')
          .toString();
      final clientName = (detailData['clientName'] ?? '').toString();
      final clientPhone = (detailData['clientPhone'] ?? '').toString();
      final clientEmail = (detailData['clientEmail'] ?? '').toString();
      final clientAddress = (detailData['clientAddress'] ?? '').toString();
      final resolvedSourceDocId = (detailData['invoiceDocId'] ?? sourceDocId)
          .toString()
          .trim();

      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => InvoiceBuilderPage(
            workerName: workerName,
            workerPhone: workerPhone.isEmpty ? null : workerPhone,
            workerEmail: workerEmail.isEmpty ? null : workerEmail,
            receiverName: clientName.isEmpty ? null : clientName,
            receiverPhone: clientPhone.isEmpty ? null : clientPhone,
            receiverEmail: clientEmail.isEmpty ? null : clientEmail,
            receiverAddress: clientAddress.isEmpty ? null : clientAddress,
            initialSavedClientId:
                (detailData['savedClientId'] ?? detailData['clientUid'] ?? '')
                    .toString(),
            initialClientTaxId: (detailData['clientTaxId'] ?? '').toString(),
            initialClientExternalNumber:
                (detailData['externalClientNumber'] ?? '').toString(),
            initialDocType: docType,
            initialItems: items,
            initialNotes: (detailData['notes'] ?? '').toString(),
            initialPaymentAmount: paymentDraft?.amount,
            initialLinkedDocuments: [
              _linkedDocumentSeed(resolvedSourceDocId, detailData),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRtl
                ? 'לא הצלחנו ליצור מסמך מס מתוך חשבון העסקה.'
                : 'Could not create a document from this saved document.',
          ),
        ),
      );
    }
  }

  Future<_ReceiptPaymentDraft?> _showReceiptPaymentDialog({
    required bool isRtl,
    required double remainingAmount,
  }) async {
    final amountController = TextEditingController(
      text: remainingAmount.toStringAsFixed(2),
    );
    String? validationMessage;

    try {
      return await showDialog<_ReceiptPaymentDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: IconButton(
                          tooltip: isRtl ? 'סגירה' : 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            foregroundColor: const Color(0xFF64748B),
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: Color(0xFF1976D2),
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isRtl ? 'יצירת קבלה' : 'Create Receipt',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRtl
                            ? 'הזינו את הסכום שהתקבל מהלקוח.'
                            : 'Enter the amount received from the client.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Color(0xFF1976D2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isRtl ? 'יתרה לתשלום' : 'Remaining due',
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${remainingAmount.toStringAsFixed(2)} ₪',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: amountController,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) {
                          if (validationMessage == null) return;
                          setDialogState(() => validationMessage = null);
                        },
                        onSubmitted: (_) => _submitReceiptAmount(
                          dialogContext: dialogContext,
                          amountController: amountController,
                          remainingAmount: remainingAmount,
                          isRtl: isRtl,
                          setValidationMessage: (message) =>
                              setDialogState(() => validationMessage = message),
                        ),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          labelText: isRtl ? 'סכום הקבלה' : 'Receipt amount',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          suffixText: '₪',
                          filled: true,
                          fillColor: const Color(0xFFFAFCFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF1976D2),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 19,
                                color: Color(0xFFB91C1C),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  validationMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        isRtl
                            ? 'את אמצעי התשלום ניתן לבחור במסך הבא.'
                            : 'You can choose the payment method on the next screen.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _submitReceiptAmount(
                          dialogContext: dialogContext,
                          amountController: amountController,
                          remainingAmount: remainingAmount,
                          isRtl: isRtl,
                          setValidationMessage: (message) =>
                              setDialogState(() => validationMessage = message),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          isRtl ? 'המשך לקבלה' : 'Continue to Receipt',
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
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(isRtl ? 'ביטול' : 'Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      amountController.dispose();
    }
  }

  void _submitReceiptAmount({
    required BuildContext dialogContext,
    required TextEditingController amountController,
    required double remainingAmount,
    required bool isRtl,
    required ValueChanged<String> setValidationMessage,
  }) {
    final parsedAmount = double.tryParse(
      amountController.text.trim().replaceAll(',', '.'),
    );
    if (parsedAmount == null ||
        parsedAmount <= 0 ||
        parsedAmount > remainingAmount + 0.01) {
      setValidationMessage(
        isRtl
            ? 'יש להזין סכום תקין שאינו גדול מהיתרה לתשלום.'
            : 'Enter a valid amount that does not exceed the remaining due.',
      );
      return;
    }
    Navigator.pop(dialogContext, _ReceiptPaymentDraft(amount: parsedAmount));
  }

  void _clearDateRange() {
    setState(() {
      _selectedDateRange = null;
    });
  }

  String _dateRangeLabel(bool isRtl) {
    if (_selectedDateRange == null) {
      return isRtl ? 'סנן לפי תאריך' : 'Filter by date';
    }

    final format = intl.DateFormat('dd/MM/yyyy');
    return '${format.format(_selectedDateRange!.start)} - ${format.format(_selectedDateRange!.end)}';
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s\u0590-\u05FF/]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _searchTerms(String query) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return const [];
    return normalized.split(' ').where((term) => term.isNotEmpty).toList();
  }

  List<String> _phoneCandidates(String input) {
    final normalized = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final digits = normalized.replaceAll(RegExp(r'\D'), '');
    final candidates = <String>{};

    if (normalized.isNotEmpty) candidates.add(normalized);
    if (digits.isNotEmpty) candidates.add(digits);

    if (digits.startsWith('0') && digits.length == 10) {
      candidates.add('+972${digits.substring(1)}');
    }
    if (digits.length == 9) {
      candidates
        ..add('0$digits')
        ..add('+972$digits');
    }
    if (digits.startsWith('972')) {
      candidates.add('+$digits');
      if (digits.length == 12) {
        candidates.add('0${digits.substring(3)}');
      }
      if (digits.length > 4 && digits[3] == '0') {
        candidates.add('+972${digits.substring(4)}');
      }
    }
    if (normalized.startsWith('+9720') && normalized.length > 5) {
      candidates.add('+972${normalized.substring(5)}');
    }

    return candidates.toList();
  }

  bool _matchesSearch(
    Map<String, dynamic> data,
    List<String> terms,
    bool isRtl,
  ) {
    if (terms.isEmpty) return true;

    final createdAt = data['createdAt'] as Timestamp?;
    final createdDate = createdAt?.toDate();
    final searchableFields = [
      data['name'],
      data['fileName'],
      data['clientName'],
      data['clientPhone'],
      data['externalClientNumber'],
      data['invoiceNumber'],
      data['docType'],
      data['amount'],
      _docTypeLabel((data['docType'] ?? '').toString(), isRtl),
      if (createdDate != null)
        intl.DateFormat('dd/MM/yyyy').format(createdDate),
      if (createdDate != null)
        intl.DateFormat('dd/MM/yyyy HH:mm').format(createdDate),
    ];

    final haystack = _normalizeSearchText(
      searchableFields.map((e) => (e ?? '').toString()).join(' '),
    );

    return terms.every(haystack.contains);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isRtl ? 'חשבוניות שמורות' : 'Saved Invoices'),
        ),
        body: Center(
          child: Text(
            isRtl
                ? 'יש להתחבר כדי לצפות בחשבוניות.'
                : 'Please sign in to view invoices.',
          ),
        ),
      );
    }

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(isRtl ? 'מסמכים' : 'Documents'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _selectedScope == _InvoiceScope.createdByMe
              ? _invoicesStream
              : _receivedInvoicesStream,
          builder: (context, snapshot) {
            final isReceivedScope = _selectedScope == _InvoiceScope.sentToMe;
            if (isReceivedScope &&
                _isLoadingReceivedInvoices &&
                _receivedInvoicesStream == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (isReceivedScope && !_hasReceivedInvoicePhone) {
              return Column(
                children: [
                  _buildScopeSwitcher(isRtl),
                  Expanded(child: _buildNoPhoneState(isRtl)),
                ],
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                children: [
                  _buildScopeSwitcher(isRtl),
                  Expanded(child: _buildLoadErrorState(isRtl)),
                ],
              );
            }

            final docs = [...(snapshot.data?.docs ?? const [])];
            if (isReceivedScope) {
              docs.sort((a, b) {
                final aDate = a.data()['createdAt'] as Timestamp?;
                final bDate = b.data()['createdAt'] as Timestamp?;
                return (bDate?.toDate() ?? DateTime(0)).compareTo(
                  aDate?.toDate() ?? DateTime(0),
                );
              });
            }
            if (docs.isEmpty) {
              return Column(
                children: [
                  _buildScopeSwitcher(isRtl),
                  Expanded(child: _buildEmptyState(isRtl, isReceivedScope)),
                ],
              );
            }

            final query = _searchQuery.trim();
            final searchTerms = _searchTerms(query);
            final filteredDocs = docs.where((doc) {
              final data = doc.data();
              final docType = (data['docType'] ?? '').toString();
              if (_selectedDocType != 'all' && docType != _selectedDocType) {
                return false;
              }

              final createdAt = data['createdAt'] as Timestamp?;
              if (_selectedDateRange != null) {
                final createdDate = createdAt?.toDate();
                if (createdDate == null ||
                    createdDate.isBefore(_selectedDateRange!.start) ||
                    createdDate.isAfter(_selectedDateRange!.end)) {
                  return false;
                }
              }

              return _matchesSearch(data, searchTerms, isRtl);
            }).toList();

            final totalAmount = docs.fold<double>(0, (runningTotal, doc) {
              final data = doc.data();
              if (data['taxAuthorityAllocationRequest'] is Map &&
                  data['documentStatus'] != 'finalized') {
                return runningTotal;
              }
              final amount = (data['amount'] as num?)?.toDouble() ?? 0;
              return runningTotal + amount;
            });

            return Column(
              children: [
                _buildScopeSwitcher(isRtl),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              focusNode: _searchFocusNode,
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: isRtl
                                    ? 'חפש לקוח, מספר לקוח, מספר מסמך או מסמך'
                                    : 'Search client, client number, document number, or document',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searchController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _buildSummaryBadge(
                            isRtl: isRtl,
                            count: docs.length,
                            totalAmount: totalAmount,
                            isReceivedScope: isReceivedScope,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickDateRange(isRtl),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1976D2),
                                side: const BorderSide(
                                  color: Color(0xFFD6E4F5),
                                ),
                                backgroundColor: const Color(0xFFF8FAFC),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.date_range_rounded,
                                size: 18,
                              ),
                              label: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  _dateRangeLabel(isRtl),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          if (_selectedDateRange != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: isRtl
                                  ? 'נקה תאריך'
                                  : 'Clear date filter',
                              onPressed: _clearDateRange,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFF1F5F9),
                                foregroundColor: const Color(0xFF64748B),
                              ),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildFilterChip('all', isRtl ? 'הכל' : 'All'),
                            _buildFilterChip(
                              'quote',
                              _docTypeLabel('quote', isRtl),
                            ),
                            _buildFilterChip(
                              'work_order',
                              _docTypeLabel('work_order', isRtl),
                            ),
                            _buildFilterChip(
                              'transaction_account',
                              _docTypeLabel('transaction_account', isRtl),
                            ),
                            _buildFilterChip(
                              'invoice',
                              _docTypeLabel('invoice', isRtl),
                            ),
                            _buildFilterChip(
                              'receipt',
                              _docTypeLabel('receipt', isRtl),
                            ),
                            _buildFilterChip(
                              'invoice_receipt',
                              _docTypeLabel('invoice_receipt', isRtl),
                            ),
                            _buildFilterChip(
                              'credit_note',
                              _docTypeLabel('credit_note', isRtl),
                            ),
                          ],
                        ),
                      ),
                      if (query.isNotEmpty || _selectedDateRange != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            isRtl
                                ? 'נמצאו ${filteredDocs.length} מתוך ${docs.length} מסמכים'
                                : '${filteredDocs.length} of ${docs.length} documents found',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: filteredDocs.isEmpty
                      ? _buildSearchEmptyState(isRtl, query.isNotEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, separatorIndex) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final invoiceDoc = filteredDocs[index];
                            final data = invoiceDoc.data();
                            final invoiceNumber = (data['invoiceNumber'] ?? '')
                                .toString();
                            final docType = (data['docType'] ?? '').toString();
                            final clientName = (data['clientName'] ?? '')
                                .toString()
                                .trim();
                            final fallbackName = clientName.isNotEmpty
                                ? '${_docTypeLabel(docType, isRtl)}${invoiceNumber.isNotEmpty ? ' #$invoiceNumber' : ''} - $clientName'
                                : '${_docTypeLabel(docType, isRtl)}${invoiceNumber.isNotEmpty ? ' #$invoiceNumber' : ''}';
                            final name = (data['name'] ?? fallbackName)
                                .toString();
                            final fileName = (data['fileName'] ?? '$name.pdf')
                                .toString();
                            final url = (data['url'] ?? '').toString();
                            final storagePath = (data['storagePath'] ?? '')
                                .toString();
                            final hasTaxWorkflow =
                                data['taxAuthorityAllocationRequest'] is Map;
                            final hasServerWorkflow =
                                data['serverDocument'] is Map;
                            final documentRecovery = data['documentRecovery'];
                            final hasMissingFinalPdf =
                                documentRecovery is Map &&
                                documentRecovery['status'] ==
                                    'needs_reconciliation' &&
                                documentRecovery['reason'] ==
                                    'missing_final_pdf';
                            final documentStatus =
                                (data['documentStatus'] ?? '')
                                    .toString()
                                    .trim();
                            final fallbackPreview = data['fallbackPreview'];
                            final fallbackPreviewUrl = fallbackPreview is Map
                                ? (fallbackPreview['url'] ?? '').toString()
                                : '';
                            final fallbackPreviewStoragePath =
                                fallbackPreview is Map
                                ? (fallbackPreview['storagePath'] ?? '')
                                      .toString()
                                : '';
                            final fallbackPreviewFileName =
                                fallbackPreview is Map
                                ? (fallbackPreview['fileName'] ?? fileName)
                                      .toString()
                                : fileName;
                            final hasFallbackPreview =
                                fallbackPreview is Map &&
                                fallbackPreview['status'] == 'available' &&
                                fallbackPreview['previewOnly'] == true &&
                                fallbackPreviewUrl.isNotEmpty &&
                                fallbackPreviewStoragePath.isNotEmpty;
                            final isFinalizedTaxDocument =
                                ((!hasTaxWorkflow && !hasServerWorkflow) ||
                                    documentStatus == 'finalized') &&
                                !hasMissingFinalPdf;
                            final opensFallbackPreview =
                                hasFallbackPreview && !isFinalizedTaxDocument;
                            final openingUrl = opensFallbackPreview
                                ? fallbackPreviewUrl
                                : url;
                            final openingStoragePath = opensFallbackPreview
                                ? fallbackPreviewStoragePath
                                : storagePath;
                            final openingFileName = opensFallbackPreview
                                ? fallbackPreviewFileName
                                : fileName;
                            final displayedDocumentStatus = hasMissingFinalPdf
                                ? 'needs_reconciliation'
                                : documentStatus;
                            final canRetryGeneration =
                                !isReceivedScope &&
                                _canRetryDocumentGeneration(data);
                            final canRetryTaxAuthorityAllocation =
                                !isReceivedScope &&
                                documentStatus == 'hearing_requested';
                            final canChooseTaxAuthorityDecision =
                                !isReceivedScope &&
                                documentStatus == 'decision_required';
                            final requiresGenerationReview =
                                !isReceivedScope &&
                                hasServerWorkflow &&
                                documentStatus == 'needs_reconciliation';
                            final isRetryingGeneration = _retryingDocuments
                                .contains(invoiceDoc.id);
                            final createdAt = data['createdAt'] as Timestamp?;
                            final amount = (data['amount'] as num?)?.toDouble();
                            final cancellationStatus =
                                (data['cancellationStatus'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final isCancelled =
                                cancellationStatus == 'cancelled';
                            final isPartiallyCancelled =
                                cancellationStatus == 'partially_cancelled';
                            final canCreateCreditNote =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                !isCancelled &&
                                (docType == 'invoice' ||
                                    docType == 'invoice_receipt');
                            final canCreateReceipt =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                !isCancelled &&
                                docType == 'invoice';
                            final canCancelReceipt =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                docType == 'receipt' &&
                                data['isCancellationDocument'] != true &&
                                !isCancelled;
                            final isProformaInvoice =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                docType == 'transaction_account';
                            final canCreateTaxDocuments =
                                isProformaInvoice && _canCreateTaxDocuments;
                            final isWorkOrder =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                docType == 'work_order';
                            final canCreateTaxDocumentsFromWorkOrder =
                                isWorkOrder && _canCreateTaxDocuments;
                            final isQuote =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                docType == 'quote';
                            final canCreateTaxDocumentsFromQuote =
                                isQuote && _canCreateTaxDocuments;
                            final canBeSigned =
                                !isReceivedScope &&
                                isFinalizedTaxDocument &&
                                (docType == 'quote' || docType == 'work_order');
                            final isLinkingLocked =
                                isCancelled || data['isLinkingLocked'] == true;
                            final isUpdatingDocumentLock =
                                _updatingDocumentLocks.contains(invoiceDoc.id);
                            final hasCreateDocumentActions =
                                !isLinkingLocked &&
                                (canCreateCreditNote ||
                                    canCancelReceipt ||
                                    isProformaInvoice ||
                                    isWorkOrder ||
                                    isQuote);
                            final createActionsExpanded =
                                !isLinkingLocked &&
                                _expandedCreateActions.contains(invoiceDoc.id);
                            final signatureStatus =
                                (data['signatureStatus'] ?? '')
                                    .toString()
                                    .trim()
                                    .toLowerCase();
                            final isSigned = signatureStatus == 'signed';
                            final isGeneratingSigningLink =
                                _generatingSigningLinks.contains(invoiceDoc.id);
                            final paidAmount =
                                (data['paidAmount'] as num?)?.toDouble() ??
                                (docType == 'invoice_receipt'
                                    ? ((amount ?? 0).abs())
                                    : 0.0);
                            final invoiceAmount = (amount ?? 0).abs();
                            final creditedAmount =
                                ((data['cancelledAmount'] as num?)
                                            ?.toDouble() ??
                                        0.0)
                                    .abs()
                                    .clamp(0.0, invoiceAmount);
                            final remainingAmount =
                                (invoiceAmount - paidAmount - creditedAmount)
                                    .clamp(0.0, invoiceAmount);
                            final canCreateReceiptWithBalance =
                                canCreateReceipt && remainingAmount > 0.01;
                            final paymentStatus =
                                (data['paymentStatus'] ?? '')
                                    .toString()
                                    .trim()
                                    .isNotEmpty
                                ? (data['paymentStatus'] ?? '')
                                      .toString()
                                      .trim()
                                : (docType == 'invoice_receipt'
                                      ? 'paid'
                                      : (paidAmount <= 0
                                            ? 'unpaid'
                                            : (remainingAmount <= 0.01
                                                  ? 'paid'
                                                  : 'partial')));
                            final createdText = createdAt == null
                                ? ''
                                : intl.DateFormat(
                                    'dd/MM/yyyy HH:mm',
                                  ).format(createdAt.toDate());
                            final accent = _docTypeColor(docType);

                            return InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                if ((!isFinalizedTaxDocument &&
                                        !hasFallbackPreview) ||
                                    (isFinalizedTaxDocument &&
                                        hasMissingFinalPdf) ||
                                    openingUrl.isEmpty) {
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SavedInvoicePreviewPage(
                                      name: openingFileName,
                                      url: openingUrl,
                                      invoiceDocId: invoiceDoc.id,
                                      canReportMissing:
                                          !isReceivedScope &&
                                          isFinalizedTaxDocument,
                                      storagePath: openingStoragePath,
                                      previewOnly: opensFallbackPreview,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x080F172A),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.picture_as_pdf_rounded,
                                            color: accent,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: accent.withValues(
                                                        alpha: 0.12,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      _docTypeLabel(
                                                        docType,
                                                        isRtl,
                                                      ),
                                                      style: TextStyle(
                                                        color: accent,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  if (invoiceNumber.isNotEmpty)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFF8FAFC,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '#$invoiceNumber',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                            0xFF475569,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  if ((hasTaxWorkflow ||
                                                          hasServerWorkflow) &&
                                                      displayedDocumentStatus !=
                                                          'finalized' &&
                                                      displayedDocumentStatus !=
                                                          'reserved')
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _documentWorkflowColor(
                                                              displayedDocumentStatus,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _documentWorkflowLabel(
                                                          displayedDocumentStatus,
                                                          isRtl,
                                                        ),
                                                        style: TextStyle(
                                                          color: _documentWorkflowColor(
                                                            displayedDocumentStatus,
                                                          ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  if (isCancelled)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            const Color(
                                                              0xFFDC2626,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        isRtl
                                                            ? 'המסמך בוטל'
                                                            : 'Document cancelled',
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFB91C1C,
                                                          ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  if (!isCancelled &&
                                                      isPartiallyCancelled)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            const Color(
                                                              0xFFD97706,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        isRtl
                                                            ? 'בוטל חלקית'
                                                            : 'Partially cancelled',
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFB45309,
                                                          ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  if (!isCancelled &&
                                                      docType == 'invoice')
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _paymentStatusColor(
                                                              paymentStatus,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _paymentStatusLabel(
                                                          paymentStatus,
                                                          isRtl,
                                                        ),
                                                        style: TextStyle(
                                                          color:
                                                              _paymentStatusColor(
                                                                paymentStatus,
                                                              ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  if (canBeSigned)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _signatureStatusColor(
                                                              signatureStatus,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _signatureStatusLabel(
                                                          signatureStatus,
                                                          isRtl,
                                                        ),
                                                        style: TextStyle(
                                                          color:
                                                              _signatureStatusColor(
                                                                signatureStatus,
                                                              ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              if (clientName.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  clientName,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (!isReceivedScope)
                                          IconButton(
                                            tooltip: isLinkingLocked
                                                ? (isCancelled
                                                      ? (isRtl
                                                            ? 'מסמך שבוטל נעול לצמיתות'
                                                            : 'Cancelled documents are permanently locked')
                                                      : (isRtl
                                                            ? 'פתח נעילה כדי לקשר או ליצור מסמך נוסף'
                                                            : 'Unlock to link or create another document'))
                                                : (isRtl
                                                      ? 'נעל קישור ויצירת מסמכים נוספים'
                                                      : 'Lock linking and document creation'),
                                            onPressed:
                                                isUpdatingDocumentLock ||
                                                    isCancelled
                                                ? null
                                                : () => _toggleDocumentLinkLock(
                                                    invoiceDocId: invoiceDoc.id,
                                                    documentName: name,
                                                    isCurrentlyLocked:
                                                        isLinkingLocked,
                                                    isRtl: isRtl,
                                                  ),
                                            icon: isUpdatingDocumentLock
                                                ? const SizedBox.square(
                                                    dimension: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Icon(
                                                    isLinkingLocked
                                                        ? Icons.lock
                                                        : Icons
                                                              .lock_open_rounded,
                                                    color: isLinkingLocked
                                                        ? const Color(
                                                            0xFF475569,
                                                          )
                                                        : const Color(
                                                            0xFF1976D2,
                                                          ),
                                                  ),
                                          ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildMetaRow(
                                            icon: Icons.calendar_today_outlined,
                                            text: createdText.isEmpty
                                                ? (isRtl
                                                      ? 'ללא תאריך'
                                                      : 'No date')
                                                : createdText,
                                          ),
                                        ),
                                        if (amount != null) ...[
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEFF6FF),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${amount.toStringAsFixed(2)} ₪',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1976D2),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (requiresGenerationReview) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF7ED),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFED7AA),
                                          ),
                                        ),
                                        child: Text(
                                          isRtl
                                              ? 'הפקת המסמך נכשלה מספר פעמים. המספר נשמר והמסמך הועבר לבדיקה. אין ליצור מסמך חדש במקומו.'
                                              : 'Generation failed repeatedly. The number is reserved and the document was sent for review. Do not create a replacement document.',
                                          style: const TextStyle(
                                            color: Color(0xFF9A3412),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (hasFallbackPreview &&
                                        !isFinalizedTaxDocument) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFBFDBFE),
                                          ),
                                        ),
                                        child: Text(
                                          isRtl
                                              ? 'נשמרה גרסת תצוגה מקדימה. אפשר לפתוח אותה כעת; הפקה מוצלחת תחליף אותה במסמך הסופי.'
                                              : 'A preview version was saved. You can open it now; successful generation will replace it with the final document.',
                                          style: const TextStyle(
                                            color: Color(0xFF1D4ED8),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (hasMissingFinalPdf) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFECACA),
                                          ),
                                        ),
                                        child: Text(
                                          isRtl
                                              ? 'המסמך הושלם, אך קובץ ה-PDF חסר. המספר נשמר והמסמך הועבר לבדיקה.'
                                              : 'The document was finalized, but its PDF is missing. Its number remains reserved and it was sent for review.',
                                          style: const TextStyle(
                                            color: Color(0xFF991B1B),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (canRetryGeneration) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: isRetryingGeneration
                                              ? null
                                              : () => _retryDocumentGeneration(
                                                  invoiceDoc.id,
                                                  isRtl,
                                                ),
                                          icon: isRetryingGeneration
                                              ? const SizedBox.square(
                                                  dimension: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                          label: Text(
                                            isRetryingGeneration
                                                ? (isRtl
                                                      ? 'מנסה שוב...'
                                                      : 'Retrying...')
                                                : (isRtl
                                                      ? 'נסה שוב להפיק את המסמך'
                                                      : 'Retry document generation'),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFB91C1C,
                                            ),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (canRetryTaxAuthorityAllocation) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: isRetryingGeneration
                                              ? null
                                              : () =>
                                                    _retryTaxAuthorityAllocation(
                                                      invoiceDoc.id,
                                                      isRtl,
                                                    ),
                                          icon: isRetryingGeneration
                                              ? const SizedBox.square(
                                                  dimension: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                          label: Text(
                                            isRetryingGeneration
                                                ? (isRtl
                                                      ? 'מבקש מספר הקצאה...'
                                                      : 'Requesting allocation...')
                                                : (isRtl
                                                      ? 'בקש מספר הקצאה שוב'
                                                      : 'Request allocation number again'),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF1976D2,
                                            ),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (canChooseTaxAuthorityDecision) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _showTaxAuthorityDecision(
                                            invoiceDocId: invoiceDoc.id,
                                            isRtl: isRtl,
                                            errors:
                                                data['taxAuthorityAllocationRequest']
                                                    is Map
                                                ? (data['taxAuthorityAllocationRequest']
                                                      as Map)['authorityErrors']
                                                : null,
                                          ),
                                          icon: const Icon(
                                            Icons.pending_actions_rounded,
                                          ),
                                          label: Text(
                                            isRtl
                                                ? 'בחרו תגובה לרשות המסים'
                                                : 'Choose Tax Authority response',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFD97706,
                                            ),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (hasCreateDocumentActions) ...[
                                      const SizedBox(height: 6),
                                      Center(
                                        child: IconButton(
                                          tooltip: createActionsExpanded
                                              ? (isRtl
                                                    ? 'הסתר פעולות יצירה'
                                                    : 'Hide document actions')
                                              : (isRtl
                                                    ? 'הצג פעולות יצירה'
                                                    : 'Show document actions'),
                                          onPressed: () {
                                            setState(() {
                                              if (createActionsExpanded) {
                                                _expandedCreateActions.remove(
                                                  invoiceDoc.id,
                                                );
                                              } else {
                                                _expandedCreateActions.add(
                                                  invoiceDoc.id,
                                                );
                                              }
                                            });
                                          },
                                          icon: AnimatedRotation(
                                            turns: createActionsExpanded
                                                ? 0.5
                                                : 0,
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            child: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: accent,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (createActionsExpanded &&
                                        canCreateCreditNote) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          if (canCreateReceiptWithBalance)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openReceiptFromInvoice(
                                                    invoiceDoc.id,
                                                    data,
                                                    isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.receipt_long_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור קבלה'
                                                    : 'Create Receipt',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openCreditNoteFromDocument(
                                                  invoiceDoc.id,
                                                  data,
                                                  isRtl,
                                                ),
                                            icon: const Icon(
                                              Icons.assignment_return_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              isRtl
                                                  ? 'בטל מסמך'
                                                  : 'Cancel Document',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFDC2626,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 0,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (createActionsExpanded &&
                                        canCancelReceipt) ...[
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: TextButton.icon(
                                          onPressed: () =>
                                              _openNegativeReceiptFromReceipt(
                                                invoiceDoc.id,
                                                data,
                                                isRtl,
                                              ),
                                          icon: const Icon(
                                            Icons.assignment_return_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            isRtl
                                                ? 'בטל מסמך'
                                                : 'Cancel Document',
                                          ),
                                          style: TextButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFFDC2626,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 0,
                                              vertical: 4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (createActionsExpanded &&
                                        isProformaInvoice) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openReceiptFromInvoice(
                                                  invoiceDoc.id,
                                                  data,
                                                  isRtl,
                                                ),
                                            icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              isRtl
                                                  ? 'צור קבלה'
                                                  : 'Create Receipt',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: accent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 0,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          if (canCreateTaxDocuments)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.request_quote_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס'
                                                    : 'Create Tax Invoice',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                          if (canCreateTaxDocuments)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice_receipt',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.receipt_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס / קבלה'
                                                    : 'Create Tax Invoice / Receipt',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (createActionsExpanded &&
                                        canBeSigned &&
                                        !isSigned) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: isGeneratingSigningLink
                                            ? null
                                            : () => _generateSigningLink(
                                                invoiceDoc.id,
                                                isRtl,
                                              ),
                                        icon: isGeneratingSigningLink
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.draw_outlined,
                                                size: 18,
                                              ),
                                        label: Text(
                                          isGeneratingSigningLink
                                              ? (isRtl
                                                    ? 'יוצר קישור...'
                                                    : 'Generating Link...')
                                              : (isRtl
                                                    ? 'צור קישור לחתימה'
                                                    : 'Generate Signing Link'),
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: accent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 0,
                                            vertical: 4,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (createActionsExpanded &&
                                        isWorkOrder) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openDocumentFromSavedDocument(
                                                  sourceDocId: invoiceDoc.id,
                                                  savedData: data,
                                                  docType:
                                                      'transaction_account',
                                                  isRtl: isRtl,
                                                ),
                                            icon: const Icon(
                                              Icons.description_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              isRtl
                                                  ? 'צור חשבון עסקה'
                                                  : 'Create Proforma Invoice',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: accent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 0,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          if (canCreateTaxDocumentsFromWorkOrder)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.request_quote_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס'
                                                    : 'Create Tax Invoice',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                          if (canCreateTaxDocumentsFromWorkOrder)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice_receipt',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.receipt_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס / קבלה'
                                                    : 'Create Tax Invoice / Receipt',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (createActionsExpanded && isQuote) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openDocumentFromSavedDocument(
                                                  sourceDocId: invoiceDoc.id,
                                                  savedData: data,
                                                  docType: 'work_order',
                                                  isRtl: isRtl,
                                                ),
                                            icon: const Icon(
                                              Icons.assignment_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              isRtl
                                                  ? 'צור הזמנת עבודה'
                                                  : 'Create Work Order',
                                            ),
                                            style: TextButton.styleFrom(
                                              foregroundColor: accent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 0,
                                                    vertical: 4,
                                                  ),
                                            ),
                                          ),
                                          if (canCreateTaxDocumentsFromQuote)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.request_quote_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס'
                                                    : 'Create Tax Invoice',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                          if (canCreateTaxDocumentsFromQuote)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _openDocumentFromSavedDocument(
                                                    sourceDocId: invoiceDoc.id,
                                                    savedData: data,
                                                    docType: 'invoice_receipt',
                                                    isRtl: isRtl,
                                                  ),
                                              icon: const Icon(
                                                Icons.receipt_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isRtl
                                                    ? 'צור חשבונית מס / קבלה'
                                                    : 'Create Tax Invoice / Receipt',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: accent,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 0,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                    if (docType == 'invoice' &&
                                        !isCancelled) ...[
                                      const SizedBox(height: 8),
                                      _buildMetaRow(
                                        icon: Icons.payments_outlined,
                                        text:
                                            '${isRtl ? 'שולם' : 'Paid'}: ${paidAmount.toStringAsFixed(2)} ₪'
                                            '${creditedAmount > 0.005 ? '  |  ${isRtl ? 'זוכה' : 'Credited'}: ${creditedAmount.toStringAsFixed(2)} ₪' : ''}'
                                            '  |  '
                                            '${isRtl ? 'נותר' : 'Remaining'}: ${remainingAmount.toStringAsFixed(2)} ₪',
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedDocType == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedDocType = value),
        selectedColor: const Color(0xFF1976D2),
        backgroundColor: const Color(0xFFF1F5F9),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
        labelStyle: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Widget _buildScopeSwitcher(bool isRtl) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SegmentedButton<_InvoiceScope>(
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFEFF6FF);
            }
            return const Color(0xFFF8FAFC);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1976D2);
            }
            return const Color(0xFF475569);
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: Color(0xFFD6E4F5)),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        segments: [
          ButtonSegment(
            value: _InvoiceScope.createdByMe,
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            label: Text(isRtl ? 'שיצרתי' : 'Created by me'),
          ),
          ButtonSegment(
            value: _InvoiceScope.sentToMe,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: Text(isRtl ? 'נשלחו אליי' : 'Sent to me'),
          ),
        ],
        selected: {_selectedScope},
        onSelectionChanged: (selection) {
          final nextScope = selection.first;
          if (nextScope == _selectedScope) return;
          setState(() {
            _selectedScope = nextScope;
          });
        },
      ),
    );
  }

  Widget _buildSummaryBadge({
    required bool isRtl,
    required int count,
    required double totalAmount,
    required bool isReceivedScope,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isReceivedScope
                ? (isRtl ? 'אליי' : 'To me')
                : (isRtl ? 'מסמכים' : 'Docs'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${totalAmount.toStringAsFixed(0)} ₪',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isRtl, bool isReceivedScope) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1FB),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.folder_copy_outlined,
                size: 42,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isReceivedScope
                  ? (isRtl
                        ? 'לא נמצאו מסמכים שנשלחו אליך'
                        : 'No documents sent to you yet')
                  : (isRtl
                        ? 'עדיין אין מסמכים שמורים'
                        : 'No saved documents yet'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isReceivedScope
                  ? (isRtl
                        ? 'כאן יופיעו חשבוניות ומסמכים שנוצרו למספר הטלפון שלך.'
                        : 'Invoices and documents created for your phone number will appear here.')
                  : (isRtl
                        ? 'כשתשמור חשבונית, קבלה או זיכוי, הם יופיעו כאן לצפייה מהירה.'
                        : 'When you save an invoice, receipt, or credit note, it will appear here for quick access.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(bool isRtl, bool hasQuery) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 34,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isRtl ? 'לא נמצאו מסמכים' : 'No documents found',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? (isRtl
                        ? 'נסו לחפש לפי שם לקוח, מספר מסמך, סוג מסמך או תאריך.'
                        : 'Try searching by client name, document number, type, or date.')
                  : (isRtl
                        ? 'שנו את טווח התאריכים או המסנן כדי לראות מסמכים נוספים.'
                        : 'Adjust the date range or filter to see more documents.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPhoneState(bool isRtl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1FB),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.phone_android_outlined,
                size: 42,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isRtl ? 'לא נמצא מספר טלפון' : 'No phone number found',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRtl
                  ? 'כדי להציג מסמכים שנוצרו עבורך, צריך מספר טלפון בפרופיל או בחשבון.'
                  : 'Add a phone number to your account or profile to see documents created for you.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(bool isRtl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 42,
                color: Color(0xFFE11D48),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isRtl ? 'לא הצלחנו לטעון מסמכים' : 'Could not load documents',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRtl
                  ? 'נסו שוב בעוד רגע. אם המסמך חדש, ייתכן שהוא עדיין מסתנכרן.'
                  : 'Try again in a moment. If the document is new, it may still be syncing.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

enum _InvoiceScope { createdByMe, sentToMe }

class _ReceiptPaymentDraft {
  final double amount;

  const _ReceiptPaymentDraft({required this.amount});
}

class SavedInvoicePreviewPage extends StatefulWidget {
  final String name;
  final String url;
  final String invoiceDocId;
  final bool canReportMissing;
  final String storagePath;
  final bool previewOnly;

  const SavedInvoicePreviewPage({
    super.key,
    required this.name,
    required this.url,
    required this.invoiceDocId,
    required this.canReportMissing,
    required this.storagePath,
    this.previewOnly = false,
  });

  @override
  State<SavedInvoicePreviewPage> createState() =>
      _SavedInvoicePreviewPageState();
}

class _SavedInvoicePreviewPageState extends State<SavedInvoicePreviewPage> {
  late Future<Uint8List> _bytesFuture;
  bool _missingConfirmed = false;
  late bool _showingFallbackPreview;

  @override
  void initState() {
    super.initState();
    _showingFallbackPreview = widget.previewOnly;
    _bytesFuture = _fetchBytes();
  }

  Future<Uint8List> _fetchBytes() async {
    Object? lastError;
    var receivedNotFound = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt == 1) {
        await Future<void>.delayed(const Duration(seconds: 1));
      } else if (attempt == 2) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      try {
        if (widget.canReportMissing && widget.storagePath.isNotEmpty) {
          final bytes = await firebase_storage.FirebaseStorage.instance
              .ref()
              .child(widget.storagePath)
              .getData(25 * 1024 * 1024);
          if (bytes == null ||
              bytes.length < 4 ||
              String.fromCharCodes(bytes.take(4)) != '%PDF') {
            throw Exception('The downloaded PDF is invalid.');
          }
          return bytes;
        }
        final response = await http.get(Uri.parse(widget.url));
        receivedNotFound = receivedNotFound || response.statusCode == 404;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Failed to load PDF (${response.statusCode})');
        }
        if (response.bodyBytes.length < 4 ||
            String.fromCharCodes(response.bodyBytes.take(4)) != '%PDF') {
          throw Exception('The downloaded PDF is invalid.');
        }
        return response.bodyBytes;
      } catch (error) {
        if (error is FirebaseException && error.code == 'object-not-found') {
          receivedNotFound = true;
        }
        lastError = error;
      }
    }

    if (receivedNotFound && widget.canReportMissing) {
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'me-west1',
        ).httpsCallable('reportMissingFinalDocumentPdf');
        final result = await callable.call<Map<String, dynamic>>({
          'invoiceDocId': widget.invoiceDocId,
        });
        _missingConfirmed = result.data['missing'] == true;
        if (result.data['previewAvailable'] == true) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final invoiceSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('invoices')
                .doc(widget.invoiceDocId)
                .get(const GetOptions(source: Source.server));
            final fallbackPreview = invoiceSnapshot.data()?['fallbackPreview'];
            final previewPath = fallbackPreview is Map
                ? fallbackPreview['storagePath']?.toString().trim()
                : null;
            if (previewPath != null && previewPath.isNotEmpty) {
              final bytes = await firebase_storage.FirebaseStorage.instance
                  .ref()
                  .child(previewPath)
                  .getData(25 * 1024 * 1024);
              if (bytes != null &&
                  bytes.length >= 4 &&
                  String.fromCharCodes(bytes.take(4)) == '%PDF') {
                _missingConfirmed = false;
                _showingFallbackPreview = true;
                return bytes;
              }
            }
          }
        }
      } catch (_) {
        _missingConfirmed = false;
      }
    }
    throw lastError ?? Exception('Failed to load PDF');
  }

  void _retryDownload() {
    if (_missingConfirmed) return;
    setState(() {
      _missingConfirmed = false;
      _bytesFuture = _fetchBytes();
    });
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
          title: Text(
            _showingFallbackPreview
                ? (isRtl
                      ? 'תצוגה מקדימה • ${widget.name}'
                      : 'Preview • ${widget.name}')
                : widget.name,
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
        ),
        body: FutureBuilder<Uint8List>(
          future: _bytesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 44,
                        color: Color(0xFFB91C1C),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _missingConfirmed
                            ? (isRtl
                                  ? 'קובץ ה-PDF חסר והמסמך הועבר לבדיקה.'
                                  : 'The PDF is missing and the document was sent for review.')
                            : (isRtl
                                  ? 'לא הצלחנו לטעון את הקובץ.'
                                  : 'Failed to load the file.'),
                        textAlign: TextAlign.center,
                      ),
                      if (!_missingConfirmed) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _retryDownload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            isRtl ? 'נסה להוריד שוב' : 'Retry download',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            final bytes = snapshot.data!;
            return PdfPreview(
              canDebug: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              build: (_) async => bytes,
            );
          },
        ),
      ),
    );
  }
}
