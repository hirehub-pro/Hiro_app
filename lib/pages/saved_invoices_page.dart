import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/widgets/tour_tip_dialog.dart';

class SavedInvoicesPage extends StatefulWidget {
  final String? tourIntroText;

  const SavedInvoicesPage({super.key, this.tourIntroText});

  @override
  State<SavedInvoicesPage> createState() => _SavedInvoicesPageState();
}

class _SavedInvoicesPageState extends State<SavedInvoicesPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _selectedDocType = 'all';
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTourIntroIfNeeded();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showTourIntroIfNeeded() async {
    final intro = widget.tourIntroText;
    if (intro == null || intro.isEmpty || !mounted) return;

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

    await showTourTipDialog(
      context: context,
      title: isRtl ? 'חשבוניות שמורות' : 'Saved Invoices',
      body: intro,
      stepLabel: isRtl ? 'שלב 7 / 8' : 'Step 7 / 8',
      icon: Icons.folder_copy_outlined,
      isRtl: isRtl,
      confirmLabel: isRtl ? 'הבנתי' : 'Got it',
    );
  }

  String _docTypeLabel(String? docType, bool isRtl) {
    switch (docType) {
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

  Future<void> _pickDateRange(bool isRtl) async {
    final now = DateTime.now();
    final initialRange =
        _selectedDateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );

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

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('saved_invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(isRtl ? 'חשבוניות שמורות' : 'Saved Invoices'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? const [];
            if (docs.isEmpty) {
              return _buildEmptyState(isRtl);
            }

            final query = _searchController.text.trim().toLowerCase();
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

              if (query.isEmpty) return true;

              final haystack = [
                data['name'],
                data['fileName'],
                data['clientName'],
                data['invoiceNumber'],
                data['docType'],
              ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

              return haystack.contains(query);
            }).toList();

            final totalAmount = docs.fold<double>(0, (sum, doc) {
              final amount = (doc.data()['amount'] as num?)?.toDouble() ?? 0;
              return sum + amount;
            });

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x0F0F172A),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isRtl
                                  ? 'ארכיון המסמכים שלך'
                                  : 'Your document archive',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${docs.length} ${isRtl ? 'מסמכים שמורים' : 'saved documents'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${isRtl ? 'סה״כ' : 'Total'} ${totalAmount.toStringAsFixed(2)} ₪',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        focusNode: _searchFocusNode,
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: isRtl
                              ? 'חפש לפי לקוח, מספר או סוג מסמך'
                              : 'Search by client, number, or document type',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.date_range_rounded),
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
                              tooltip: isRtl ? 'נקה תאריך' : 'Clear date filter',
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
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildFilterChip('all', isRtl ? 'הכל' : 'All'),
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
                    ],
                  ),
                ),
                Expanded(
                  child: filteredDocs.isEmpty
                      ? Center(
                          child: Text(
                            isRtl
                                ? 'לא נמצאו מסמכים התואמים לחיפוש או לטווח התאריכים.'
                                : 'No documents matched your search or date filter.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final data = filteredDocs[index].data();
                            final name = (data['name'] ?? 'Invoice').toString();
                            final fileName = (data['fileName'] ?? '$name.pdf')
                                .toString();
                            final url = (data['url'] ?? '').toString();
                            final createdAt = data['createdAt'] as Timestamp?;
                            final amount = (data['amount'] as num?)?.toDouble();
                            final clientName = (data['clientName'] ?? '')
                                .toString()
                                .trim();
                            final invoiceNumber = (data['invoiceNumber'] ?? '')
                                .toString();
                            final docType = (data['docType'] ?? '').toString();
                            final createdText = createdAt == null
                                ? ''
                                : intl.DateFormat(
                                    'dd/MM/yyyy HH:mm',
                                  ).format(createdAt.toDate());
                            final accent = _docTypeColor(docType);

                            return InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                if (url.isEmpty) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SavedInvoicePreviewPage(
                                      name: fileName,
                                      url: url,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0D0F172A),
                                      blurRadius: 14,
                                      offset: Offset(0, 6),
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
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
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
                                                runSpacing: 8,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
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
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  if (invoiceNumber.isNotEmpty)
                                                    Text(
                                                      '#$invoiceNumber',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(
                                                          0xFF475569,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              if (clientName.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  clientName,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _buildMetaPill(
                                          icon: Icons.calendar_today_outlined,
                                          text: createdText.isEmpty
                                              ? (isRtl
                                                    ? 'ללא תאריך'
                                                    : 'No date')
                                              : createdText,
                                        ),
                                        if (amount != null)
                                          _buildMetaPill(
                                            icon: Icons.payments_outlined,
                                            text:
                                                '${amount.toStringAsFixed(2)} ₪',
                                            isStrong: true,
                                          ),
                                      ],
                                    ),
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
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Widget _buildMetaPill({
    required IconData icon,
    required String text,
    bool isStrong = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isStrong ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isRtl) {
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
              isRtl ? 'עדיין אין מסמכים שמורים' : 'No saved documents yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRtl
                  ? 'כשתשמור חשבונית, קבלה או זיכוי, הם יופיעו כאן לצפייה מהירה.'
                  : 'When you save an invoice, receipt, or credit note, it will appear here for quick access.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedInvoicePreviewPage extends StatefulWidget {
  final String name;
  final String url;

  const SavedInvoicePreviewPage({
    super.key,
    required this.name,
    required this.url,
  });

  @override
  State<SavedInvoicePreviewPage> createState() =>
      _SavedInvoicePreviewPageState();
}

class _SavedInvoicePreviewPageState extends State<SavedInvoicePreviewPage> {
  late final Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _fetchBytes();
  }

  Future<Uint8List> _fetchBytes() async {
    final response = await http.get(Uri.parse(widget.url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load PDF');
    }
    return response.bodyBytes;
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
          title: Text(widget.name),
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
                child: Text(
                  isRtl ? 'נכשלה טעינת הקובץ' : 'Failed to load file',
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
