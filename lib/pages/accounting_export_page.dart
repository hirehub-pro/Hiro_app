import 'dart:io';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/movein_export_service.dart';
import 'package:untitled1/services/movein_generator.dart';

class AccountingExportPage extends StatefulWidget {
  const AccountingExportPage({super.key});

  @override
  State<AccountingExportPage> createState() => _AccountingExportPageState();
}

class _AccountingExportPageState extends State<AccountingExportPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final Map<String, TextEditingController> _accountControllers = {
    for (final entry in MoveinAccountingSettings.defaultAccountKeys.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  late DateTimeRange _dateRange;
  bool _isLoading = true;
  bool _isWorking = false;
  String _progressStatus = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1, 0),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (final controller in _accountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final raw = snapshot.data()?['accountingExportSettings'];
      final settings = MoveinAccountingSettings.fromMap(
        raw is Map<String, dynamic> ? raw : null,
        fallbackEmail: user.email ?? '',
      );
      for (final entry in settings.accountKeys.entries) {
        _accountControllers[entry.key]?.text = entry.value;
      }
      _emailController.text = settings.recipientEmail;
    } catch (_) {
      _emailController.text = user.email ?? '';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  MoveinAccountingSettings _currentSettings() {
    return MoveinAccountingSettings(
      accountKeys: {
        for (final entry in _accountControllers.entries)
          entry.key: entry.value.text.trim(),
      },
      recipientEmail: _emailController.text.trim(),
    );
  }

  Future<void> _saveSettings({bool showConfirmation = true}) async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final strings = _strings(context, listen: false);
    setState(() {
      _isWorking = true;
      _progressStatus = strings['saving']!;
    });
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'accountingExportSettings': {
          ..._currentSettings().toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (showConfirmation && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['saved']!)));
      }
    } finally {
      if (showConfirmation && mounted) {
        setState(() {
          _isWorking = false;
          _progressStatus = '';
        });
      }
    }
  }

  Future<void> _createAndEmail() async {
    if (_isWorking || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final strings = _strings(context, listen: false);
    Directory? generatedDirectory;
    setState(() {
      _isWorking = true;
      _progressStatus = strings['preparing']!;
    });

    try {
      await _saveSettings(showConfirmation: false);
      if (!mounted) return;
      setState(() => _progressStatus = strings['creating']!);

      final rootDirectory = await getTemporaryDirectory();
      final package = await MoveinExportService.exportForUser(
        firestore: FirebaseFirestore.instance,
        userId: user.uid,
        fromDate: _compactDate(_dateRange.start),
        toDate: _compactDate(_dateRange.end),
        settings: _currentSettings(),
        rootDirectory: rootDirectory,
      );
      generatedDirectory = package.directory;

      if (!mounted) return;
      setState(() => _progressStatus = strings['uploading']!);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final folder = 'users/${user.uid}/accounting_exports/$stamp';
      final paths = <String>[];
      for (final file in package.files) {
        final name = file.uri.pathSegments.last;
        final reference = firebase_storage.FirebaseStorage.instance.ref().child(
          '$folder/$name',
        );
        await reference.putFile(
          file,
          firebase_storage.SettableMetadata(
            contentType: 'application/octet-stream',
          ),
        );
        paths.add(reference.fullPath);
      }

      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      final token = await refreshed?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw StateError(strings['sign_in_again']!);
      }
      if (!mounted) return;
      setState(() => _progressStatus = strings['sending']!);
      final response = await http.post(
        Uri.parse(
          'https://us-central1-hire-hub-fe6c4.cloudfunctions.net/'
          'sendAccountingExportEmailHttp',
        ),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'X-Firebase-Auth': token,
        },
        body: jsonEncode(<String, dynamic>{
          'recipientEmail': _emailController.text.trim(),
          'filePaths': paths,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = strings['try_again']!;
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = body['error']?.toString() ?? message;
        } on FormatException {
          // Keep the localized fallback for non-JSON infrastructure errors.
        }
        throw StateError(message);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings['sent']!.replaceAll(
              '{email}',
              _emailController.text.trim(),
            ),
          ),
          backgroundColor: const Color(0xFF168653),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${strings['error']}: $message'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (generatedDirectory != null && generatedDirectory.existsSync()) {
        await generatedDirectory.delete(recursive: true);
      }
      if (mounted) {
        setState(() {
          _isWorking = false;
          _progressStatus = '';
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: _dateRange,
    );
    if (selected != null && mounted) {
      setState(() => _dateRange = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final languageCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = languageCode == 'he' || languageCode == 'ar';
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _introCard(strings),
                            const SizedBox(height: 18),
                            _section(
                              title: strings['registers']!,
                              children: _accountFields(strings, const [
                                'generalRegister',
                                'creditRegister',
                                'cashRegister',
                                'checksRegister',
                                'transfersRegister',
                                'transfersUsdRegister',
                                'transfersEurRegister',
                                'transfersGbpRegister',
                                'transfersJpyRegister',
                                'otherRegister',
                                'paypalRegister',
                                'bitRegister',
                                'payboxRegister',
                                'pepperRegister',
                                'otherCreditRegister',
                              ]),
                            ),
                            const SizedBox(height: 18),
                            _section(
                              title: strings['accounts']!,
                              children: _accountFields(strings, const [
                                'purchasesAccount',
                                'inputVatAccount',
                                'withholdingTaxAccount',
                                'outputVatAccount',
                                'incomeAccount',
                                'exemptIncomeAccount',
                                'casualCustomerAccount',
                              ]),
                            ),
                            const SizedBox(height: 18),
                            _deliverySection(strings),
                            const SizedBox(height: 20),
                            if (_isWorking) ...[
                              LinearProgressIndicator(
                                borderRadius: BorderRadius.circular(999),
                                minHeight: 8,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _progressStatus,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _isWorking
                                      ? null
                                      : () => _saveSettings(),
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(strings['save']!),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _isWorking
                                      ? null
                                      : _createAndEmail,
                                  icon: const Icon(Icons.outgoing_mail),
                                  label: Text(strings['create']!),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1976D2),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 26,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _introCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            child: Icon(Icons.account_balance, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings['heading']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  strings['description']!,
                  style: const TextStyle(
                    color: Color(0xFFDCEAFE),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 14,
                children: children
                    .map((child) => SizedBox(width: width, child: child))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _accountFields(Map<String, String> strings, List<String> names) {
    return names.map((name) {
      return TextFormField(
        controller: _accountControllers[name],
        maxLength: 15,
        decoration: InputDecoration(
          labelText: strings[name]!,
          counterText: '',
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        validator: (value) {
          final normalized = (value ?? '').trim();
          if (normalized.isEmpty) return strings['required']!;
          if (normalized.length > 15) return strings['too_long']!;
          return null;
        },
      );
    }).toList();
  }

  Widget _deliverySection(Map<String, String> strings) {
    final dateFormat = intl.DateFormat('dd/MM/yyyy');
    return _section(
      title: strings['delivery']!,
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: strings['email']!,
            prefixIcon: const Icon(Icons.alternate_email),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          validator: (value) {
            final email = (value ?? '').trim();
            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
              return strings['invalid_email']!;
            }
            return null;
          },
        ),
        InkWell(
          onTap: _isWorking ? null : _pickDateRange,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: strings['date_range']!,
              prefixIcon: const Icon(Icons.date_range),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              '${dateFormat.format(_dateRange.start)} – ${dateFormat.format(_dateRange.end)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  static String _compactDate(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';

  Map<String, String> _strings(BuildContext context, {bool listen = true}) {
    final language = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;
    return switch (language) {
      'he' => _hebrewStrings,
      'ar' => _arabicStrings,
      'ru' => _russianStrings,
      'am' => _amharicStrings,
      _ => _englishStrings,
    };
  }

  static const _englishStrings = <String, String>{
    'title': 'External Accounting Export',
    'heading': 'Hashavshevet accounting export',
    'description':
        'Set your accounting cards, choose a period, and email the MOVEIN and HESHIN files.',
    'registers': 'Cash and payment registers',
    'accounts': 'Accounting cards',
    'delivery': 'Export period and delivery',
    'email': 'Recipient email',
    'date_range': 'Document date range',
    'save': 'Save settings',
    'create': 'Create and email files',
    'saving': 'Saving settings…',
    'saved': 'Accounting export settings saved.',
    'preparing': 'Preparing the export…',
    'creating': 'Creating MOVEIN and HESHIN files…',
    'uploading': 'Uploading the files securely…',
    'sending': 'Sending the files by email…',
    'sent': 'MOVEIN and HESHIN files were sent to {email}.',
    'error': 'Export failed',
    'service_unavailable':
        'The email service is not available yet. Please try again shortly.',
    'try_again': 'Please try again.',
    'required': 'This card number is required.',
    'too_long': 'Use no more than 15 characters.',
    'invalid_email': 'Enter a valid email address.',
    'sign_in_again': 'Please sign in again before sending the files.',
    'generalRegister': 'General register',
    'creditRegister': 'Credit-card register',
    'cashRegister': 'Cash register',
    'checksRegister': 'Checks register',
    'transfersRegister': 'Bank transfers register',
    'transfersUsdRegister': 'Transfers – US dollar',
    'transfersEurRegister': 'Transfers – euro',
    'transfersGbpRegister': 'Transfers – pound sterling',
    'transfersJpyRegister': 'Transfers – Japanese yen',
    'otherRegister': 'Other register',
    'paypalRegister': 'Other – PayPal',
    'bitRegister': 'Other – Bit',
    'payboxRegister': 'Other – PayBox',
    'pepperRegister': 'Other – Pepper',
    'otherCreditRegister': 'Other – credit',
    'purchasesAccount': 'Purchases account',
    'inputVatAccount': 'Input VAT account',
    'withholdingTaxAccount': 'Withholding-tax account',
    'outputVatAccount': 'Output VAT account',
    'incomeAccount': 'Income account',
    'exemptIncomeAccount': 'VAT-exempt income account',
    'casualCustomerAccount': 'Casual customer account',
  };

  static const _hebrewStrings = <String, String>{
    'title': 'ייצוא להנה״ח חיצונית',
    'heading': 'ייצוא הנהלת חשבונות לחשבשבת',
    'description':
        'הגדירו מספרי כרטיסים, בחרו תקופה וכתובת מייל לקבלת קובצי MOVEIN ו-HESHIN.',
    'registers': 'עדכון מספרי הקופות',
    'accounts': 'כרטיסי הנהלת חשבונות',
    'delivery': 'תקופת הייצוא ושליחת הקבצים',
    'email': 'כתובת מייל לקבלת הקבצים',
    'date_range': 'טווח תאריכי המסמכים',
    'save': 'שמירת הגדרות',
    'create': 'יצירה ושליחה למייל',
    'saving': 'שומר הגדרות…',
    'saved': 'הגדרות הייצוא נשמרו.',
    'preparing': 'מכין את הייצוא…',
    'creating': 'יוצר את קובצי MOVEIN ו-HESHIN…',
    'uploading': 'מעלה את הקבצים באופן מאובטח…',
    'sending': 'שולח את הקבצים למייל…',
    'sent': 'קובצי MOVEIN ו-HESHIN נשלחו אל {email}.',
    'error': 'הייצוא נכשל',
    'service_unavailable':
        'שירות שליחת הקבצים עדיין אינו זמין. נסו שוב בעוד מספר דקות.',
    'try_again': 'יש לנסות שוב.',
    'required': 'חובה להזין מספר כרטיס.',
    'too_long': 'ניתן להזין עד 15 תווים.',
    'invalid_email': 'יש להזין כתובת מייל תקינה.',
    'sign_in_again': 'יש להתחבר מחדש לפני שליחת הקבצים.',
    'generalRegister': 'קופה כללית',
    'creditRegister': 'קופת אשראי',
    'cashRegister': 'קופת מזומן',
    'checksRegister': 'קופת המחאות',
    'transfersRegister': 'קופת העברות',
    'transfersUsdRegister': 'קופת העברות – דולר',
    'transfersEurRegister': 'קופת העברות – יורו',
    'transfersGbpRegister': 'קופת העברות – ליש״ט',
    'transfersJpyRegister': 'קופת העברות – ין יפני',
    'otherRegister': 'קופה אחרת',
    'paypalRegister': 'קופה אחרת – פייפאל',
    'bitRegister': 'קופה אחרת – ביט',
    'payboxRegister': 'קופה אחרת – פייבוקס',
    'pepperRegister': 'קופה אחרת – פפר',
    'otherCreditRegister': 'קופה אחרת – קרדיט',
    'purchasesAccount': 'כרטיס קניות',
    'inputVatAccount': 'כרטיס מע״מ תשומות',
    'withholdingTaxAccount': 'מס במקור',
    'outputVatAccount': 'מע״מ עסקאות',
    'incomeAccount': 'כרטיס הכנסות',
    'exemptIncomeAccount': 'כרטיס הכנסות פטורות',
    'casualCustomerAccount': 'מספר כרטיס לקוח מזדמן',
  };

  static final _arabicStrings = <String, String>{
    ..._englishStrings,
    'title': 'التصدير إلى نظام محاسبة خارجي',
    'heading': 'تصدير المحاسبة إلى Hashavshevet',
    'description':
        'حدّد أرقام الحسابات والفترة والبريد الإلكتروني لاستلام ملفات MOVEIN وHESHIN.',
    'registers': 'حسابات النقد وطرق الدفع',
    'accounts': 'الحسابات المحاسبية',
    'delivery': 'فترة التصدير وإرسال الملفات',
    'email': 'البريد الإلكتروني للمستلم',
    'date_range': 'نطاق تواريخ المستندات',
    'save': 'حفظ الإعدادات',
    'create': 'إنشاء الملفات وإرسالها',
    'saving': 'جارٍ حفظ الإعدادات…',
    'saved': 'تم حفظ إعدادات التصدير.',
    'preparing': 'جارٍ تحضير التصدير…',
    'creating': 'جارٍ إنشاء ملفات MOVEIN وHESHIN…',
    'uploading': 'جارٍ رفع الملفات بأمان…',
    'sending': 'جارٍ إرسال الملفات بالبريد…',
    'sent': 'تم إرسال ملفات MOVEIN وHESHIN إلى {email}.',
    'error': 'فشل التصدير',
    'service_unavailable':
        'خدمة إرسال الملفات غير متاحة بعد. حاول مرة أخرى بعد قليل.',
    'try_again': 'يرجى المحاولة مرة أخرى.',
    'required': 'رقم الحساب مطلوب.',
    'too_long': 'استخدم 15 حرفًا كحد أقصى.',
    'invalid_email': 'أدخل بريدًا إلكترونيًا صحيحًا.',
    'generalRegister': 'الصندوق العام',
    'creditRegister': 'صندوق بطاقات الائتمان',
    'cashRegister': 'صندوق النقد',
    'checksRegister': 'صندوق الشيكات',
    'transfersRegister': 'صندوق التحويلات البنكية',
    'transfersUsdRegister': 'التحويلات – دولار أمريكي',
    'transfersEurRegister': 'التحويلات – يورو',
    'transfersGbpRegister': 'التحويلات – جنيه إسترليني',
    'transfersJpyRegister': 'التحويلات – ين ياباني',
    'otherRegister': 'صندوق آخر',
    'paypalRegister': 'آخر – PayPal',
    'bitRegister': 'آخر – Bit',
    'payboxRegister': 'آخر – PayBox',
    'pepperRegister': 'آخر – Pepper',
    'otherCreditRegister': 'آخر – ائتمان',
    'purchasesAccount': 'حساب المشتريات',
    'inputVatAccount': 'حساب ضريبة المدخلات',
    'withholdingTaxAccount': 'حساب الضريبة المقتطعة',
    'outputVatAccount': 'حساب ضريبة المخرجات',
    'incomeAccount': 'حساب الإيرادات',
    'exemptIncomeAccount': 'حساب الإيرادات المعفاة',
    'casualCustomerAccount': 'حساب العميل العابر',
  };

  static final _russianStrings = <String, String>{
    ..._englishStrings,
    'title': 'Экспорт во внешнюю бухгалтерию',
    'heading': 'Бухгалтерский экспорт для Hashavshevet',
    'description':
        'Укажите номера счетов, период и адрес для получения файлов MOVEIN и HESHIN.',
    'registers': 'Кассы и способы оплаты',
    'accounts': 'Бухгалтерские счета',
    'delivery': 'Период и отправка файлов',
    'email': 'Email получателя',
    'date_range': 'Диапазон дат документов',
    'save': 'Сохранить настройки',
    'create': 'Создать и отправить',
    'saving': 'Сохранение настроек…',
    'saved': 'Настройки экспорта сохранены.',
    'preparing': 'Подготовка экспорта…',
    'creating': 'Создание файлов MOVEIN и HESHIN…',
    'uploading': 'Безопасная загрузка файлов…',
    'sending': 'Отправка файлов по email…',
    'sent': 'Файлы MOVEIN и HESHIN отправлены на {email}.',
    'error': 'Ошибка экспорта',
    'service_unavailable':
        'Сервис отправки файлов пока недоступен. Повторите попытку через несколько минут.',
    'try_again': 'Повторите попытку.',
    'required': 'Укажите номер счета.',
    'too_long': 'Не более 15 символов.',
    'invalid_email': 'Введите корректный email.',
    'generalRegister': 'Общая касса',
    'creditRegister': 'Касса банковских карт',
    'cashRegister': 'Касса наличных',
    'checksRegister': 'Касса чеков',
    'transfersRegister': 'Касса банковских переводов',
    'transfersUsdRegister': 'Переводы – доллар США',
    'transfersEurRegister': 'Переводы – евро',
    'transfersGbpRegister': 'Переводы – фунт стерлингов',
    'transfersJpyRegister': 'Переводы – японская иена',
    'otherRegister': 'Прочая касса',
    'paypalRegister': 'Прочее – PayPal',
    'bitRegister': 'Прочее – Bit',
    'payboxRegister': 'Прочее – PayBox',
    'pepperRegister': 'Прочее – Pepper',
    'otherCreditRegister': 'Прочее – кредит',
    'purchasesAccount': 'Счет покупок',
    'inputVatAccount': 'Счет входного НДС',
    'withholdingTaxAccount': 'Счет налога у источника',
    'outputVatAccount': 'Счет исходящего НДС',
    'incomeAccount': 'Счет доходов',
    'exemptIncomeAccount': 'Счет доходов без НДС',
    'casualCustomerAccount': 'Счет разового клиента',
  };

  static final _amharicStrings = <String, String>{
    ..._englishStrings,
    'title': 'ወደ ውጫዊ የሂሳብ ስርዓት ላክ',
    'heading': 'የሂሳብ ፋይሎችን ወደ Hashavshevet ላክ',
    'description':
        'የሂሳብ ካርድ ቁጥሮችን፣ ጊዜውን እና MOVEIN እና HESHIN ፋይሎችን የሚቀበል ኢሜይል ያስገቡ።',
    'registers': 'የጥሬ ገንዘብና የክፍያ ሂሳቦች',
    'accounts': 'የሂሳብ ካርዶች',
    'delivery': 'የመላኪያ ጊዜና ኢሜይል',
    'email': 'የተቀባይ ኢሜይል',
    'date_range': 'የሰነዶች ቀን ክልል',
    'save': 'ቅንብሮችን አስቀምጥ',
    'create': 'ፋይሎችን ፍጠርና ላክ',
    'saving': 'ቅንብሮችን በማስቀመጥ ላይ…',
    'saved': 'የመላኪያ ቅንብሮች ተቀምጠዋል።',
    'preparing': 'መላኪያውን በማዘጋጀት ላይ…',
    'creating': 'MOVEIN እና HESHIN ፋይሎችን በመፍጠር ላይ…',
    'uploading': 'ፋይሎቹን በደህንነት በመስቀል ላይ…',
    'sending': 'ፋይሎቹን በኢሜይል በመላክ ላይ…',
    'sent': 'MOVEIN እና HESHIN ፋይሎች ወደ {email} ተልከዋል።',
    'error': 'መላክ አልተሳካም',
    'service_unavailable': 'የፋይል መላኪያ አገልግሎቱ ገና አይገኝም። እባክዎ ትንሽ ቆይተው ይሞክሩ።',
    'try_again': 'እባክዎ እንደገና ይሞክሩ።',
    'required': 'የሂሳብ ቁጥር ያስፈልጋል።',
    'too_long': 'ከ15 ቁምፊዎች አይበልጥ።',
    'invalid_email': 'ትክክለኛ ኢሜይል ያስገቡ።',
    'generalRegister': 'አጠቃላይ የገንዘብ ሂሳብ',
    'creditRegister': 'የክሬዲት ካርድ ሂሳብ',
    'cashRegister': 'የጥሬ ገንዘብ ሂሳብ',
    'checksRegister': 'የቼክ ሂሳብ',
    'transfersRegister': 'የባንክ ዝውውር ሂሳብ',
    'transfersUsdRegister': 'ዝውውር – የአሜሪካ ዶላር',
    'transfersEurRegister': 'ዝውውር – ዩሮ',
    'transfersGbpRegister': 'ዝውውር – ፓውንድ',
    'transfersJpyRegister': 'ዝውውር – የጃፓን የን',
    'otherRegister': 'ሌላ የገንዘብ ሂሳብ',
    'paypalRegister': 'ሌላ – PayPal',
    'bitRegister': 'ሌላ – Bit',
    'payboxRegister': 'ሌላ – PayBox',
    'pepperRegister': 'ሌላ – Pepper',
    'otherCreditRegister': 'ሌላ – ክሬዲት',
    'purchasesAccount': 'የግዢ ሂሳብ',
    'inputVatAccount': 'የግብዓት VAT ሂሳብ',
    'withholdingTaxAccount': 'ተቀናሽ ግብር ሂሳብ',
    'outputVatAccount': 'የውጤት VAT ሂሳብ',
    'incomeAccount': 'የገቢ ሂሳብ',
    'exemptIncomeAccount': 'ከVAT ነፃ የገቢ ሂሳብ',
    'casualCustomerAccount': 'የአልፎ አልፎ ደንበኛ ሂሳብ',
  };
}
