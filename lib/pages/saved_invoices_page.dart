import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTourIntroIfNeeded();
    });
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
        appBar: AppBar(
          title: Text(isRtl ? 'חשבוניות שמורות' : 'Saved Invoices'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? const [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  isRtl
                      ? 'אין חשבוניות שמורות עדיין.'
                      : 'No saved invoices yet.',
                  style: const TextStyle(color: Colors.grey),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final name = (data['name'] ?? 'Invoice').toString();
                final fileName = (data['fileName'] ?? '$name.pdf').toString();
                final url = (data['url'] ?? '').toString();
                final createdAt = data['createdAt'] as Timestamp?;
                final amount = (data['amount'] as num?)?.toDouble();
                final createdText = createdAt == null
                    ? ''
                    : intl.DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(createdAt.toDate());

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE8F1FB),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (createdText.isNotEmpty)
                          Text(
                            createdText,
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (amount != null)
                          Text(
                            '${amount.toStringAsFixed(2)} ₪',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      if (url.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SavedInvoicePreviewPage(name: fileName, url: url),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
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
