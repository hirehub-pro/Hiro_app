import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/pages/saved_invoices_page.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

class _ClientBankBranch {
  const _ClientBankBranch({required this.name, required this.code});

  final String name;
  final String code;

  String get label => '$name - $code';
}

Map<String, List<_ClientBankBranch>> _parseClientBankBranches(String xmlText) {
  final document = XmlDocument.parse(xmlText);
  final branchesByBankId = <String, List<_ClientBankBranch>>{};

  for (final branch in document.findAllElements('branch')) {
    final bankId = branch.getElement('id')?.innerText.trim() ?? '';
    final branchName = branch.getElement('branch_name')?.innerText.trim() ?? '';
    final branchCode = branch.getElement('branch_code')?.innerText.trim() ?? '';
    if (bankId.isEmpty || branchName.isEmpty || branchCode.isEmpty) continue;

    branchesByBankId
        .putIfAbsent(bankId, () => [])
        .add(_ClientBankBranch(name: branchName, code: branchCode));
  }

  for (final branches in branchesByBankId.values) {
    branches.sort((a, b) => a.label.compareTo(b.label));
  }
  return branchesByBankId;
}

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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          bottom: TabBar(
            labelColor: const Color(0xFF1976D2),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFF1976D2),
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: strings.clientDetailsTab),
              Tab(text: strings.contactDetails),
            ],
          ),
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

                  final client = _ClientDetails.fromData(
                    snapshot.data!.data()!,
                  );
                  return TabBarView(
                    children: [
                      SingleChildScrollView(
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
                                        backgroundColor: const Color(
                                          0xFF1976D2,
                                        ),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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
                                  height: client.linkedUserId.isNotEmpty
                                      ? 10
                                      : 16,
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
                                          backgroundColor: const Color(
                                            0xFFEAF4FF,
                                          ),
                                          foregroundColor: const Color(
                                            0xFF1565C0,
                                          ),
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          minimumSize: const Size.fromHeight(
                                            58,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
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
                                        onPressed:
                                            client.externalClientNumber.isEmpty
                                            ? null
                                            : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => SavedInvoicesPage(
                                                    initialSearchQuery: client
                                                        .externalClientNumber,
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
                                          foregroundColor: const Color(
                                            0xFF0F766E,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF99D5CE),
                                          ),
                                          backgroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          minimumSize: const Size.fromHeight(
                                            58,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
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
                                            Uri.parse(
                                              'tel:${client.phones[index]}',
                                            ),
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
                                      if (client
                                          .externalClientNumber
                                          .isNotEmpty)
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
                      ),
                      _ClientContactDetailsTab(
                        clientId: clientId,
                        userId: user.uid,
                        client: client,
                        strings: strings,
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _ClientContactDetailsTab extends StatefulWidget {
  const _ClientContactDetailsTab({
    required this.clientId,
    required this.userId,
    required this.client,
    required this.strings,
  });

  final String clientId;
  final String userId;
  final _ClientDetails client;
  final _ClientDetailsStrings strings;

  @override
  State<_ClientContactDetailsTab> createState() =>
      _ClientContactDetailsTabState();
}

class _ClientContactDetailsTabState extends State<_ClientContactDetailsTab> {
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

  final _formKey = GlobalKey<FormState>();
  final _bankFocusNode = FocusNode();
  final _branchFocusNode = FocusNode();
  final Map<String, List<_ClientBankBranch>> _branchesByBankId = {};
  late final Map<String, TextEditingController> _controllers;
  bool _isLoadingBankBranches = true;
  bool _bankBranchesLoadFailed = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final details = widget.client.contactDetails;
    _controllers = {
      'street': TextEditingController(text: details.street),
      'city': TextEditingController(text: details.city),
      'zipCode': TextEditingController(text: details.zipCode),
      'country': TextEditingController(text: details.country),
      'contactName': TextEditingController(text: details.contactName),
      'contactEmail': TextEditingController(text: details.contactEmail),
      'fax': TextEditingController(text: details.fax),
      'accountingContactName': TextEditingController(
        text: details.accountingContactName,
      ),
      'accountingContactEmail': TextEditingController(
        text: details.accountingContactEmail,
      ),
      'accountingContactPhone': TextEditingController(
        text: details.accountingContactPhone,
      ),
      'customerContent': TextEditingController(text: details.customerContent),
      'bankName': TextEditingController(text: details.bankName),
      'bankBranch': TextEditingController(text: details.bankBranch),
      'bankAccountNumber': TextEditingController(
        text: details.bankAccountNumber,
      ),
    };
    _loadBankBranches();
  }

  Future<void> _loadBankBranches() async {
    try {
      final xmlText = await rootBundle.loadString('assets/snifim_he.xml');
      final branches = await compute(_parseClientBankBranches, xmlText);
      if (!mounted) return;
      setState(() {
        _branchesByBankId
          ..clear()
          ..addAll(branches);
        _isLoadingBankBranches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBankBranches = false;
        _bankBranchesLoadFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _bankFocusNode.dispose();
    _branchFocusNode.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _controllers[key]!.text.trim();

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? null
        : widget.strings.invalidEmail;
  }

  String? _bankIdFromSelection(String bankName) {
    final matches = RegExp(r'\d+').allMatches(bankName).toList();
    return matches.isEmpty ? null : matches.last.group(0);
  }

  void _clearInvalidBank() {
    final bankController = _controllers['bankName']!;
    if (bankController.text.trim().isEmpty ||
        _bankNames.contains(bankController.text.trim())) {
      return;
    }
    setState(() {
      bankController.clear();
      _controllers['bankBranch']!.clear();
    });
  }

  void _clearInvalidBranch() {
    final branchController = _controllers['bankBranch']!;
    final branch = branchController.text.trim();
    if (branch.isEmpty) return;
    final bankId = _bankIdFromSelection(_value('bankName'));
    final branches = bankId == null
        ? const <_ClientBankBranch>[]
        : _branchesByBankId[bankId] ?? const <_ClientBankBranch>[];
    if (branches.any((availableBranch) => availableBranch.label == branch)) {
      return;
    }
    setState(branchController.clear);
  }

  InputDecoration _bankInputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF1F5FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
    );
  }

  Widget _buildBankAutocomplete() {
    final bankController = _controllers['bankName']!;
    final branchController = _controllers['bankBranch']!;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _clearInvalidBank();
      },
      child: Autocomplete<String>(
        textEditingController: bankController,
        focusNode: _bankFocusNode,
        displayStringForOption: (bank) => bank,
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return _bankNames;
          return _bankNames.where((bank) => bank.toLowerCase().contains(query));
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            onChanged: (_) {
              setState(branchController.clear);
            },
            validator: (value) {
              final bank = value?.trim() ?? '';
              if (bank.isEmpty || _bankNames.contains(bank)) return null;
              return widget.strings.selectBankFromList;
            },
            decoration: _bankInputDecoration(
              label: widget.strings.bank,
              icon: Icons.account_balance_outlined,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final banks = options.toList();
          return Align(
            alignment: AlignmentDirectional.topStart,
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
                  itemCount: banks.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    title: Text(
                      banks[index],
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                    ),
                    onTap: () => onSelected(banks[index]),
                  ),
                ),
              ),
            ),
          );
        },
        onSelected: (_) => setState(branchController.clear),
      ),
    );
  }

  Widget _buildBranchAutocomplete() {
    final bank = _value('bankName');
    final bankId = _bankNames.contains(bank)
        ? _bankIdFromSelection(bank)
        : null;
    final branches = bankId == null
        ? const <_ClientBankBranch>[]
        : _branchesByBankId[bankId] ?? const <_ClientBankBranch>[];
    final isBankSelected = bankId != null;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _clearInvalidBranch();
      },
      child: Autocomplete<_ClientBankBranch>(
        key: ValueKey('client-branch-$bankId'),
        textEditingController: _controllers['bankBranch']!,
        focusNode: _branchFocusNode,
        displayStringForOption: (branch) => branch.label,
        optionsBuilder: (textEditingValue) {
          if (!isBankSelected || _isLoadingBankBranches) {
            return const Iterable<_ClientBankBranch>.empty();
          }
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty) return branches;
          return branches.where(
            (branch) => branch.label.toLowerCase().contains(query),
          );
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            enabled: isBankSelected && !_isLoadingBankBranches,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            validator: (value) {
              final branch = value?.trim() ?? '';
              if (branch.isEmpty ||
                  branches.any((item) => item.label == branch)) {
                return null;
              }
              return widget.strings.selectBranchFromList;
            },
            decoration: _bankInputDecoration(
              label: widget.strings.branch,
              icon: Icons.store_mall_directory_outlined,
              hintText: _isLoadingBankBranches
                  ? widget.strings.loadingBranches
                  : !isBankSelected
                  ? widget.strings.selectBankFirst
                  : branches.isEmpty
                  ? widget.strings.noBranchesFound
                  : null,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final branchOptions = options.toList();
          return Align(
            alignment: AlignmentDirectional.topStart,
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

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    final contactDetails = {
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final address = [
      _value('street'),
      _value('city'),
      _value('zipCode'),
      _value('country'),
    ].where((part) => part.isNotEmpty).join(', ');

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('clients')
          .doc(widget.clientId)
          .update({
            'contactDetails': contactDetails,
            'address': address,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.contactDetailsSaved),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.contactDetailsSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 42),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ContactFormSection(
                  icon: Icons.contact_mail_outlined,
                  title: widget.strings.contactDetails,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 680;
                      final addressFields = [
                        _ContactTextField(
                          controller: _controllers['street']!,
                          label: widget.strings.street,
                          icon: Icons.signpost_outlined,
                        ),
                        _ContactTextField(
                          controller: _controllers['city']!,
                          label: widget.strings.city,
                          icon: Icons.location_city_outlined,
                        ),
                        _ContactTextField(
                          controller: _controllers['zipCode']!,
                          label: widget.strings.zipCode,
                          icon: Icons.markunread_mailbox_outlined,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        _ContactTextField(
                          controller: _controllers['country']!,
                          label: widget.strings.country,
                          icon: Icons.public_outlined,
                        ),
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.strings.address,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (twoColumns)
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final field in addressFields)
                                  SizedBox(
                                    width: (constraints.maxWidth - 12) / 2,
                                    child: field,
                                  ),
                              ],
                            )
                          else
                            ...addressFields.expand(
                              (field) => [field, const SizedBox(height: 12)],
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _ContactFormSection(
                  icon: Icons.person_pin_outlined,
                  title: widget.strings.contactPerson,
                  child: Column(
                    children: [
                      _ContactTextField(
                        controller: _controllers['contactName']!,
                        label: widget.strings.contactName,
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['contactEmail']!,
                        label: widget.strings.contactEmail,
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['fax']!,
                        label: widget.strings.fax,
                        icon: Icons.fax_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ContactFormSection(
                  icon: Icons.account_balance_wallet_outlined,
                  title: widget.strings.accountingContact,
                  child: Column(
                    children: [
                      _ContactTextField(
                        controller: _controllers['accountingContactName']!,
                        label: widget.strings.accountingContactName,
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['accountingContactEmail']!,
                        label: widget.strings.accountingContactEmail,
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['accountingContactPhone']!,
                        label: widget.strings.accountingContactPhone,
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['customerContent']!,
                        label: widget.strings.customerContent,
                        icon: Icons.notes_outlined,
                        maxLines: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ContactFormSection(
                  icon: Icons.account_balance_outlined,
                  title: widget.strings.bankDetails,
                  child: Column(
                    children: [
                      _buildBankAutocomplete(),
                      const SizedBox(height: 12),
                      _buildBranchAutocomplete(),
                      if (_bankBranchesLoadFailed) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFB45309),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.strings.branchesLoadFailed,
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLoadingBankBranches = true;
                                  _bankBranchesLoadFailed = false;
                                });
                                _loadBankBranches();
                              },
                              child: Text(widget.strings.retry),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _ContactTextField(
                        controller: _controllers['bankAccountNumber']!,
                        label: widget.strings.bankAccountNumber,
                        icon: Icons.numbers_rounded,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
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
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _isSaving
                          ? widget.strings.saving
                          : widget.strings.saveContactDetails,
                    ),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactFormSection extends StatelessWidget {
  const _ContactFormSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(icon: icon, title: title),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ContactTextField extends StatelessWidget {
  const _ContactTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF1F5FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
        ),
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
    required this.contactDetails,
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
      contactDetails: _ClientContactDetails.fromData(
        data['contactDetails'],
        legacyAddress: (data['address'] ?? '').toString().trim(),
      ),
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
  final _ClientContactDetails contactDetails;

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

class _ClientContactDetails {
  const _ClientContactDetails({
    required this.street,
    required this.city,
    required this.zipCode,
    required this.country,
    required this.contactName,
    required this.contactEmail,
    required this.fax,
    required this.accountingContactName,
    required this.accountingContactEmail,
    required this.accountingContactPhone,
    required this.customerContent,
    required this.bankName,
    required this.bankBranch,
    required this.bankAccountNumber,
  });

  factory _ClientContactDetails.fromData(
    dynamic rawData, {
    required String legacyAddress,
  }) {
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : const <String, dynamic>{};
    String value(String key) => (data[key] ?? '').toString().trim();

    return _ClientContactDetails(
      street: value('street').isEmpty ? legacyAddress : value('street'),
      city: value('city'),
      zipCode: value('zipCode'),
      country: value('country'),
      contactName: value('contactName'),
      contactEmail: value('contactEmail'),
      fax: value('fax'),
      accountingContactName: value('accountingContactName'),
      accountingContactEmail: value('accountingContactEmail'),
      accountingContactPhone: value('accountingContactPhone'),
      customerContent: value('customerContent'),
      bankName: value('bankName'),
      bankBranch: value('bankBranch'),
      bankAccountNumber: value('bankAccountNumber'),
    );
  }

  Map<String, String> toMap() => {
    'street': street,
    'city': city,
    'zipCode': zipCode,
    'country': country,
    'contactName': contactName,
    'contactEmail': contactEmail,
    'fax': fax,
    'accountingContactName': accountingContactName,
    'accountingContactEmail': accountingContactEmail,
    'accountingContactPhone': accountingContactPhone,
    'customerContent': customerContent,
    'bankName': bankName,
    'bankBranch': bankBranch,
    'bankAccountNumber': bankAccountNumber,
  };

  final String street;
  final String city;
  final String zipCode;
  final String country;
  final String contactName;
  final String contactEmail;
  final String fax;
  final String accountingContactName;
  final String accountingContactEmail;
  final String accountingContactPhone;
  final String customerContent;
  final String bankName;
  final String bankBranch;
  final String bankAccountNumber;
}

class _ClientDetailsStrings {
  const _ClientDetailsStrings(this.values);

  factory _ClientDetailsStrings.forLocale(String locale) =>
      _ClientDetailsStrings(_translations[locale] ?? _translations['en']!);

  final Map<String, String> values;

  String _value(String key) => values[key] ?? _translations['en']![key]!;

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
  String get clientDetailsTab => _value('clientDetailsTab');
  String get street => _value('street');
  String get city => _value('city');
  String get zipCode => _value('zipCode');
  String get country => _value('country');
  String get contactPerson => _value('contactPerson');
  String get contactName => _value('contactName');
  String get contactEmail => _value('contactEmail');
  String get fax => _value('fax');
  String get accountingContact => _value('accountingContact');
  String get accountingContactName => _value('accountingContactName');
  String get accountingContactEmail => _value('accountingContactEmail');
  String get accountingContactPhone => _value('accountingContactPhone');
  String get customerContent => _value('customerContent');
  String get bankDetails => _value('bankDetails');
  String get bank => _value('bank');
  String get branch => _value('branch');
  String get bankAccountNumber => _value('bankAccountNumber');
  String get invalidEmail => _value('invalidEmail');
  String get saveContactDetails => _value('saveContactDetails');
  String get saving => _value('saving');
  String get contactDetailsSaved => _value('contactDetailsSaved');
  String get contactDetailsSaveFailed => _value('contactDetailsSaveFailed');
  String get selectBankFromList => _value('selectBankFromList');
  String get selectBranchFromList => _value('selectBranchFromList');
  String get selectBankFirst => _value('selectBankFirst');
  String get loadingBranches => _value('loadingBranches');
  String get noBranchesFound => _value('noBranchesFound');
  String get branchesLoadFailed => _value('branchesLoadFailed');
  String get retry => _value('retry');

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
      'clientDetailsTab': 'Client details',
      'street': 'Street',
      'city': 'City',
      'zipCode': 'Zip code',
      'country': 'Country',
      'contactPerson': 'Contact person',
      'contactName': 'Contact name',
      'contactEmail': 'Contact email',
      'fax': 'Fax',
      'accountingContact': 'Accounting contact',
      'accountingContactName': 'Accounting contact name',
      'accountingContactEmail': 'Accounting contact email',
      'accountingContactPhone': 'Accounting contact phone',
      'customerContent': 'Content for the customer',
      'bankDetails': 'Bank details',
      'bank': 'Bank',
      'branch': 'Branch',
      'bankAccountNumber': 'Account number',
      'invalidEmail': 'Enter a valid email address.',
      'saveContactDetails': 'Save contact details',
      'saving': 'Saving...',
      'contactDetailsSaved': 'Contact details saved.',
      'contactDetailsSaveFailed': 'Could not save the contact details.',
      'selectBankFromList': 'Select a bank from the list.',
      'selectBranchFromList': 'Select a branch from the list.',
      'selectBankFirst': 'Select a bank first',
      'loadingBranches': 'Loading branches...',
      'noBranchesFound': 'No branches found',
      'branchesLoadFailed': 'Could not load the branch list.',
      'retry': 'Retry',
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
      'clientDetailsTab': 'פרטי לקוח',
      'street': 'רחוב',
      'city': 'עיר',
      'zipCode': 'מיקוד',
      'country': 'מדינה',
      'contactPerson': 'איש קשר',
      'contactName': 'שם איש הקשר',
      'contactEmail': 'מייל איש הקשר',
      'fax': 'פקס',
      'accountingContact': 'איש קשר בהנהלת חשבונות',
      'accountingContactName': 'שם איש הקשר בהנה״ח',
      'accountingContactEmail': 'מייל איש הקשר בהנה״ח',
      'accountingContactPhone': 'טלפון איש הקשר בהנה״ח',
      'customerContent': 'תוכן עבור הלקוח',
      'bankDetails': 'פרטי חשבון בנק',
      'bank': 'בנק',
      'branch': 'סניף',
      'bankAccountNumber': 'מספר חשבון',
      'invalidEmail': 'יש להזין כתובת אימייל תקינה.',
      'saveContactDetails': 'שמור פרטי קשר',
      'saving': 'שומר...',
      'contactDetailsSaved': 'פרטי הקשר נשמרו.',
      'contactDetailsSaveFailed': 'לא ניתן לשמור את פרטי הקשר.',
      'selectBankFromList': 'יש לבחור בנק מהרשימה.',
      'selectBranchFromList': 'יש לבחור סניף מהרשימה.',
      'selectBankFirst': 'יש לבחור בנק תחילה',
      'loadingBranches': 'טוען סניפים...',
      'noBranchesFound': 'לא נמצאו סניפים',
      'branchesLoadFailed': 'לא ניתן לטעון את רשימת הסניפים.',
      'retry': 'נסה שוב',
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
      'clientDetailsTab': 'تفاصيل العميل',
      'street': 'الشارع',
      'city': 'المدينة',
      'zipCode': 'الرمز البريدي',
      'country': 'الدولة',
      'contactPerson': 'جهة الاتصال',
      'contactName': 'اسم جهة الاتصال',
      'contactEmail': 'بريد جهة الاتصال',
      'fax': 'فاكس',
      'accountingContact': 'جهة اتصال المحاسبة',
      'accountingContactName': 'اسم جهة اتصال المحاسبة',
      'accountingContactEmail': 'بريد جهة اتصال المحاسبة',
      'accountingContactPhone': 'هاتف جهة اتصال المحاسبة',
      'customerContent': 'محتوى للعميل',
      'bankDetails': 'تفاصيل الحساب البنكي',
      'bank': 'البنك',
      'branch': 'الفرع',
      'bankAccountNumber': 'رقم الحساب',
      'invalidEmail': 'أدخل عنوان بريد إلكتروني صالحًا.',
      'saveContactDetails': 'حفظ بيانات الاتصال',
      'saving': 'جارٍ الحفظ...',
      'contactDetailsSaved': 'تم حفظ بيانات الاتصال.',
      'contactDetailsSaveFailed': 'تعذر حفظ بيانات الاتصال.',
      'selectBankFromList': 'اختر بنكًا من القائمة.',
      'selectBranchFromList': 'اختر فرعًا من القائمة.',
      'selectBankFirst': 'اختر بنكًا أولًا',
      'loadingBranches': 'جارٍ تحميل الفروع...',
      'noBranchesFound': 'لم يتم العثور على فروع',
      'branchesLoadFailed': 'تعذر تحميل قائمة الفروع.',
      'retry': 'إعادة المحاولة',
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
      'clientDetailsTab': 'Данные клиента',
      'street': 'Улица',
      'city': 'Город',
      'zipCode': 'Почтовый индекс',
      'country': 'Страна',
      'contactPerson': 'Контактное лицо',
      'contactName': 'Имя контактного лица',
      'contactEmail': 'Email контактного лица',
      'fax': 'Факс',
      'accountingContact': 'Контакт бухгалтерии',
      'accountingContactName': 'Имя контакта бухгалтерии',
      'accountingContactEmail': 'Email контакта бухгалтерии',
      'accountingContactPhone': 'Телефон контакта бухгалтерии',
      'customerContent': 'Содержание для клиента',
      'bankDetails': 'Банковские реквизиты',
      'bank': 'Банк',
      'branch': 'Отделение',
      'bankAccountNumber': 'Номер счета',
      'invalidEmail': 'Введите действительный адрес электронной почты.',
      'saveContactDetails': 'Сохранить контактные данные',
      'saving': 'Сохранение...',
      'contactDetailsSaved': 'Контактные данные сохранены.',
      'contactDetailsSaveFailed': 'Не удалось сохранить контактные данные.',
      'selectBankFromList': 'Выберите банк из списка.',
      'selectBranchFromList': 'Выберите отделение из списка.',
      'selectBankFirst': 'Сначала выберите банк',
      'loadingBranches': 'Загрузка отделений...',
      'noBranchesFound': 'Отделения не найдены',
      'branchesLoadFailed': 'Не удалось загрузить список отделений.',
      'retry': 'Повторить',
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
      'clientDetailsTab': 'የደንበኛ ዝርዝሮች',
      'street': 'መንገድ',
      'city': 'ከተማ',
      'zipCode': 'የፖስታ ኮድ',
      'country': 'አገር',
      'contactPerson': 'የእውቂያ ሰው',
      'contactName': 'የእውቂያ ሰው ስም',
      'contactEmail': 'የእውቂያ ኢሜይል',
      'fax': 'ፋክስ',
      'accountingContact': 'የሂሳብ እውቂያ',
      'accountingContactName': 'የሂሳብ እውቂያ ስም',
      'accountingContactEmail': 'የሂሳብ እውቂያ ኢሜይል',
      'accountingContactPhone': 'የሂሳብ እውቂያ ስልክ',
      'customerContent': 'ለደንበኛው ይዘት',
      'bankDetails': 'የባንክ ዝርዝሮች',
      'bank': 'ባንክ',
      'branch': 'ቅርንጫፍ',
      'bankAccountNumber': 'የሂሳብ ቁጥር',
      'invalidEmail': 'ትክክለኛ የኢሜይል አድራሻ ያስገቡ።',
      'saveContactDetails': 'የመገናኛ መረጃ አስቀምጥ',
      'saving': 'በማስቀመጥ ላይ...',
      'contactDetailsSaved': 'የመገናኛ መረጃ ተቀምጧል።',
      'contactDetailsSaveFailed': 'የመገናኛ መረጃን ማስቀመጥ አልተቻለም።',
      'selectBankFromList': 'ከዝርዝሩ ባንክ ይምረጡ።',
      'selectBranchFromList': 'ከዝርዝሩ ቅርንጫፍ ይምረጡ።',
      'selectBankFirst': 'መጀመሪያ ባንክ ይምረጡ',
      'loadingBranches': 'ቅርንጫፎችን በመጫን ላይ...',
      'noBranchesFound': 'ምንም ቅርንጫፍ አልተገኘም',
      'branchesLoadFailed': 'የቅርንጫፎችን ዝርዝር መጫን አልተቻለም።',
      'retry': 'እንደገና ሞክር',
    },
  };
}
