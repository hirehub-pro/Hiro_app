import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/pages/saved_invoices_page.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';

enum ClientDetailsAction { edit }

class ClientDetailsPage extends StatelessWidget {
  const ClientDetailsPage({super.key, required this.clientId});

  final String clientId;

  Future<void> _createDocument(
    BuildContext context,
    User user,
    _ClientDetails client,
    _ClientDetailsStrings strings,
  ) async {
    try {
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userSnapshot.data() ?? <String, dynamic>{};
      final workerName = (userData['name'] ?? user.displayName ?? '')
          .toString()
          .trim();
      final workerPhone = (userData['phone'] ?? '').toString().trim();
      final workerEmail = (userData['email'] ?? user.email ?? '')
          .toString()
          .trim();
      final isBusinessVerified = userData['isVerified'] == true;

      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isBusinessVerified
              ? InvoiceBuilderPage(
                  workerName: workerName.isEmpty ? 'Worker' : workerName,
                  workerPhone: workerPhone.isEmpty ? null : workerPhone,
                  workerEmail: workerEmail.isEmpty ? null : workerEmail,
                  initialDocType: 'quote',
                  initialSavedClientId: clientId,
                  initialClientTaxId: client.taxId,
                  initialClientExternalNumber: client.externalClientNumber,
                  receiverName: client.name,
                  receiverPhone: client.primaryPhone,
                  receiverEmail: client.primaryEmail,
                  receiverAddress: client.address,
                )
              : const VerifyBusinessPage(),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.documentOpenFailed)));
    }
  }

  Future<void> _launchContact(
    BuildContext context,
    Uri uri,
    _ClientDetailsStrings strings,
  ) async {
    try {
      final opened = await launchUrl(uri);
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.openFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LanguageProvider>().locale.languageCode;
    final strings = _ClientDetailsStrings.forLocale(locale);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          strings.title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: strings.edit,
            onPressed: () => Navigator.pop(context, ClientDetailsAction.edit),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: user == null
          ? _DetailsMessage(
              icon: Icons.lock_outline_rounded,
              title: strings.loginRequired,
              message: strings.loginMessage,
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('clients')
                  .doc(clientId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _DetailsMessage(
                    icon: Icons.cloud_off_rounded,
                    title: strings.loadFailed,
                    message: strings.tryAgain,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return _DetailsMessage(
                    icon: Icons.person_off_outlined,
                    title: strings.notFound,
                    message: strings.notFoundMessage,
                  );
                }

                final client = _ClientDetails.fromData(snapshot.data!.data()!);
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 42),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ClientHero(client: client, strings: strings),
                          if (client.linkedUserId.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatPage(
                                      receiverId: client.linkedUserId,
                                      receiverName: client.name,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                ),
                                label: Text(strings.openChat),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1976D2),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(
                            height: client.linkedUserId.isNotEmpty ? 10 : 16,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _createDocument(
                                    context,
                                    user,
                                    client,
                                    strings,
                                  ),
                                  icon: const Icon(
                                    Icons.note_add_outlined,
                                    size: 19,
                                  ),
                                  label: Text(
                                    strings.createDocument,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEAF4FF),
                                    foregroundColor: const Color(0xFF1565C0),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size.fromHeight(58),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: client.externalClientNumber.isEmpty
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SavedInvoicesPage(
                                              initialSearchQuery:
                                                  client.externalClientNumber,
                                            ),
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.folder_copy_outlined,
                                    size: 19,
                                  ),
                                  label: Text(
                                    strings.savedInvoices,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF0F766E),
                                    side: const BorderSide(
                                      color: Color(0xFF99D5CE),
                                    ),
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size.fromHeight(58),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (client.phones.isNotEmpty ||
                              client.emails.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _SectionTitle(
                              icon: Icons.contact_phone_outlined,
                              title: strings.contactDetails,
                            ),
                            const SizedBox(height: 12),
                            _DetailsCard(
                              children: [
                                for (
                                  var index = 0;
                                  index < client.phones.length;
                                  index++
                                )
                                  _ContactRow(
                                    icon: Icons.phone_outlined,
                                    value: client.phones[index],
                                    primary: index == 0,
                                    primaryLabel: strings.primary,
                                    onTap: () => _launchContact(
                                      context,
                                      Uri.parse('tel:${client.phones[index]}'),
                                      strings,
                                    ),
                                  ),
                                for (
                                  var index = 0;
                                  index < client.emails.length;
                                  index++
                                )
                                  _ContactRow(
                                    icon: Icons.email_outlined,
                                    value: client.emails[index],
                                    primary: index == 0,
                                    primaryLabel: strings.primary,
                                    onTap: () => _launchContact(
                                      context,
                                      Uri(
                                        scheme: 'mailto',
                                        path: client.emails[index],
                                      ),
                                      strings,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (client.externalClientNumber.isNotEmpty ||
                              client.taxId.isNotEmpty ||
                              client.address.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _SectionTitle(
                              icon: Icons.business_outlined,
                              title: strings.businessDetails,
                            ),
                            const SizedBox(height: 12),
                            _DetailsCard(
                              children: [
                                if (client.externalClientNumber.isNotEmpty)
                                  _InfoRow(
                                    icon: Icons.tag_rounded,
                                    label: strings.externalNumber,
                                    value: client.externalClientNumber,
                                  ),
                                if (client.taxId.isNotEmpty)
                                  _InfoRow(
                                    icon: Icons.badge_outlined,
                                    label: strings.taxId,
                                    value: client.taxId,
                                  ),
                                if (client.address.isNotEmpty)
                                  _InfoRow(
                                    icon: Icons.location_on_outlined,
                                    label: strings.address,
                                    value: client.address,
                                  ),
                              ],
                            ),
                          ],
                          if (client.notes.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _SectionTitle(
                              icon: Icons.notes_rounded,
                              title: strings.notes,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                client.notes,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  height: 1.55,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ClientHero extends StatelessWidget {
  const _ClientHero({required this.client, required this.strings});

  final _ClientDetails client;
  final _ClientDetailsStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  client.initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      strings.client,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1976D2), size: 21),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(children: children),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    required this.primary,
    required this.primaryLabel,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final bool primary;
  final String primaryLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: const Color(0xFF1976D2), size: 20),
      ),
      title: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: primary
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(
                    color: Color(0xFF15803D),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : null,
      trailing: const Icon(Icons.open_in_new_rounded, size: 17),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: const Color(0xFF475569), size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
      subtitle: SelectableText(
        value,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailsMessage extends StatelessWidget {
  const _DetailsMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientDetails {
  const _ClientDetails({
    required this.name,
    required this.linkedUserId,
    required this.externalClientNumber,
    required this.taxId,
    required this.phones,
    required this.emails,
    required this.address,
    required this.notes,
  });

  factory _ClientDetails.fromData(Map<String, dynamic> data) {
    final fallbackPhone = (data['phone'] ?? '').toString().trim();
    final fallbackEmail = (data['email'] ?? '').toString().trim();
    return _ClientDetails(
      name: (data['name'] ?? '').toString().trim(),
      linkedUserId: (data['linkedUserId'] ?? '').toString().trim(),
      externalClientNumber: (data['externalClientNumber'] ?? '')
          .toString()
          .trim(),
      taxId: (data['taxId'] ?? '').toString().trim(),
      phones: _contactValues(data['phones'], fallbackPhone),
      emails: _contactValues(data['emails'], fallbackEmail),
      address: (data['address'] ?? '').toString().trim(),
      notes: (data['notes'] ?? '').toString().trim(),
    );
  }

  final String name;
  final String linkedUserId;
  final String externalClientNumber;
  final String taxId;
  final List<String> phones;
  final List<String> emails;
  final String address;
  final String notes;

  String get primaryPhone => phones.isEmpty ? '' : phones.first;
  String get primaryEmail => emails.isEmpty ? '' : emails.first;
  String get initial =>
      name.isEmpty ? '?' : name.characters.first.toUpperCase();

  static List<String> _contactValues(dynamic rawValues, String fallback) {
    final values = rawValues is List
        ? rawValues
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    if (values.isNotEmpty) return values;
    return fallback.isEmpty ? const [] : [fallback];
  }
}

class _ClientDetailsStrings {
  const _ClientDetailsStrings(this.values);

  factory _ClientDetailsStrings.forLocale(String locale) =>
      _ClientDetailsStrings(_translations[locale] ?? _translations['en']!);

  final Map<String, String> values;

  String get title => values['title']!;
  String get client => values['client']!;
  String get edit => values['edit']!;
  String get openChat => values['openChat']!;
  String get createDocument => values['createDocument']!;
  String get savedInvoices => values['savedInvoices']!;
  String get documentOpenFailed => values['documentOpenFailed']!;
  String get externalNumber => values['externalNumber']!;
  String get contactDetails => values['contactDetails']!;
  String get primary => values['primary']!;
  String get businessDetails => values['businessDetails']!;
  String get taxId => values['taxId']!;
  String get address => values['address']!;
  String get notes => values['notes']!;
  String get openFailed => values['openFailed']!;
  String get loginRequired => values['loginRequired']!;
  String get loginMessage => values['loginMessage']!;
  String get loadFailed => values['loadFailed']!;
  String get tryAgain => values['tryAgain']!;
  String get notFound => values['notFound']!;
  String get notFoundMessage => values['notFoundMessage']!;

  static const _translations = <String, Map<String, String>>{
    'en': {
      'title': 'Client details',
      'client': 'Client',
      'edit': 'Edit',
      'openChat': 'Open chat',
      'createDocument': 'Create another document',
      'savedInvoices': 'Saved documents for this client',
      'documentOpenFailed': 'Could not open the document builder.',
      'externalNumber': 'Client number in external accountancy',
      'contactDetails': 'Contact details',
      'primary': 'Primary • used in documents',
      'businessDetails': 'Business details',
      'taxId': 'Business No. / ID / Tax ID',
      'address': 'Address',
      'notes': 'Notes',
      'openFailed': 'Could not open this contact method.',
      'loginRequired': 'Sign in required',
      'loginMessage': 'Sign in to view this client.',
      'loadFailed': 'Could not load client',
      'tryAgain': 'Check your connection and try again.',
      'notFound': 'Client not found',
      'notFoundMessage': 'This client may have been deleted.',
    },
    'he': {
      'title': 'פרטי לקוח',
      'client': 'לקוח',
      'edit': 'ערוך',
      'openChat': 'פתח צ׳אט',
      'createDocument': 'צור מסמך נוסף',
      'savedInvoices': 'מסמכים שמורים של הלקוח',
      'documentOpenFailed': 'לא ניתן לפתוח את יוצר המסמכים.',
      'externalNumber': 'מס׳ לקוח בהנה״ח חיצונית',
      'contactDetails': 'פרטי קשר',
      'primary': 'ראשי • משמש במסמכים',
      'businessDetails': 'פרטי העסק',
      'taxId': 'מס׳ עוסק / ת.ז. / ח.פ.',
      'address': 'כתובת',
      'notes': 'הערות',
      'openFailed': 'לא ניתן לפתוח את פרטי הקשר.',
      'loginRequired': 'נדרשת התחברות',
      'loginMessage': 'יש להתחבר כדי לצפות בלקוח.',
      'loadFailed': 'לא ניתן לטעון את הלקוח',
      'tryAgain': 'בדוק את החיבור ונסה שוב.',
      'notFound': 'הלקוח לא נמצא',
      'notFoundMessage': 'ייתכן שהלקוח נמחק.',
    },
    'ar': {
      'title': 'تفاصيل العميل',
      'client': 'عميل',
      'edit': 'تعديل',
      'openChat': 'فتح المحادثة',
      'createDocument': 'إنشاء مستند آخر',
      'savedInvoices': 'مستندات العميل المحفوظة',
      'documentOpenFailed': 'تعذر فتح منشئ المستندات.',
      'externalNumber': 'رقم العميل في المحاسبة الخارجية',
      'contactDetails': 'بيانات الاتصال',
      'primary': 'رئيسي • يُستخدم في المستندات',
      'businessDetails': 'بيانات العمل',
      'taxId': 'رقم النشاط / الهوية / الضريبة',
      'address': 'العنوان',
      'notes': 'ملاحظات',
      'openFailed': 'تعذر فتح وسيلة الاتصال.',
      'loginRequired': 'تسجيل الدخول مطلوب',
      'loginMessage': 'سجّل الدخول لعرض هذا العميل.',
      'loadFailed': 'تعذر تحميل العميل',
      'tryAgain': 'تحقق من الاتصال وحاول مرة أخرى.',
      'notFound': 'العميل غير موجود',
      'notFoundMessage': 'ربما تم حذف هذا العميل.',
    },
    'ru': {
      'title': 'Данные клиента',
      'client': 'Клиент',
      'edit': 'Изменить',
      'openChat': 'Открыть чат',
      'createDocument': 'Создать другой документ',
      'savedInvoices': 'Сохраненные документы клиента',
      'documentOpenFailed': 'Не удалось открыть конструктор документов.',
      'externalNumber': 'Номер клиента во внешней бухгалтерии',
      'contactDetails': 'Контактные данные',
      'primary': 'Основной • используется в документах',
      'businessDetails': 'Деловые данные',
      'taxId': 'Рег. номер / ID / налоговый номер',
      'address': 'Адрес',
      'notes': 'Заметки',
      'openFailed': 'Не удалось открыть контакт.',
      'loginRequired': 'Требуется вход',
      'loginMessage': 'Войдите для просмотра клиента.',
      'loadFailed': 'Не удалось загрузить клиента',
      'tryAgain': 'Проверьте соединение и повторите попытку.',
      'notFound': 'Клиент не найден',
      'notFoundMessage': 'Возможно, клиент был удален.',
    },
    'am': {
      'title': 'የደንበኛ ዝርዝሮች',
      'client': 'ደንበኛ',
      'edit': 'አርትዕ',
      'openChat': 'ውይይት ክፈት',
      'createDocument': 'ሌላ ሰነድ ፍጠር',
      'savedInvoices': 'የደንበኛው የተቀመጡ ሰነዶች',
      'documentOpenFailed': 'የሰነድ አዘጋጁን መክፈት አልተቻለም።',
      'externalNumber': 'የውጭ ሂሳብ የደንበኛ ቁጥር',
      'contactDetails': 'የመገናኛ መረጃ',
      'primary': 'ዋና • በሰነዶች ውስጥ ይጠቀማል',
      'businessDetails': 'የንግድ ዝርዝሮች',
      'taxId': 'የንግድ / መታወቂያ / ግብር ቁጥር',
      'address': 'አድራሻ',
      'notes': 'ማስታወሻዎች',
      'openFailed': 'የመገናኛ ዘዴውን መክፈት አልተቻለም።',
      'loginRequired': 'መግባት ያስፈልጋል',
      'loginMessage': 'ይህን ደንበኛ ለማየት ይግቡ።',
      'loadFailed': 'ደንበኛውን መጫን አልተቻለም',
      'tryAgain': 'ግንኙነትዎን ይፈትሹና እንደገና ይሞክሩ።',
      'notFound': 'ደንበኛው አልተገኘም',
      'notFoundMessage': 'ደንበኛው ተሰርዞ ሊሆን ይችላል።',
    },
  };
}
