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
import 'package:untitled1/widgets/tour_tip_dialog.dart';

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
  InvoiceItem({
    required this.description,
    this.quantity = 1,
    required this.price,
  });

  double get total => quantity * price;
}

class InvoiceBuilderPage extends StatefulWidget {
  final String workerName;
  final String? workerPhone;
  final String? workerEmail;
  final String? receiverId;
  final String? receiverName;
  final String? receiverPhone;
  final String? receiverAddress;
  final String? tourIntroText;

  const InvoiceBuilderPage({
    super.key,
    required this.workerName,
    this.workerPhone,
    this.workerEmail,
    this.receiverId,
    this.receiverName,
    this.receiverPhone,
    this.receiverAddress,
    this.tourIntroText,
  });

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
  final _clientNameController = TextEditingController();
  final _clientAddressController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _invoiceCounterController = TextEditingController(text: "1");
  final _itemDescController = TextEditingController();
  final _itemQtyController = TextEditingController(text: "1");
  final _itemPriceController = TextEditingController();
  final _notesController = TextEditingController();

  final List<InvoiceItem> _items = [];
  bool _isPreparing = false;
  String _invoiceNumber = "";
  double _totalAmount = 0.0;

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

    _bindInvoiceCounterLiveSync();
    _fetchWorkerInfo();
    _loadAssets();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTourIntroIfNeeded();
    });
  }

  Future<void> _showTourIntroIfNeeded() async {
    final intro = widget.tourIntroText;
    if (intro == null || intro.isEmpty || !mounted) return;

    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    await showTourTipDialog(
      context: context,
      title: isRtl ? 'יוצר חשבוניות' : 'Invoice Builder',
      body: intro,
      stepLabel: isRtl ? 'שלב 6 / 8' : 'Step 6 / 8',
      icon: Icons.description_outlined,
      isRtl: isRtl,
      confirmLabel: isRtl ? 'הבנתי' : 'Got it',
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

              if (_isBusinessVerified && _dealerType == 'licensed') {
                _selectedDocType = 'invoice_receipt';
              } else {
                _selectedDocType = 'receipt';
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
    _notesController.dispose();
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
          'items': 'פירוט פריטים ושירותים',
          'desc': 'תיאור השירות/מוצר',
          'qty': 'כמות',
          'price': 'מחיר ליח\'',
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
        };
        break;
      default:
        _cachedStrings = {
          'title': 'Business Document Builder',
          'client_info': 'Client Details:',
          'client_name': 'Client Name',
          'client_address': 'Client Address',
          'client_phone': 'Client Phone',
          'items': 'Service Items & Details',
          'desc': 'Description',
          'qty': 'Qty',
          'price': 'Unit Price',
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
      'items': 'Service Items & Details',
      'desc': 'Description',
      'qty': 'Qty',
      'price': 'Unit Price',
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
    };

    return {...defaults, ...source};
  }

  void _addItem() {
    if (_itemDescController.text.isEmpty || _itemPriceController.text.isEmpty)
      return;
    final price = double.tryParse(_itemPriceController.text) ?? 0.0;
    final qty = int.tryParse(_itemQtyController.text) ?? 1;
    setState(() {
      final newItem = InvoiceItem(
        description: _itemDescController.text,
        quantity: qty,
        price: price,
      );
      _items.add(newItem);
      _totalAmount += newItem.total;
      _itemDescController.clear();
      _itemPriceController.clear();
      _itemQtyController.text = "1";
    });
  }

  void _removeItem(int index) {
    setState(() {
      _totalAmount -= _items[index].total;
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
              await _saveInvoicePdf(pdfBytes);
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
        .collection('saved_invoices');

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
      final storagePath = 'saved_invoices/${currentUser.uid}/$safeName.pdf';

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
        'amount': _totalAmount,
        'invoiceNumber': _invoiceNumber,
        'createdAt': FieldValue.serverTimestamp(),
      });

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
        // Increase margins significantly to avoid content sticking to the border
        pageFormat: format.copyWith(
          marginTop: 1.5 * pdf.PdfPageFormat.cm,
          marginBottom: 1.5 * pdf.PdfPageFormat.cm,
          marginLeft: 1.5 * pdf.PdfPageFormat.cm,
          marginRight: 1.5 * pdf.PdfPageFormat.cm,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context context) {
          final isInvoice =
              _selectedDocType == 'invoice' ||
              _selectedDocType == 'invoice_receipt';
          final docTitle = _selectedDocType == 'receipt'
              ? strings['receipt']!
              : _selectedDocType == 'invoice'
              ? strings['invoice']!
              : strings['invoice_receipt']!;

          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Formal Header Section
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo (RTL: appears on the right)
                    if (logo != null) pw.Image(logo, width: 85, height: 85),
                    // Document Info (RTL: appears on the left)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              docTitle,
                              style: pw.TextStyle(
                                fontSize: 28,
                                fontWeight: pw.FontWeight.bold,
                                color: pdf.PdfColors.black,
                              ),
                            ),
                            pw.Text(
                              strings['original']!,
                              style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 12),
                        pw.Text(
                          isInvoice
                              ? "${strings['tax_invoice_num']} $_invoiceNumber"
                              : "${strings['inv_no']} $_invoiceNumber",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        pw.Text(
                          "${strings['date']} ${intl.DateFormat('dd/MM/yyyy').format(DateTime.now())}",
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(thickness: 2, color: pdf.PdfColors.black),
                pw.SizedBox(height: 25),

                // Business & Client Information Block
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Business Details (RTL: Right side)
                    pw.Expanded(
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
                          pw.SizedBox(height: 8),
                          pw.Text(
                            widget.workerName,
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),

                          // Consistently show all ID authorized_dealer_label Address fields
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
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                            pw.Text(
                              _dealerType == 'licensed'
                                  ? strings['licensed_dealer']!
                                  : strings['exempt_dealer']!,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ],

                          if (_businessAddress != null &&
                              _businessAddress!.isNotEmpty) ...[
                            pw.Text(
                              "${strings['business_address']} $_businessAddress",
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ],

                          if (widget.workerPhone != null)
                            pw.Text(
                              widget.workerPhone!,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          if (widget.workerEmail != null)
                            pw.Text(
                              widget.workerEmail!,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 50),
                    // Client Details (RTL: Left side)
                    pw.Expanded(
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
                          pw.SizedBox(height: 8),
                          pw.Text(
                            _clientNameController.text,
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (_clientPhoneController.text.isNotEmpty)
                            pw.Text(
                              _clientPhoneController.text,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          if (_clientAddressController.text.isNotEmpty)
                            pw.Text(
                              _clientAddressController.text,
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 40),

                // Professional Table for Items
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
                          "${item.price.toStringAsFixed(2)} ₪",
                          "${item.total.toStringAsFixed(2)} ₪",
                        ],
                      )
                      .toList(),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: pdf.PdfColors.white,
                    fontSize: 11,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: pdf.PdfColors.black,
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
                pw.SizedBox(height: 20),

                // Calculation Summary Section
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Spacer(flex: 2),
                    pw.Expanded(
                      flex: 1,
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
                                  style: const pw.TextStyle(fontSize: 10),
                                ),
                                pw.Text(
                                  "${(_totalAmount / 1.17).toStringAsFixed(2)} ₪",
                                  style: const pw.TextStyle(fontSize: 10),
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
                                  style: const pw.TextStyle(fontSize: 10),
                                ),
                                pw.Text(
                                  "${(_totalAmount - (_totalAmount / 1.17)).toStringAsFixed(2)} ₪",
                                  style: const pw.TextStyle(fontSize: 10),
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
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                "${_totalAmount.toStringAsFixed(2)} ₪",
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (_notesController.text.isNotEmpty) ...[
                  pw.SizedBox(height: 30),
                  pw.Text(
                    strings['notes']!,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
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
                ],

                pw.Spacer(),
                pw.Divider(thickness: 1, color: pdf.PdfColors.black),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    strings['legal_disclaimer']!,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: pdf.PdfColors.black,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 8),
              ],
            ),
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
                              ],
                              onChanged: (val) {
                                if (val != null)
                                  setState(() => _selectedDocType = val);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _invoiceCounterController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) {
                                final year = intl.DateFormat(
                                  'yyyy',
                                ).format(DateTime.now());
                                final counter =
                                    int.tryParse(
                                      _invoiceCounterController.text,
                                    ) ??
                                    1;
                                setState(() {
                                  _invoiceNumber =
                                      '$year-${(counter < 1 ? 1 : counter).toString().padLeft(4, '0')}';
                                });
                              },
                              onSubmitted: (_) =>
                                  _syncInvoiceNumberFromCounter(),
                              decoration: _inputStyle(
                                strings['invoice_counter']!,
                                Icons.format_list_numbered_rounded,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _syncInvoiceNumberFromCounter(),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  isRtl
                                      ? 'עדכן מספר מסמך'
                                      : 'Update Document Number',
                                ),
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
                                    "${item.quantity} x ${item.price.toStringAsFixed(2)} ₪",
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${item.total.toStringAsFixed(2)} ₪",
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
                                      "${_totalAmount.toStringAsFixed(2)} ₪",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
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

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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
