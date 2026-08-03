import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/client_details_page.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:untitled1/services/client_service.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/utils/israeli_id_validator.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  static const Color _primary = Color(0xFF1976D2);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);

  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isOpeningDocument = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  CollectionReference<Map<String, dynamic>>? get _clientsCollection {
    final user = _user;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('clients');
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) return;
    setState(() => _searchQuery = query);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _showClientEditor(
    _ClientStrings strings, {
    _ClientRecord? client,
  }) async {
    final collection = _clientsCollection;
    if (collection == null) return;

    final nameController = TextEditingController(text: client?.name ?? '');
    final externalClientNumberController = TextEditingController(
      text: client?.externalClientNumber.isNotEmpty == true
          ? client!.externalClientNumber
          : ClientService.generateExternalClientNumber(),
    );
    final taxIdController = TextEditingController(text: client?.taxId ?? '');
    final phoneControllers = (client?.phones ?? const <String>[''])
        .map((phone) => TextEditingController(text: phone))
        .toList();
    final emailControllers = (client?.emails ?? const <String>[''])
        .map((email) => TextEditingController(text: email))
        .toList();
    final addressController = TextEditingController(
      text: client?.address ?? '',
    );
    final notesController = TextEditingController(text: client?.notes ?? '');
    final formKey = GlobalKey<FormState>();
    final ownedControllers = <TextEditingController>[
      nameController,
      externalClientNumberController,
      taxIdController,
      ...phoneControllers,
      ...emailControllers,
      addressController,
      notesController,
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var isSaving = false;
        return _ClientEditorControllerOwner(
          controllers: ownedControllers,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> save() async {
                if (isSaving || !(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                setSheetState(() => isSaving = true);
                try {
                  final name = nameController.text.trim();
                  final phones = phoneControllers
                      .map((controller) => controller.text.trim())
                      .where((phone) => phone.isNotEmpty)
                      .toList();
                  final emails = emailControllers
                      .map((controller) => controller.text.trim())
                      .where((email) => email.isNotEmpty)
                      .toList();
                  final data = <String, dynamic>{
                    'name': name,
                    'nameLowercase': name.toLowerCase(),
                    'taxId': taxIdController.text.trim(),
                    'phone': phones.isEmpty ? '' : phones.first,
                    'phones': phones,
                    'email': emails.isEmpty ? '' : emails.first,
                    'emails': emails,
                    'address': addressController.text.trim(),
                    'notes': notesController.text.trim(),
                  };
                  await ClientService.saveClient(
                    userId: _user!.uid,
                    clientData: data,
                    externalClientNumber: externalClientNumberController.text,
                    clientId: client?.id,
                  );

                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        client == null
                            ? strings.clientAdded
                            : strings.clientUpdated,
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } on ClientNumberConflictException {
                  if (!sheetContext.mounted) return;
                  setSheetState(() => isSaving = false);
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text(strings.clientNumberDuplicate)),
                  );
                } catch (_) {
                  if (!sheetContext.mounted) return;
                  setSheetState(() => isSaving = false);
                  ScaffoldMessenger.of(
                    sheetContext,
                  ).showSnackBar(SnackBar(content: Text(strings.saveFailed)));
                }
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF4FF),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: _primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      client == null
                                          ? strings.addClient
                                          : strings.editClient,
                                      style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: _ink,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      strings.formHint,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: strings.close,
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          _ClientTextField(
                            controller: nameController,
                            label: strings.name,
                            icon: Icons.person_outline_rounded,
                            required: true,
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? strings.nameRequired
                                : null,
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(phoneControllers.length, (index) {
                            final isPrimary = index == 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ClientTextField(
                                controller: phoneControllers[index],
                                label: isPrimary
                                    ? strings.primaryPhone
                                    : '${strings.phone} ${index + 1}',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                helperText: isPrimary
                                    ? strings.primaryContactHint
                                    : null,
                                suffixIcon: IconButton(
                                  tooltip: isPrimary
                                      ? strings.addPhone
                                      : strings.removeField,
                                  onPressed: () {
                                    if (isPrimary) {
                                      final controller =
                                          TextEditingController();
                                      setSheetState(() {
                                        phoneControllers.add(controller);
                                        ownedControllers.add(controller);
                                      });
                                    } else {
                                      setSheetState(
                                        () => phoneControllers.removeAt(index),
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    isPrimary
                                        ? Icons.add_rounded
                                        : Icons.remove_circle_outline_rounded,
                                  ),
                                ),
                              ),
                            );
                          }),
                          ...List.generate(emailControllers.length, (index) {
                            final isPrimary = index == 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ClientTextField(
                                controller: emailControllers[index],
                                label: isPrimary
                                    ? strings.primaryEmail
                                    : '${strings.email} ${index + 1}',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                helperText: isPrimary
                                    ? strings.primaryContactHint
                                    : null,
                                suffixIcon: IconButton(
                                  tooltip: isPrimary
                                      ? strings.addEmail
                                      : strings.removeField,
                                  onPressed: () {
                                    if (isPrimary) {
                                      final controller =
                                          TextEditingController();
                                      setSheetState(() {
                                        emailControllers.add(controller);
                                        ownedControllers.add(controller);
                                      });
                                    } else {
                                      setSheetState(
                                        () => emailControllers.removeAt(index),
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    isPrimary
                                        ? Icons.add_rounded
                                        : Icons.remove_circle_outline_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) return null;
                                  return RegExp(
                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                      ).hasMatch(email)
                                      ? null
                                      : strings.invalidEmail;
                                },
                              ),
                            );
                          }),
                          _ClientTextField(
                            controller: taxIdController,
                            label: strings.taxId,
                            icon: Icons.badge_outlined,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            validator: (value) {
                              final id = value?.trim() ?? '';
                              if (id.isEmpty) return null;
                              if (id.length != 9) {
                                return strings.taxIdInvalidLength;
                              }
                              return isValidIsraeliId(id)
                                  ? null
                                  : strings.taxIdInvalid;
                            },
                          ),
                          const SizedBox(height: 12),
                          _ClientTextField(
                            controller: addressController,
                            label: strings.address,
                            icon: Icons.location_on_outlined,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _ClientTextField(
                            controller: notesController,
                            label: strings.notes,
                            icon: Icons.notes_rounded,
                            maxLines: 3,
                            textInputAction: TextInputAction.newline,
                          ),
                          const SizedBox(height: 12),
                          _ClientTextField(
                            controller: externalClientNumberController,
                            label: strings.externalClientNumber,
                            icon: Icons.tag_rounded,
                            required: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            helperText: strings.externalClientNumberHint,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            validator: (value) =>
                                ClientService.isValidExternalClientNumber(
                                  value ?? '',
                                )
                                ? null
                                : strings.externalClientNumberInvalid,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: isSaving ? null : save,
                              icon: isSaving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(
                                isSaving ? strings.saving : strings.saveClient,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _primary.withValues(
                                  alpha: 0.6,
                                ),
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
            },
          ),
        );
      },
    );
  }

  Future<void> _deleteClient(
    _ClientRecord client,
    _ClientStrings strings,
  ) async {
    final collection = _clientsCollection;
    if (collection == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFDC2626),
          size: 30,
        ),
        title: Text(strings.deleteClient),
        content: Text(strings.deleteConfirmation(client.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ClientService.deleteClient(userId: _user!.uid, clientId: client.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.clientDeleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.deleteFailed)));
    }
  }

  Future<void> _openClientDetails(
    _ClientRecord client,
    _ClientStrings strings,
  ) async {
    final action = await Navigator.push<ClientDetailsAction>(
      context,
      MaterialPageRoute(builder: (_) => ClientDetailsPage(clientId: client.id)),
    );
    if (!mounted || action != ClientDetailsAction.edit) return;
    await _showClientEditor(strings, client: client);
  }

  Future<void> _createDocument(
    _ClientRecord client,
    _ClientStrings strings,
  ) async {
    final user = _user;
    if (user == null || _isOpeningDocument) return;

    setState(() => _isOpeningDocument = true);
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

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isBusinessVerified
              ? InvoiceBuilderPage(
                  workerName: workerName.isEmpty ? 'Worker' : workerName,
                  workerPhone: workerPhone.isEmpty ? null : workerPhone,
                  workerEmail: workerEmail.isEmpty ? null : workerEmail,
                  initialDocType: 'quote',
                  initialSavedClientId: client.id,
                  initialClientTaxId: client.taxId,
                  receiverName: client.name,
                  receiverPhone: client.phone,
                  receiverEmail: client.email,
                  receiverAddress: client.address,
                )
              : const VerifyBusinessPage(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.createDocumentFailed)));
    } finally {
      if (mounted) setState(() => _isOpeningDocument = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LanguageProvider>().locale.languageCode;
    final strings = _ClientStrings.forLocale(locale);
    final collection = _clientsCollection;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          strings.title,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: collection == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showClientEditor(strings),
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                strings.addClient,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      body: collection == null
          ? _MessageState(
              icon: Icons.lock_outline_rounded,
              title: strings.loginRequired,
              message: strings.loginMessage,
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: collection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _MessageState(
                    icon: Icons.cloud_off_rounded,
                    title: strings.loadFailed,
                    message: strings.tryAgain,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allClients =
                    snapshot.data!.docs.map(_ClientRecord.fromDocument).toList()
                      ..sort(
                        (a, b) => a.name.toLowerCase().compareTo(
                          b.name.toLowerCase(),
                        ),
                      );
                final clients = allClients.where((client) {
                  if (_searchQuery.isEmpty) return true;
                  return client.searchText.contains(_searchQuery);
                }).toList();

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                            child: _ClientsHeader(
                              strings: strings,
                              controller: _searchController,
                              clientCount: allClients.length,
                              onClear: _searchController.clear,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (allClients.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyClientsState(
                          strings: strings,
                          onAdd: () => _showClientEditor(strings),
                        ),
                      )
                    else if (clients.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _MessageState(
                          icon: Icons.search_off_rounded,
                          title: strings.noResults,
                          message: strings.noResultsMessage,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent >= 760
                                ? 2
                                : 1;
                            return SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    mainAxisExtent: 250,
                                  ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _ClientCard(
                                  client: clients[index],
                                  strings: strings,
                                  onOpen: () => _openClientDetails(
                                    clients[index],
                                    strings,
                                  ),
                                  onCreateDocument: () =>
                                      _createDocument(clients[index], strings),
                                  onEdit: () => _showClientEditor(
                                    strings,
                                    client: clients[index],
                                  ),
                                  onDelete: () =>
                                      _deleteClient(clients[index], strings),
                                ),
                                childCount: clients.length,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _ClientsHeader extends StatelessWidget {
  const _ClientsHeader({
    required this.strings,
    required this.controller,
    required this.clientCount,
    required this.onClear,
  });

  final _ClientStrings strings;
  final TextEditingController controller;
  final int clientCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.manageClients,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.clientCount(clientCount),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: strings.search,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.clearSearch,
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.strings,
    required this.onOpen,
    required this.onCreateDocument,
    required this.onEdit,
    required this.onDelete,
  });

  final _ClientRecord client;
  final _ClientStrings strings;
  final VoidCallback onOpen;
  final VoidCallback onCreateDocument;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFFEAF4FF),
                    child: Text(
                      client.initial,
                      style: const TextStyle(
                        color: Color(0xFF1976D2),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (client.externalClientNumber.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${strings.externalClientNumberShort}: ${client.externalClientNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1976D2),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else if (client.taxId.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${strings.taxIdShort}: ${client.taxId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<_ClientAction>(
                    tooltip: strings.moreActions,
                    onSelected: (action) {
                      if (action == _ClientAction.edit) {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _ClientAction.edit,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(strings.edit),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ClientAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFDC2626),
                          ),
                          title: Text(
                            strings.delete,
                            style: const TextStyle(color: Color(0xFFDC2626)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 15),
              if (client.phone.isNotEmpty)
                _ClientDetailLine(
                  icon: Icons.phone_outlined,
                  text: client.phone,
                ),
              if (client.email.isNotEmpty)
                _ClientDetailLine(
                  icon: Icons.email_outlined,
                  text: client.email,
                ),
              if (client.address.isNotEmpty)
                _ClientDetailLine(
                  icon: Icons.location_on_outlined,
                  text: client.address,
                ),
              if (!client.hasContactDetails)
                _ClientDetailLine(
                  icon: Icons.info_outline_rounded,
                  text: strings.noContactDetails,
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCreateDocument,
                  icon: const Icon(Icons.note_add_outlined, size: 19),
                  label: Text(strings.createDocument),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF4FF),
                    foregroundColor: const Color(0xFF1976D2),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientDetailLine extends StatelessWidget {
  const _ClientDetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF64748B)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyClientsState extends StatelessWidget {
  const _EmptyClientsState({required this.strings, required this.onAdd});

  final _ClientStrings strings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF4FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Color(0xFF1976D2),
                size: 48,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              strings.noClients,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.noClientsMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), height: 1.45),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.addFirstClient),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
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
            Icon(icon, size: 54, color: const Color(0xFF94A3B8)),
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

class _ClientEditorControllerOwner extends StatefulWidget {
  const _ClientEditorControllerOwner({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_ClientEditorControllerOwner> createState() =>
      _ClientEditorControllerOwnerState();
}

class _ClientEditorControllerOwnerState
    extends State<_ClientEditorControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ClientTextField extends StatelessWidget {
  const _ClientTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.required = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.maxLines = 1,
    this.helperText,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool required;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final int maxLines;
  final String? helperText;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        helperText: helperText,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
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
      ),
    );
  }
}

enum _ClientAction { edit, delete }

List<String> _clientContactValues(dynamic rawValues, String fallback) {
  final values = rawValues is List
      ? rawValues
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList()
      : <String>[];
  if (values.isNotEmpty) return values;
  return [fallback.trim()];
}

class _ClientRecord {
  const _ClientRecord({
    required this.id,
    required this.name,
    required this.externalClientNumber,
    required this.taxId,
    required this.phone,
    required this.phones,
    required this.email,
    required this.emails,
    required this.address,
    required this.notes,
  });

  factory _ClientRecord.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    return _ClientRecord(
      id: document.id,
      name: (data['name'] ?? '').toString().trim(),
      externalClientNumber: (data['externalClientNumber'] ?? '')
          .toString()
          .trim(),
      taxId: (data['taxId'] ?? '').toString().trim(),
      phone: phone,
      phones: _clientContactValues(data['phones'], phone),
      email: email,
      emails: _clientContactValues(data['emails'], email),
      address: (data['address'] ?? '').toString().trim(),
      notes: (data['notes'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String name;
  final String externalClientNumber;
  final String taxId;
  final String phone;
  final List<String> phones;
  final String email;
  final List<String> emails;
  final String address;
  final String notes;

  String get initial {
    final trimmedName = name.trim();
    return trimmedName.isEmpty
        ? '?'
        : trimmedName.characters.first.toUpperCase();
  }

  bool get hasContactDetails =>
      phone.isNotEmpty || email.isNotEmpty || address.isNotEmpty;

  String get searchText =>
      '$name $externalClientNumber $taxId ${phones.join(' ')} ${emails.join(' ')} $address $notes'
          .toLowerCase();
}

class _ClientStrings {
  const _ClientStrings(this.values);

  factory _ClientStrings.forLocale(String locale) {
    return _ClientStrings(_translations[locale] ?? _translations['en']!);
  }

  final Map<String, String> values;

  String get title => values['title']!;
  String get manageClients => values['manageClients']!;
  String get search => values['search']!;
  String get clearSearch => values['clearSearch']!;
  String get addClient => values['addClient']!;
  String get editClient => values['editClient']!;
  String get formHint => values['formHint']!;
  String get name => values['name']!;
  String get phone => values['phone']!;
  String get primaryPhone => values['primaryPhone']!;
  String get email => values['email']!;
  String get primaryEmail => values['primaryEmail']!;
  String get primaryContactHint => values['primaryContactHint']!;
  String get addPhone => values['addPhone']!;
  String get addEmail => values['addEmail']!;
  String get removeField => values['removeField']!;
  String get taxId => values['taxId']!;
  String get taxIdShort => values['taxIdShort']!;
  String get taxIdInvalidLength => values['taxIdInvalidLength']!;
  String get taxIdInvalid => values['taxIdInvalid']!;
  String get externalClientNumber => values['externalClientNumber']!;
  String get externalClientNumberShort => values['externalClientNumberShort']!;
  String get externalClientNumberHint => values['externalClientNumberHint']!;
  String get externalClientNumberInvalid =>
      values['externalClientNumberInvalid']!;
  String get clientNumberDuplicate => values['clientNumberDuplicate']!;
  String get address => values['address']!;
  String get notes => values['notes']!;
  String get close => values['close']!;
  String get saveClient => values['saveClient']!;
  String get saving => values['saving']!;
  String get nameRequired => values['nameRequired']!;
  String get invalidEmail => values['invalidEmail']!;
  String get clientAdded => values['clientAdded']!;
  String get clientUpdated => values['clientUpdated']!;
  String get saveFailed => values['saveFailed']!;
  String get deleteClient => values['deleteClient']!;
  String get cancel => values['cancel']!;
  String get delete => values['delete']!;
  String get edit => values['edit']!;
  String get clientDeleted => values['clientDeleted']!;
  String get deleteFailed => values['deleteFailed']!;
  String get moreActions => values['moreActions']!;
  String get noContactDetails => values['noContactDetails']!;
  String get createDocument => values['createDocument']!;
  String get createDocumentFailed => values['createDocumentFailed']!;
  String get noClients => values['noClients']!;
  String get noClientsMessage => values['noClientsMessage']!;
  String get addFirstClient => values['addFirstClient']!;
  String get noResults => values['noResults']!;
  String get noResultsMessage => values['noResultsMessage']!;
  String get loginRequired => values['loginRequired']!;
  String get loginMessage => values['loginMessage']!;
  String get loadFailed => values['loadFailed']!;
  String get tryAgain => values['tryAgain']!;

  String clientCount(int count) =>
      values['clientCount']!.replaceAll('{count}', count.toString());

  String deleteConfirmation(String name) =>
      values['deleteConfirmation']!.replaceAll('{name}', name);

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Clients',
      'manageClients': 'Your clients',
      'clientCount': '{count} clients saved',
      'search': 'Search by name, phone, or email',
      'clearSearch': 'Clear search',
      'addClient': 'Add client',
      'editClient': 'Edit client',
      'formHint': 'Keep client details ready for your business documents.',
      'name': 'Client name',
      'phone': 'Phone number',
      'primaryPhone': 'Primary phone number',
      'email': 'Email address',
      'primaryEmail': 'Primary email address',
      'primaryContactHint': 'Used automatically in new documents',
      'addPhone': 'Add another phone number',
      'addEmail': 'Add another email address',
      'removeField': 'Remove',
      'taxId': 'Business No. / ID / Tax ID',
      'taxIdShort': 'ID',
      'taxIdInvalidLength': 'Client ID must be exactly 9 digits.',
      'taxIdInvalid': 'Enter a valid Israeli ID number.',
      'externalClientNumber': 'Client number in external accountancy',
      'externalClientNumberShort': 'Accountancy No.',
      'externalClientNumberHint': '1–10 digits',
      'externalClientNumberInvalid':
          'Enter 1–10 digits. This field is required.',
      'clientNumberDuplicate':
          'This client number is already used by another client.',
      'generateClientNumber': 'Generate a new client number',
      'address': 'Address',
      'notes': 'Notes',
      'close': 'Close',
      'saveClient': 'Save client',
      'saving': 'Saving...',
      'nameRequired': 'Please enter the client name.',
      'invalidEmail': 'Please enter a valid email address.',
      'clientAdded': 'Client added successfully.',
      'clientUpdated': 'Client updated successfully.',
      'saveFailed': 'Could not save the client. Please try again.',
      'deleteClient': 'Delete client?',
      'deleteConfirmation': 'Remove {name} from your clients?',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'clientDeleted': 'Client deleted.',
      'deleteFailed': 'Could not delete the client.',
      'moreActions': 'More actions',
      'noContactDetails': 'No contact details added',
      'createDocument': 'Create document',
      'createDocumentFailed': 'Could not open the document builder.',
      'noClients': 'No clients yet',
      'noClientsMessage':
          'Add your clients once, then keep their contact and billing details organized in one place.',
      'addFirstClient': 'Add your first client',
      'noResults': 'No matching clients',
      'noResultsMessage': 'Try a different name, phone number, or email.',
      'loginRequired': 'Sign in required',
      'loginMessage': 'Sign in to view and manage your clients.',
      'loadFailed': 'Could not load clients',
      'tryAgain': 'Check your connection and try again.',
    },
    'he': {
      'title': 'לקוחות',
      'manageClients': 'הלקוחות שלך',
      'clientCount': '{count} לקוחות שמורים',
      'search': 'חיפוש לפי שם, טלפון או אימייל',
      'clearSearch': 'נקה חיפוש',
      'addClient': 'הוסף לקוח',
      'editClient': 'ערוך לקוח',
      'formHint': 'שמור את פרטי הלקוח מוכנים למסמכי העסק שלך.',
      'name': 'שם הלקוח',
      'phone': 'מספר טלפון',
      'primaryPhone': 'מספר טלפון ראשי',
      'email': 'כתובת אימייל',
      'primaryEmail': 'כתובת אימייל ראשית',
      'primaryContactHint': 'ישמש אוטומטית במסמכים חדשים',
      'addPhone': 'הוסף מספר טלפון נוסף',
      'addEmail': 'הוסף כתובת אימייל נוספת',
      'removeField': 'הסר',
      'taxId': 'מס׳ עוסק / ת.ז. / ח.פ.',
      'taxIdShort': 'מזהה',
      'taxIdInvalidLength': 'מספר הזיהוי חייב להכיל בדיוק 9 ספרות.',
      'taxIdInvalid': 'יש להזין מספר זיהוי ישראלי תקין.',
      'externalClientNumber': 'מס׳ לקוח בהנה״ח חיצונית',
      'externalClientNumberShort': 'מס׳ הנה״ח',
      'externalClientNumberHint': '1–10 ספרות',
      'externalClientNumberInvalid': 'יש להזין 1–10 ספרות. שדה זה הוא חובה.',
      'clientNumberDuplicate': 'מספר לקוח זה כבר משויך ללקוח אחר.',
      'generateClientNumber': 'צור מספר לקוח חדש',
      'address': 'כתובת',
      'notes': 'הערות',
      'close': 'סגור',
      'saveClient': 'שמור לקוח',
      'saving': 'שומר...',
      'nameRequired': 'יש להזין את שם הלקוח.',
      'invalidEmail': 'יש להזין כתובת אימייל תקינה.',
      'clientAdded': 'הלקוח נוסף בהצלחה.',
      'clientUpdated': 'פרטי הלקוח עודכנו.',
      'saveFailed': 'לא ניתן לשמור את הלקוח. נסה שוב.',
      'deleteClient': 'למחוק את הלקוח?',
      'deleteConfirmation': 'להסיר את {name} מרשימת הלקוחות?',
      'cancel': 'ביטול',
      'delete': 'מחק',
      'edit': 'ערוך',
      'clientDeleted': 'הלקוח נמחק.',
      'deleteFailed': 'לא ניתן למחוק את הלקוח.',
      'moreActions': 'פעולות נוספות',
      'noContactDetails': 'לא נוספו פרטי קשר',
      'createDocument': 'יצירת מסמך',
      'createDocumentFailed': 'לא ניתן לפתוח את יוצר המסמכים.',
      'noClients': 'עדיין אין לקוחות',
      'noClientsMessage':
          'הוסף לקוחות פעם אחת ושמור את פרטי הקשר והחיוב שלהם מסודרים במקום אחד.',
      'addFirstClient': 'הוסף לקוח ראשון',
      'noResults': 'לא נמצאו לקוחות',
      'noResultsMessage': 'נסה שם, מספר טלפון או אימייל אחר.',
      'loginRequired': 'נדרשת התחברות',
      'loginMessage': 'יש להתחבר כדי לצפות ולנהל לקוחות.',
      'loadFailed': 'לא ניתן לטעון לקוחות',
      'tryAgain': 'בדוק את החיבור ונסה שוב.',
    },
    'ar': {
      'title': 'العملاء',
      'manageClients': 'عملاؤك',
      'clientCount': 'تم حفظ {count} عملاء',
      'search': 'ابحث بالاسم أو الهاتف أو البريد',
      'clearSearch': 'مسح البحث',
      'addClient': 'إضافة عميل',
      'editClient': 'تعديل العميل',
      'formHint': 'احتفظ ببيانات العميل جاهزة لمستندات عملك.',
      'name': 'اسم العميل',
      'phone': 'رقم الهاتف',
      'primaryPhone': 'رقم الهاتف الرئيسي',
      'email': 'البريد الإلكتروني',
      'primaryEmail': 'البريد الإلكتروني الرئيسي',
      'primaryContactHint': 'يُستخدم تلقائيًا في المستندات الجديدة',
      'addPhone': 'إضافة رقم هاتف آخر',
      'addEmail': 'إضافة بريد إلكتروني آخر',
      'removeField': 'إزالة',
      'taxId': 'رقم النشاط / الهوية / الضريبة',
      'taxIdShort': 'المعرّف',
      'taxIdInvalidLength': 'يجب أن يتكون رقم الهوية من 9 أرقام بالضبط.',
      'taxIdInvalid': 'أدخل رقم هوية إسرائيليًا صالحًا.',
      'externalClientNumber': 'رقم العميل في المحاسبة الخارجية',
      'externalClientNumberShort': 'رقم المحاسبة',
      'externalClientNumberHint': 'من 1 إلى 10 أرقام',
      'externalClientNumberInvalid': 'أدخل من 1 إلى 10 أرقام. هذا الحقل مطلوب.',
      'clientNumberDuplicate': 'رقم العميل مستخدم بالفعل لعميل آخر.',
      'generateClientNumber': 'إنشاء رقم عميل جديد',
      'address': 'العنوان',
      'notes': 'ملاحظات',
      'close': 'إغلاق',
      'saveClient': 'حفظ العميل',
      'saving': 'جارٍ الحفظ...',
      'nameRequired': 'يرجى إدخال اسم العميل.',
      'invalidEmail': 'يرجى إدخال بريد إلكتروني صحيح.',
      'clientAdded': 'تمت إضافة العميل بنجاح.',
      'clientUpdated': 'تم تحديث بيانات العميل.',
      'saveFailed': 'تعذر حفظ العميل. حاول مرة أخرى.',
      'deleteClient': 'حذف العميل؟',
      'deleteConfirmation': 'إزالة {name} من قائمة العملاء؟',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'edit': 'تعديل',
      'clientDeleted': 'تم حذف العميل.',
      'deleteFailed': 'تعذر حذف العميل.',
      'moreActions': 'المزيد من الإجراءات',
      'noContactDetails': 'لم تتم إضافة بيانات اتصال',
      'createDocument': 'إنشاء مستند',
      'createDocumentFailed': 'تعذر فتح منشئ المستندات.',
      'noClients': 'لا يوجد عملاء بعد',
      'noClientsMessage':
          'أضف عملاءك مرة واحدة واحتفظ ببيانات الاتصال والفوترة منظمة في مكان واحد.',
      'addFirstClient': 'أضف أول عميل',
      'noResults': 'لا يوجد عملاء مطابقون',
      'noResultsMessage': 'جرّب اسمًا أو رقم هاتف أو بريدًا آخر.',
      'loginRequired': 'تسجيل الدخول مطلوب',
      'loginMessage': 'سجّل الدخول لعرض عملائك وإدارتهم.',
      'loadFailed': 'تعذر تحميل العملاء',
      'tryAgain': 'تحقق من الاتصال وحاول مرة أخرى.',
    },
    'ru': {
      'title': 'Клиенты',
      'manageClients': 'Ваши клиенты',
      'clientCount': 'Сохранено клиентов: {count}',
      'search': 'Поиск по имени, телефону или email',
      'clearSearch': 'Очистить поиск',
      'addClient': 'Добавить клиента',
      'editClient': 'Изменить клиента',
      'formHint': 'Храните данные клиентов для деловых документов.',
      'name': 'Имя клиента',
      'phone': 'Телефон',
      'primaryPhone': 'Основной телефон',
      'email': 'Email',
      'primaryEmail': 'Основной email',
      'primaryContactHint': 'Автоматически используется в новых документах',
      'addPhone': 'Добавить другой телефон',
      'addEmail': 'Добавить другой email',
      'removeField': 'Удалить',
      'taxId': 'Рег. номер / ID / налоговый номер',
      'taxIdShort': 'ID',
      'taxIdInvalidLength': 'ID клиента должен содержать ровно 9 цифр.',
      'taxIdInvalid': 'Введите действительный израильский ID.',
      'externalClientNumber': 'Номер клиента во внешней бухгалтерии',
      'externalClientNumberShort': 'Бух. №',
      'externalClientNumberHint': 'От 1 до 10 цифр',
      'externalClientNumberInvalid':
          'Введите от 1 до 10 цифр. Поле обязательно.',
      'clientNumberDuplicate': 'Этот номер уже используется другим клиентом.',
      'generateClientNumber': 'Создать новый номер клиента',
      'address': 'Адрес',
      'notes': 'Заметки',
      'close': 'Закрыть',
      'saveClient': 'Сохранить',
      'saving': 'Сохранение...',
      'nameRequired': 'Введите имя клиента.',
      'invalidEmail': 'Введите действительный email.',
      'clientAdded': 'Клиент добавлен.',
      'clientUpdated': 'Данные клиента обновлены.',
      'saveFailed': 'Не удалось сохранить клиента.',
      'deleteClient': 'Удалить клиента?',
      'deleteConfirmation': 'Удалить {name} из списка клиентов?',
      'cancel': 'Отмена',
      'delete': 'Удалить',
      'edit': 'Изменить',
      'clientDeleted': 'Клиент удален.',
      'deleteFailed': 'Не удалось удалить клиента.',
      'moreActions': 'Другие действия',
      'noContactDetails': 'Контактные данные не добавлены',
      'createDocument': 'Создать документ',
      'createDocumentFailed': 'Не удалось открыть конструктор документов.',
      'noClients': 'Клиентов пока нет',
      'noClientsMessage':
          'Храните контакты и платежные данные клиентов в одном месте.',
      'addFirstClient': 'Добавить первого клиента',
      'noResults': 'Клиенты не найдены',
      'noResultsMessage': 'Попробуйте другое имя, телефон или email.',
      'loginRequired': 'Требуется вход',
      'loginMessage': 'Войдите для управления клиентами.',
      'loadFailed': 'Не удалось загрузить клиентов',
      'tryAgain': 'Проверьте соединение и повторите попытку.',
    },
    'am': {
      'title': 'ደንበኞች',
      'manageClients': 'የእርስዎ ደንበኞች',
      'clientCount': '{count} ደንበኞች ተቀምጠዋል',
      'search': 'በስም፣ ስልክ ወይም ኢሜይል ይፈልጉ',
      'clearSearch': 'ፍለጋን አጽዳ',
      'addClient': 'ደንበኛ ጨምር',
      'editClient': 'ደንበኛ አርትዕ',
      'formHint': 'የደንበኛ መረጃን ለንግድ ሰነዶችዎ ያዘጋጁ።',
      'name': 'የደንበኛ ስም',
      'phone': 'ስልክ ቁጥር',
      'primaryPhone': 'ዋና ስልክ ቁጥር',
      'email': 'ኢሜይል',
      'primaryEmail': 'ዋና ኢሜይል',
      'primaryContactHint': 'በአዲስ ሰነዶች ውስጥ በራስ-ሰር ይጠቀማል',
      'addPhone': 'ሌላ ስልክ ቁጥር ጨምር',
      'addEmail': 'ሌላ ኢሜይል ጨምር',
      'removeField': 'አስወግድ',
      'taxId': 'የንግድ / መታወቂያ / ግብር ቁጥር',
      'taxIdShort': 'መታወቂያ',
      'taxIdInvalidLength': 'የደንበኛ መታወቂያ በትክክል 9 አሃዞች መሆን አለበት።',
      'taxIdInvalid': 'ትክክለኛ የእስራኤል መታወቂያ ቁጥር ያስገቡ።',
      'externalClientNumber': 'የውጭ ሂሳብ የደንበኛ ቁጥር',
      'externalClientNumberShort': 'የሂሳብ ቁጥር',
      'externalClientNumberHint': 'ከ1–10 ቁጥሮች',
      'externalClientNumberInvalid': 'ከ1–10 ቁጥሮች ያስገቡ። ይህ መስክ ያስፈልጋል።',
      'clientNumberDuplicate': 'ይህ የደንበኛ ቁጥር በሌላ ደንበኛ ጥቅም ላይ ነው።',
      'generateClientNumber': 'አዲስ የደንበኛ ቁጥር ፍጠር',
      'address': 'አድራሻ',
      'notes': 'ማስታወሻዎች',
      'close': 'ዝጋ',
      'saveClient': 'ደንበኛ አስቀምጥ',
      'saving': 'በማስቀመጥ ላይ...',
      'nameRequired': 'የደንበኛውን ስም ያስገቡ።',
      'invalidEmail': 'ትክክለኛ ኢሜይል ያስገቡ።',
      'clientAdded': 'ደንበኛው ተጨምሯል።',
      'clientUpdated': 'የደንበኛ መረጃ ተዘምኗል።',
      'saveFailed': 'ደንበኛውን ማስቀመጥ አልተቻለም።',
      'deleteClient': 'ደንበኛው ይሰረዝ?',
      'deleteConfirmation': '{name}ን ከደንበኞች ዝርዝር ያስወግዱ?',
      'cancel': 'ሰርዝ',
      'delete': 'አጥፋ',
      'edit': 'አርትዕ',
      'clientDeleted': 'ደንበኛው ተሰርዟል።',
      'deleteFailed': 'ደንበኛውን መሰረዝ አልተቻለም።',
      'moreActions': 'ተጨማሪ እርምጃዎች',
      'noContactDetails': 'የመገናኛ መረጃ አልተጨመረም',
      'createDocument': 'ሰነድ ፍጠር',
      'createDocumentFailed': 'የሰነድ አዘጋጁን መክፈት አልተቻለም።',
      'noClients': 'እስካሁን ደንበኞች የሉም',
      'noClientsMessage': 'የደንበኞችን መገናኛ እና የክፍያ መረጃ በአንድ ቦታ ያደራጁ።',
      'addFirstClient': 'የመጀመሪያ ደንበኛ ጨምር',
      'noResults': 'ተዛማጅ ደንበኞች አልተገኙም',
      'noResultsMessage': 'ሌላ ስም፣ ስልክ ወይም ኢሜይል ይሞክሩ።',
      'loginRequired': 'መግባት ያስፈልጋል',
      'loginMessage': 'ደንበኞችን ለማስተዳደር ይግቡ።',
      'loadFailed': 'ደንበኞችን መጫን አልተቻለም',
      'tryAgain': 'ግንኙነትዎን ይፈትሹና እንደገና ይሞክሩ።',
    },
  };
}
