import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/analytics_service.dart';
import 'package:untitled1/services/ai_description_service.dart';
import 'package:untitled1/pages/subscription.dart';
import 'package:untitled1/map/map_radius_picker.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/pages/privacy_policy_page.dart';
import 'package:untitled1/pages/terms_of_service_page.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/utils/profession_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

class SignUpPage extends StatefulWidget {
  final Map<String, dynamic>? pendingWorkerData;
  final File? pendingWorkerImage;
  final int startAtStep;

  const SignUpPage({
    super.key,
    this.pendingWorkerData,
    this.pendingWorkerImage,
    this.startAtStep = 0,
  });

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

enum SignUpStep { profile, phone }

enum UserType { normal, worker }

class _SignUpPageState extends State<SignUpPage> with TickerProviderStateMixin {
  static final Uri _googlePlayWorkerAppUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.hirehub.app',
  );
  static final Uri _appleStoreWorkerAppUri = Uri.parse(
    'https://apps.apple.com/us/app/hiro-%D7%94%D7%99%D7%A8%D7%95/id6763238120',
  );
  static const List<int> _displayWeekdayOrder = [7, 1, 2, 3, 4, 5, 6];
  static const List<String> _spokenLanguageOptions = [
    'Hebrew',
    'Arabic',
    'English',
    'Russian',
    'Amharic',
  ];
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();

  late SignUpStep _currentStep;
  late UserType _userType;

  String? _selectedTown;
  List<String> _selectedProfessions = [];
  List<String> _selectedSpokenLanguages = [];
  List<Map<String, dynamic>> _professionItems = [];

  bool _loading = false;
  bool _autoCompletingFromPaidWorker = false;
  bool _professionSelectorOpen = false;
  bool _agreedToPolicy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _codeSent = false;
  bool _smsDialogOpen = false;
  String _verificationId = "";
  int? _resendToken;
  File? _image;
  final ImagePicker _picker = ImagePicker();

  AnimationController? _introController;
  AnimationController? _backgroundController;

  AnimationController get _introAnimationController {
    final controller = _introController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
    _introController = created;
    return created;
  }

  AnimationController get _backgroundAnimationController {
    final controller = _backgroundController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _backgroundController = created;
    return created;
  }

  void _ensureAnimationControllers() {
    _introAnimationController;
    _backgroundAnimationController;
  }

  Future<void> _openDescriptionAssistant(Map<String, String> strings) async {
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    var years = '';
    var specialties = '';
    var serviceStyle = '';
    var thingsYouDo = '';
    var thingsYouDontDo = '';
    var showValidation = false;
    var isGenerating = false;
    String? generationError;

    final generatedDescription = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isComplete =
              years.trim().isNotEmpty &&
              specialties.trim().isNotEmpty &&
              serviceStyle.trim().isNotEmpty &&
              thingsYouDo.trim().isNotEmpty &&
              thingsYouDontDo.trim().isNotEmpty;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 48,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE8F3FF), Color(0xFFF7FBFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF1976D2),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          strings['desc_assistant_title']!,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings['desc_assistant_subtitle']!,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildAssistantInfoChip(
                              icon: Icons.work_outline_rounded,
                              label: _selectedProfessions.isEmpty
                                  ? strings['desc_generated_profession_fallback']!
                                  : _selectedProfessions
                                        .map(
                                          (profession) =>
                                              _labelForStoredProfession(
                                                profession,
                                                localeCode,
                                              ),
                                        )
                                        .join(', '),
                            ),
                            if ((_selectedTown ?? '').trim().isNotEmpty)
                              _buildAssistantInfoChip(
                                icon: Icons.location_on_outlined,
                                label: _selectedTown!.trim(),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings['desc_assistant_section_background']!,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDescriptionAssistantField(
                            label: strings['desc_question_years']!,
                            hintText: strings['desc_question_years_hint']!,
                            icon: Icons.timeline_rounded,
                            keyboardType: TextInputType.number,
                            onChanged: (value) => setDialogState(() {
                              years = value;
                              generationError = null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildDescriptionAssistantField(
                            label: strings['desc_question_specialties']!,
                            hintText:
                                strings['desc_question_specialties_hint']!,
                            icon: Icons.handyman_outlined,
                            maxLines: 2,
                            onChanged: (value) => setDialogState(() {
                              specialties = value;
                              generationError = null;
                            }),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            strings['desc_assistant_section_service']!,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDescriptionAssistantField(
                            label: strings['desc_question_service_style']!,
                            hintText:
                                strings['desc_question_service_style_hint']!,
                            icon: Icons.favorite_border_rounded,
                            maxLines: 2,
                            onChanged: (value) => setDialogState(() {
                              serviceStyle = value;
                              generationError = null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildDescriptionAssistantField(
                            label: strings['desc_question_things_you_do']!,
                            hintText:
                                strings['desc_question_things_you_do_hint']!,
                            icon: Icons.check_circle_outline_rounded,
                            maxLines: 3,
                            onChanged: (value) => setDialogState(() {
                              thingsYouDo = value;
                              generationError = null;
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildDescriptionAssistantField(
                            label: strings['desc_question_things_you_dont_do']!,
                            hintText:
                                strings['desc_question_things_you_dont_do_hint']!,
                            icon: Icons.remove_circle_outline_rounded,
                            maxLines: 3,
                            onChanged: (value) => setDialogState(() {
                              thingsYouDontDo = value;
                              generationError = null;
                            }),
                          ),
                          if (showValidation && !isComplete) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFE11D48,
                                ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(
                                    0xFFE11D48,
                                  ).withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                strings['desc_assistant_validation']!,
                                style: const TextStyle(
                                  color: Color(0xFFBE123C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          if (generationError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.22),
                                ),
                              ),
                              child: Text(
                                generationError!,
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isGenerating
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFD7E1EC)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(strings['cancel']!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isGenerating
                                ? null
                                : () async {
                                    years = years.trim();
                                    specialties = specialties.trim();
                                    serviceStyle = serviceStyle.trim();
                                    thingsYouDo = thingsYouDo.trim();
                                    thingsYouDontDo = thingsYouDontDo.trim();

                                    if (!isComplete) {
                                      setDialogState(
                                        () => showValidation = true,
                                      );
                                      return;
                                    }

                                    setDialogState(() {
                                      isGenerating = true;
                                      generationError = null;
                                    });

                                    try {
                                      final professions = _selectedProfessions
                                          .map(
                                            (profession) =>
                                                _labelForStoredProfession(
                                                  profession,
                                                  localeCode,
                                                ),
                                          )
                                          .toList();
                                      final description =
                                          await AiDescriptionService.generateDescription(
                                            AiDescriptionRequest(
                                              localeCode: localeCode,
                                              professions: professions,
                                              town: _selectedTown,
                                              years: years,
                                              specialties: specialties,
                                              serviceStyle: serviceStyle,
                                              thingsYouDo: thingsYouDo,
                                              thingsYouDontDo: thingsYouDontDo,
                                            ),
                                          );
                                      if (!context.mounted) return;
                                      Navigator.of(context).pop(description);
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      setDialogState(() {
                                        isGenerating = false;
                                        generationError =
                                            strings['desc_ai_generation_error']!;
                                      });
                                    }
                                  },
                            icon: isGenerating
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome_rounded),
                            label: Text(
                              isGenerating
                                  ? strings['desc_generate_loading']!
                                  : strings['desc_generate_action']!,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
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
        },
      ),
    );

    if (!mounted || generatedDescription == null) return;
    setState(() {
      _descriptionController.text = generatedDescription;
    });
  }

  Widget _buildAssistantInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E8F8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1976D2)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionAssistantField({
    required String label,
    required String hintText,
    required IconData icon,
    required ValueChanged<String> onChanged,
    bool required = true,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        label: _buildRequiredLabel(label, required: required),
        hintText: hintText,
        alignLabelWithHint: maxLines > 1,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.only(top: maxLines > 1 ? 12 : 0),
          child: Icon(icon, color: const Color(0xFF64748B), size: 20),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.4),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }

  LatLng? _workCenter;
  double _workRadius = 15000.0;
  double _savedWorkRadius = 15000.0;
  bool _disableWorkRadius = false;
  bool _hideSchedule = false;
  List<int> _disabledDays = [];
  TimeOfDay _workingHoursFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _workingHoursTo = const TimeOfDay(hour: 16, minute: 0);

  @override
  void initState() {
    super.initState();
    _ensureAnimationControllers();

    _currentStep = SignUpStep.profile;
    _image = widget.pendingWorkerImage;

    if (widget.pendingWorkerData != null) {
      _userType = UserType.worker;
      _nameController.text = widget.pendingWorkerData!['name'] ?? "";
      _emailController.text = widget.pendingWorkerData!['email'] ?? "";
      _selectedTown = widget.pendingWorkerData!['town'];
      _selectedProfessions = List<String>.from(
        widget.pendingWorkerData!['professions'] ?? [],
      ).map(ProfessionLocalization.toCanonical).toList();
      _selectedSpokenLanguages = List<String>.from(
        widget.pendingWorkerData!['spokenLanguages'] ?? [],
      ).where(_spokenLanguageOptions.contains).toList();
      _altPhoneController.text =
          widget.pendingWorkerData!['optionalPhone'] ?? "";
      _descriptionController.text =
          widget.pendingWorkerData!['description'] ?? "";
      _hideSchedule = widget.pendingWorkerData!['hideSchedule'] ?? false;
      _disabledDays = List<int>.from(
        widget.pendingWorkerData!['disabledDays'] ?? [],
      );
      _workingHoursFrom = _parseStoredTime(
        widget.pendingWorkerData!['defaultWorkingHours']?['from']?.toString(),
        fallback: const TimeOfDay(hour: 8, minute: 0),
      );
      _workingHoursTo = _parseStoredTime(
        widget.pendingWorkerData!['defaultWorkingHours']?['to']?.toString(),
        fallback: const TimeOfDay(hour: 16, minute: 0),
      );
      _phoneController.text =
          widget.pendingWorkerData!['phone'] ??
          (FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
      final pendingLat = widget.pendingWorkerData!['lat'] as num?;
      final pendingLng = widget.pendingWorkerData!['lng'] as num?;
      if (pendingLat != null && pendingLng != null) {
        _workCenter = LatLng(pendingLat.toDouble(), pendingLng.toDouble());
      }
      final pendingRadius = (widget.pendingWorkerData!['workRadius'] as num?)
          ?.toDouble();
      if (pendingRadius != null) {
        if (pendingRadius <= 0) {
          _disableWorkRadius = true;
          _workRadius = 0;
          _savedWorkRadius = 15000.0;
        } else {
          _disableWorkRadius = false;
          _workRadius = pendingRadius;
          _savedWorkRadius = pendingRadius;
        }
      }
      _agreedToPolicy = true;
    } else {
      _userType = UserType.normal;
    }

    _loadProfessionItems();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryFinalizePaidWorkerRegistrationAfterSubscription();
    });
  }

  @override
  void reassemble() {
    FocusManager.instance.primaryFocus?.unfocus();
    super.reassemble();
  }

  Future<void> _loadProfessionItems() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('metadata')
          .doc('professions')
          .get();
      final data = snapshot.data();
      final rawItems = data?['items'];
      if (rawItems is! List) return;

      final items =
          rawItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => _professionCanonicalValue(item).isNotEmpty)
              .toList()
            ..sort((a, b) {
              final aId = (a['id'] as num?)?.toInt() ?? 1 << 30;
              final bId = (b['id'] as num?)?.toInt() ?? 1 << 30;
              if (aId != bId) return aId.compareTo(bId);
              return _professionCanonicalValue(
                a,
              ).compareTo(_professionCanonicalValue(b));
            });

      if (!mounted) return;
      setState(() {
        _professionItems = items;
        _selectedProfessions = _selectedProfessions
            .map(_normalizeStoredProfession)
            .where((profession) => profession.isNotEmpty)
            .toSet()
            .toList();
      });
    } catch (e) {
      debugPrint('Failed to load profession metadata: $e');
    }
  }

  String _professionCanonicalValue(Map<String, dynamic> item) {
    final english = item['en']?.toString().trim();
    if (english != null && english.isNotEmpty) return english;

    for (final key in const ['he', 'ar', 'ru', 'am']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic>? _findProfessionItem(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final item in _professionItems) {
      for (final key in const ['en', 'he', 'ar', 'ru', 'am']) {
        final candidate = item[key]?.toString().trim().toLowerCase();
        if (candidate != null &&
            candidate.isNotEmpty &&
            candidate == normalized) {
          return item;
        }
      }
    }
    return null;
  }

  String _normalizeStoredProfession(String value) {
    final item = _findProfessionItem(value);
    if (item != null) {
      return _professionCanonicalValue(item);
    }
    return ProfessionLocalization.toCanonical(value);
  }

  String _professionLabel(Map<String, dynamic> item, String localeCode) {
    final localized = item[localeCode]?.toString().trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return _professionCanonicalValue(item);
  }

  List<String> _professionSearchTerms(Map<String, dynamic> item) {
    final terms = <String>{};
    for (final key in const ['en', 'he', 'ar', 'ru', 'am']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        terms.add(value.toLowerCase());
      }
    }
    final canonical = _professionCanonicalValue(item).trim().toLowerCase();
    if (canonical.isNotEmpty) {
      terms.add(canonical);
    }
    return terms.toList();
  }

  List<Map<String, dynamic>> _professionOptions() {
    final rawOptions = _professionItems.isNotEmpty
        ? _professionItems
        : ProfessionLocalization.canonicalProfessions
              .map((profession) => <String, dynamic>{'en': profession})
              .toList();

    final seenCanonical = <String>{};
    final uniqueOptions = <Map<String, dynamic>>[];
    for (final item in rawOptions) {
      final canonical = _professionCanonicalValue(item);
      if (canonical.isEmpty || !seenCanonical.add(canonical.toLowerCase())) {
        continue;
      }
      uniqueOptions.add(item);
    }
    return uniqueOptions;
  }

  int _professionSearchScore(Map<String, dynamic> item, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return 0;

    final label = _professionLabel(item, 'en').toLowerCase();
    if (label == normalizedQuery) return 400;
    if (label.startsWith(normalizedQuery)) return 300;

    for (final term in _professionSearchTerms(item)) {
      if (term == normalizedQuery) return 260;
      if (term.startsWith(normalizedQuery)) return 220;
      if (term.contains(normalizedQuery)) return 140;
    }

    final words = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (words.isEmpty) return 0;

    var matches = 0;
    for (final word in words) {
      if (_professionSearchTerms(item).any((term) => term.contains(word))) {
        matches++;
      }
    }
    return matches == words.length ? 80 + matches : 0;
  }

  Future<void> _openProfessionSelector(Map<String, String> strings) async {
    if (_professionSelectorOpen) return;
    _professionSelectorOpen = true;
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    final draftSelectedProfessions = List<String>.from(_selectedProfessions);
    var isClosing = false;

    List<Map<String, dynamic>> filteredOptions(String query) {
      final normalizedQuery = query.trim().toLowerCase();
      final filtered = _professionOptions().where((item) {
        if (normalizedQuery.isEmpty) return true;
        return _professionSearchScore(item, normalizedQuery) > 0;
      }).toList();

      filtered.sort((a, b) {
        final aCanonical = _professionCanonicalValue(a);
        final bCanonical = _professionCanonicalValue(b);
        final aSelected = draftSelectedProfessions.contains(aCanonical);
        final bSelected = draftSelectedProfessions.contains(bCanonical);
        if (aSelected != bSelected) return aSelected ? -1 : 1;

        final scoreDiff = _professionSearchScore(
          b,
          normalizedQuery,
        ).compareTo(_professionSearchScore(a, normalizedQuery));
        if (scoreDiff != 0) return scoreDiff;

        return _professionLabel(a, localeCode).toLowerCase().compareTo(
          _professionLabel(b, localeCode).toLowerCase(),
        );
      });

      return filtered;
    }

    void toggleDraftProfession(String profession) {
      if (draftSelectedProfessions.contains(profession)) {
        draftSelectedProfessions.remove(profession);
      } else {
        draftSelectedProfessions.add(profession);
      }
    }

    try {
      final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final query = searchController.text;
              final options = filteredOptions(query);
              Future<void> closeSheet() async {
                if (isClosing) return;
                isClosing = true;
                searchFocusNode.unfocus();
                FocusScope.of(sheetContext).unfocus();
                await WidgetsBinding.instance.endOfFrame;
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop(draftSelectedProfessions);
              }

              return PopScope<List<String>>(
                canPop: false,
                onPopInvokedWithResult: (didPop, result) {
                  if (didPop) return;
                  closeSheet();
                },
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      bottom:
                          MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                    ),
                    child: Container(
                      height: MediaQuery.of(sheetContext).size.height * 0.78,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 36,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(top: 12, bottom: 18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF1976D2,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.work_outline_rounded,
                                    color: Color(0xFF1976D2),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings['professions']!,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _selectedCountLabel(
                                          localeCode,
                                          draftSelectedProfessions.length,
                                        ),
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: closeSheet,
                                  child: Text(strings['close']!),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: _buildStyledTextField(
                              controller: searchController,
                              labelText: strings['professions']!,
                              icon: Icons.search_rounded,
                              hintText: strings['search_hint'],
                              focusNode: searchFocusNode,
                              onChanged: (_) => setSheetState(() {}),
                            ),
                          ),
                          if (draftSelectedProfessions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: draftSelectedProfessions.map((
                                    profession,
                                  ) {
                                    return InputChip(
                                      label: Text(
                                        _labelForStoredProfession(
                                          profession,
                                          localeCode,
                                        ),
                                      ),
                                      selected: true,
                                      onDeleted: () {
                                        toggleDraftProfession(profession);
                                        setSheetState(() {});
                                      },
                                      selectedColor: const Color(
                                        0xFF1976D2,
                                      ).withValues(alpha: 0.14),
                                      deleteIconColor: const Color(0xFF1976D2),
                                      side: BorderSide.none,
                                      labelStyle: const TextStyle(
                                        color: Color(0xFF0F4C9A),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          Expanded(
                            child: options.isEmpty
                                ? Center(
                                    child: Text(
                                      _noProfessionMatchesLabel(localeCode),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      14,
                                      14,
                                    ),
                                    itemCount: options.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final item = options[index];
                                      final canonical =
                                          _professionCanonicalValue(item);
                                      final label = _professionLabel(
                                        item,
                                        localeCode,
                                      );
                                      final isSelected =
                                          draftSelectedProfessions.contains(
                                            canonical,
                                          );

                                      return Material(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          onTap: () {
                                            toggleDraftProfession(canonical);
                                            setSheetState(() {});
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFF1976D2)
                                                    : const Color(0xFFE2E8F0),
                                                width: isSelected ? 1.4 : 1,
                                              ),
                                              color: isSelected
                                                  ? const Color(
                                                      0xFF1976D2,
                                                    ).withValues(alpha: 0.08)
                                                  : Colors.white,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isSelected
                                                        ? const Color(
                                                            0xFF1976D2,
                                                          )
                                                        : Colors.transparent,
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? const Color(
                                                              0xFF1976D2,
                                                            )
                                                          : const Color(
                                                              0xFFCBD5E1,
                                                            ),
                                                      width: 1.4,
                                                    ),
                                                  ),
                                                  child: isSelected
                                                      ? const Icon(
                                                          Icons.check,
                                                          size: 14,
                                                          color: Colors.white,
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Text(
                                                    label,
                                                    style: TextStyle(
                                                      color: const Color(
                                                        0xFF0F172A,
                                                      ),
                                                      fontSize: 15,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w800
                                                          : FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
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
            },
          );
        },
      );

      if (!mounted || result == null) return;
      setState(() {
        _selectedProfessions = result.toSet().toList();
      });
    } finally {
      FocusManager.instance.primaryFocus?.unfocus();
      // The modal route can still build during its reverse animation after
      // showModalBottomSheet completes, so keep field resources alive briefly.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      searchController.dispose();
      searchFocusNode.dispose();
      _professionSelectorOpen = false;
    }
  }

  String _labelForStoredProfession(String profession, String localeCode) {
    final item = _findProfessionItem(profession);
    if (item != null) {
      return _professionLabel(item, localeCode);
    }
    return ProfessionLocalization.toLocalized(profession, localeCode);
  }

  String _selectedCountLabel(String localeCode, int count) {
    switch (localeCode) {
      case 'he':
        return '$count נבחרו';
      case 'ar':
        return 'تم اختيار $count';
      case 'ru':
        return 'Выбрано: $count';
      case 'am':
        return '$count ተመርጧል';
      default:
        return '$count selected';
    }
  }

  String _noProfessionMatchesLabel(String localeCode) {
    switch (localeCode) {
      case 'he':
        return 'לא נמצאו מקצועות תואמים';
      case 'ar':
        return 'لم يتم العثور على مهن مطابقة';
      case 'ru':
        return 'Подходящие профессии не найдены';
      case 'am':
        return 'ተመሳሳይ ሙያዎች አልተገኙም';
      default:
        return 'No matching professions';
    }
  }

  TimeOfDay _parseStoredTime(String? value, {required TimeOfDay fallback}) {
    final raw = (value ?? '').trim();
    final parts = raw.split(':');
    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return fallback;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatStoredTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _displayTime(TimeOfDay time) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(time, alwaysUse24HourFormat: true);
  }

  Future<void> _pickWorkingHour({required bool isStart}) async {
    final initialTime = isStart ? _workingHoursFrom : _workingHoursTo;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;

    final currentStart = isStart ? picked : _workingHoursFrom;
    final currentEnd = isStart ? _workingHoursTo : picked;
    final startMinutes = (currentStart.hour * 60) + currentStart.minute;
    final endMinutes = (currentEnd.hour * 60) + currentEnd.minute;
    if (endMinutes <= startMinutes) return;

    setState(() {
      if (isStart) {
        _workingHoursFrom = picked;
      } else {
        _workingHoursTo = picked;
      }
    });
  }

  Future<void> _tryFinalizePaidWorkerRegistrationAfterSubscription() async {
    if (_autoCompletingFromPaidWorker) return;
    if (widget.pendingWorkerData == null) return;
    if (!SubscriptionAccessService.isEntitledSubscriptionStatus(
      widget.pendingWorkerData?['subscriptionStatus']?.toString(),
    )) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.phoneNumber == null || user.phoneNumber!.isEmpty) {
      return;
    }

    _autoCompletingFromPaidWorker = true;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    await _commitUserDataToDatabase();
  }

  @override
  void dispose() {
    _introController?.dispose();
    _backgroundController?.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _altPhoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'יצירת חשבון',
          'subtitle': 'צרו פרופיל מאומת והמשיכו ל-Hiro.',
          'access': 'הרשמה מאובטחת',
          'profile_card_title': 'פרטי חשבון',
          'profile_card_subtitle': 'כמה פרטים קצרים לפני אימות הטלפון.',
          'phone_card_title': 'אימות טלפון',
          'phone_card_subtitle': 'הכניסו את הקוד שקיבלתם ב-SMS כדי לסיים.',
          'feature_profile_title': 'פרופיל ברור',
          'feature_profile_body': 'פרטים בסיסיים שמכינים את החשבון.',
          'feature_phone_title': 'אימות מהיר',
          'feature_phone_body': 'קוד SMS קצר שומר על גישה אמינה.',
          'feature_pro_title': 'מוכן למקצוענים',
          'feature_pro_body': 'רדיוס עבודה, שעות ומקצועות במקום אחד.',
          'phone_label': 'מספר טלפון',
          'phone_subtitle': 'הכנס את מספר הטלפון שלך לאימות וסיום',
          'send_code': 'שלח קוד אימות',
          'verify_code': 'אמת וסיים הרשמה',
          'enter_code': 'הכנס קוד שקיבלת ב-SMS',
          'name_label': 'שם מלא',
          'email_label': 'אימייל',
          'town_label': 'עיר',
          'user_type': 'סוג חשבון',
          'normal': 'לקוח',
          'pro': 'בעל מקצוע',
          'professions': 'בחר מקצועות',
          'spoken_languages': 'שפות מדוברות',
          'spoken_languages_required': 'יש לבחור לפחות שפה אחת',
          'alt_phone': 'טלפון נוסף (אופציונלי)',
          'desc_label': 'ספר על עצמך',
          'desc_helper':
              'כתוב בקצרה מה הניסיון שלך, באילו עבודות אתה מתמחה, ואיזה שירות אתה נותן.',
          'desc_generate_button': 'צור תיאור',
          'desc_assistant_title': 'יצירת תיאור אוטומטית',
          'desc_assistant_subtitle':
              'ענה על כמה שאלות קצרות, ו-Firebase AI יכין עבורך תיאור מקצועי שאפשר לערוך.',
          'desc_assistant_section_background': 'רקע וניסיון',
          'desc_assistant_section_service': 'שירות וגבולות עבודה',
          'desc_assistant_validation': 'יש למלא את כל השדות כדי ליצור תיאור.',
          'desc_question_years': 'כמה שנות ניסיון יש לך?',
          'desc_question_years_hint': 'לדוגמה: 6',
          'desc_question_specialties': 'במה אתה מתמחה?',
          'desc_question_specialties_hint':
              'לדוגמה: תיקוני חשמל, התקנות, איתור תקלות',
          'desc_question_service_style': 'איך היית מתאר את השירות שלך?',
          'desc_question_service_style_hint': 'לדוגמה: אדיב, מדויק, נקי ומסודר',
          'desc_question_things_you_do': 'כתוב על הדברים שאתה עושה',
          'desc_question_things_you_do_hint':
              'לדוגמה: התקנות, תיקונים, תחזוקה, ייעוץ',
          'desc_question_things_you_dont_do': 'כתוב על הדברים שאתה לא עושה',
          'desc_question_things_you_dont_do_hint':
              'לדוגמה: לא עובד בשבת, לא מטפל בתעשייה, לא עושה עבודות חירום',
          'desc_generate_action': 'צור עם AI',
          'desc_generate_loading': 'יוצר תיאור...',
          'desc_ai_generation_error':
              'לא הצלחנו ליצור תיאור כרגע. בדוק ש-Firebase AI Logic מוגדר ונסה שוב.',
          'desc_generated_profession_fallback': 'בעל/ת מקצוע',
          'desc_generated_town': ' אני עובד/ת באזור {town}.',
          'agree_prefix': 'אני מסכים ל-',
          'and': ' ו-',
          'terms_link': 'תנאי השימוש',
          'privacy_link': 'מדיניות הפרטיות',
          'finish': 'המשך לאימות טלפון',
          'pay': 'המשך לתשלום מנוי',
          'req': 'שדה חובה',
          'policy_err': 'עליך להסכים לתנאים',
          'invalid_phone': 'אנא הכנס מספר טלפון ישראלי תקין (05XXXXXXXX)',
          'error_verify': 'שגיאה באימות הקוד',
          'search_hint': 'חפש...',
          'terms_title': 'תנאי שימוש',
          'terms_content': 'תנאי השימוש...',
          'privacy_title': 'מדיניות פרטיות',
          'privacy_content': 'מדיניות פרטיות...',
          'cancel': 'ביטול',
          'close': 'סגור',
          'current_loc': 'מיקום נוכחי',
          'pick_map': 'בחר מהמפה',
          'work_radius': 'רדיוס עבודה',
          'work_radius_help': 'מגדיר עד לאיזה מרחק השירות שלך מגיע.',
          'disable_radius': 'לא מגיע ללקוח (הלקוח מגיע אליי)',
          'hide_schedule': 'הסתר לוח זמנים מאחרים',
          'working_hours': 'שעות עבודה',
          'available_from': 'זמין מ-',
          'available_to': 'זמין עד',
          'select_off_days': 'בחר ימי חופש קבועים',
          'days': '1,2,3,4,5,6,7',
          'radius_val': 'רדיוס: {val} ק"מ',
          'select_radius': 'בחר רדיוס על המפה',
          'edit_phone': 'ערוך מספר טלפון',
          'resend_code': 'שלח SMS שוב',
          'phone_hint': 'לדוגמה: 0501234567',
          'sms_failed': 'שליחת ה-SMS נכשלה: {msg}',
          'auth_error': 'שגיאת אימות: {err}',
          'db_error': 'שגיאת מסד נתונים: {err}',
          'location_services_disabled': 'שירותי המיקום כבויים.',
          'location_permissions_denied': 'הרשאות המיקום נדחו',
          'location_permissions_denied_forever': 'הרשאות המיקום נדחו לצמיתות.',
        };
      case 'ar':
        return {
          'title': 'إنشاء حساب',
          'subtitle': 'أنشئ ملفًا موثقًا وواصل إلى Hiro.',
          'access': 'تسجيل آمن',
          'profile_card_title': 'تفاصيل الحساب',
          'profile_card_subtitle': 'بضع تفاصيل سريعة قبل التحقق من الهاتف.',
          'phone_card_title': 'التحقق عبر الهاتف',
          'phone_card_subtitle': 'أدخل رمز SMS لإكمال إنشاء الحساب.',
          'feature_profile_title': 'ملف واضح',
          'feature_profile_body': 'تفاصيل أساسية تجهز حسابك.',
          'feature_phone_title': 'تحقق سريع',
          'feature_phone_body': 'رمز SMS قصير يحافظ على أمان الوصول.',
          'feature_pro_title': 'جاهز للمحترفين',
          'feature_pro_body': 'نطاق العمل، الساعات، والمهن في مسار واحد.',
          'phone_label': 'رقم الهاتف',
          'phone_subtitle': 'أدخل رقم هاتفك للتحقق والإكمال',
          'send_code': 'إرسال رمز التحقق',
          'verify_code': 'تحقق وأكمل',
          'enter_code': 'أدخل رمز SMS',
          'name_label': 'الاسم الكامل',
          'email_label': 'البريد الإلكتروني',
          'town_label': 'المدينة',
          'user_type': 'نوع المستخدم',
          'normal': 'عميل',
          'pro': 'محترف',
          'professions': 'اختر المهن',
          'spoken_languages': 'اللغات المحكية',
          'spoken_languages_required': 'اختر لغة واحدة على الأقل',
          'alt_phone': 'هاتف إضافي (اختياري)',
          'desc_label': 'الوصف',
          'desc_helper':
              'اكتب ملخصًا قصيرًا عن خبرتك وتخصصاتك والخدمة التي تقدمها.',
          'desc_generate_button': 'أنشئ وصفًا',
          'desc_assistant_title': 'توليد الوصف',
          'desc_assistant_subtitle':
              'أجب عن بضع أسئلة قصيرة وسيقوم Firebase AI بإنشاء وصف مصقول يمكنك تعديله.',
          'desc_assistant_section_background': 'الخلفية',
          'desc_assistant_section_service': 'تفاصيل الخدمة',
          'desc_assistant_validation': 'املأ جميع الحقول لتوليد الوصف.',
          'desc_question_years': 'كم سنة من الخبرة لديك؟',
          'desc_question_years_hint': 'مثال: 6',
          'desc_question_specialties': 'ما تخصصك؟',
          'desc_question_specialties_hint':
              'مثال: إصلاحات كهربائية، تركيب، استكشاف الأعطال',
          'desc_question_service_style': 'كيف تصف أسلوب خدمتك؟',
          'desc_question_service_style_hint': 'مثال: ودود، دقيق، نظيف، موثوق',
          'desc_question_things_you_do': 'اكتب عن الأشياء التي تقوم بها',
          'desc_question_things_you_do_hint':
              'مثال: تركيب، إصلاحات، صيانة، فحوصات',
          'desc_question_things_you_dont_do':
              'اكتب عن الأشياء التي لا تقوم بها',
          'desc_question_things_you_dont_do_hint':
              'مثال: لا أعمال طارئة، لا أعمال صناعية، لا اتصالات في عطلة نهاية الأسبوع',
          'desc_generate_action': 'أنشئ بالذكاء الاصطناعي',
          'desc_generate_loading': 'جارٍ التوليد...',
          'desc_ai_generation_error':
              'تعذر علينا توليد وصف الآن. تأكد من إعداد Firebase AI Logic ثم حاول مرة أخرى.',
          'desc_generated_profession_fallback': 'مقدم خدمة',
          'desc_generated_town': ' أعمل في منطقة {town}.',
          'agree_prefix': 'أوافق على ',
          'and': ' و',
          'terms_link': 'شروط الاستخدام',
          'privacy_link': 'سياسة الخصوصية',
          'finish': 'المتابعة إلى التحقق من الهاتف',
          'pay': 'المتابعة إلى الاشتراك',
          'req': 'مطلوب',
          'policy_err': 'يجب أن توافق على الشروط',
          'invalid_phone': 'يرجى إدخال رقم هاتف إسرائيلي صالح (05XXXXXXXX)',
          'error_verify': 'خطأ في التحقق من الرمز',
          'search_hint': 'بحث...',
          'terms_title': 'شروط الاستخدام',
          'terms_content': 'شروط الاستخدام...',
          'privacy_title': 'سياسة الخصوصية',
          'privacy_content': 'سياسة الخصوصية...',
          'cancel': 'إلغاء',
          'close': 'إغلاق',
          'current_loc': 'الموقع الحالي',
          'pick_map': 'اختر من الخريطة',
          'work_radius': 'نطاق العمل',
          'work_radius_help': 'يحدد إلى أي مسافة تصل خدمتك.',
          'disable_radius': 'لا أصل للعميل (العميل يأتي إليّ)',
          'hide_schedule': 'إخفاء الجدول عن الآخرين',
          'working_hours': 'ساعات العمل',
          'available_from': 'متاح من',
          'available_to': 'متاح حتى',
          'select_off_days': 'اختر أيام العطلة الثابتة',
          'days': '1,2,3,4,5,6,7',
          'radius_val': 'النطاق: {val} كم',
          'select_radius': 'اختر النطاق على الخريطة',
          'edit_phone': 'تعديل رقم الهاتف',
          'resend_code': 'إرسال SMS مرة أخرى',
          'phone_hint': 'مثال: 0501234567',
          'sms_failed': 'فشل إرسال SMS: {msg}',
          'auth_error': 'خطأ في المصادقة: {err}',
          'db_error': 'خطأ في قاعدة البيانات: {err}',
          'location_services_disabled': 'خدمات الموقع معطلة.',
          'location_permissions_denied': 'تم رفض أذونات الموقع',
          'location_permissions_denied_forever':
              'تم رفض أذونات الموقع نهائيًا.',
        };
      case 'ru':
        return {
          'title': 'Создать аккаунт',
          'subtitle': 'Создайте подтвержденный профиль и продолжайте в Hiro.',
          'access': 'Безопасная регистрация',
          'profile_card_title': 'Данные аккаунта',
          'profile_card_subtitle':
              'Несколько быстрых данных перед проверкой телефона.',
          'phone_card_title': 'Проверка телефона',
          'phone_card_subtitle':
              'Введите SMS-код, чтобы завершить создание аккаунта.',
          'feature_profile_title': 'Понятный профиль',
          'feature_profile_body': 'Базовые данные, подготавливающие аккаунт.',
          'feature_phone_title': 'Быстрая проверка',
          'feature_phone_body':
              'Короткий SMS-код обеспечивает надежный доступ.',
          'feature_pro_title': 'Готово для профи',
          'feature_pro_body': 'Радиус работы, часы и профессии в одном потоке.',
          'phone_label': 'Номер телефона',
          'phone_subtitle': 'Введите номер телефона для проверки и завершения',
          'send_code': 'Отправить код подтверждения',
          'verify_code': 'Подтвердить и завершить',
          'enter_code': 'Введите SMS-код',
          'name_label': 'Полное имя',
          'email_label': 'Электронная почта',
          'town_label': 'Город',
          'user_type': 'Тип пользователя',
          'normal': 'Клиент',
          'pro': 'Профессионал',
          'professions': 'Выберите профессии',
          'spoken_languages': 'Разговорные языки',
          'spoken_languages_required': 'Выберите хотя бы один язык',
          'alt_phone': 'Дополнительный телефон (необязательно)',
          'desc_label': 'Описание',
          'desc_helper':
              'Кратко опишите ваш опыт, специализацию и услуги, которые вы предоставляете.',
          'desc_generate_button': 'Создать описание',
          'desc_assistant_title': 'Генерация описания',
          'desc_assistant_subtitle':
              'Ответьте на несколько коротких вопросов, и Firebase AI создаст отредактируемое описание.',
          'desc_assistant_section_background': 'Опыт и фон',
          'desc_assistant_section_service': 'Детали услуги',
          'desc_assistant_validation':
              'Заполните все поля, чтобы сгенерировать описание.',
          'desc_question_years': 'Сколько у вас лет опыта?',
          'desc_question_years_hint': 'Пример: 6',
          'desc_question_specialties': 'В чем вы специализируетесь?',
          'desc_question_specialties_hint':
              'Пример: электромонтаж, установка, поиск неисправностей',
          'desc_question_service_style': 'Как вы описали бы свой стиль работы?',
          'desc_question_service_style_hint':
              'Пример: вежливый, точный, аккуратный, надежный',
          'desc_question_things_you_do': 'Расскажите, что вы делаете',
          'desc_question_things_you_do_hint':
              'Пример: установка, ремонт, обслуживание, проверки',
          'desc_question_things_you_dont_do': 'Расскажите, чего вы не делаете',
          'desc_question_things_you_dont_do_hint':
              'Пример: без срочных выездов, без промышленной работы, без звонков в выходные',
          'desc_generate_action': 'Сгенерировать с AI',
          'desc_generate_loading': 'Генерируется...',
          'desc_ai_generation_error':
              'Сейчас не удалось сгенерировать описание. Убедитесь, что Firebase AI Logic настроен, и попробуйте снова.',
          'desc_generated_profession_fallback': 'специалист',
          'desc_generated_town': ' Я работаю в районе {town}.',
          'agree_prefix': 'Я согласен с ',
          'and': ' и ',
          'terms_link': 'Условиями использования',
          'privacy_link': 'Политикой конфиденциальности',
          'finish': 'Продолжить к проверке телефона',
          'pay': 'Перейти к подписке',
          'req': 'Обязательно',
          'policy_err': 'Вы должны согласиться с условиями',
          'invalid_phone':
              'Введите действительный израильский номер телефона (05XXXXXXXX)',
          'error_verify': 'Ошибка проверки кода',
          'search_hint': 'Поиск...',
          'terms_title': 'Условия использования',
          'terms_content': 'Условия использования...',
          'privacy_title': 'Политика конфиденциальности',
          'privacy_content': 'Политика конфиденциальности...',
          'cancel': 'Отмена',
          'close': 'Закрыть',
          'current_loc': 'Текущее местоположение',
          'pick_map': 'Выбрать на карте',
          'work_radius': 'Радиус работы',
          'work_radius_help':
              'Определяет, на какое расстояние распространяется ваша услуга.',
          'disable_radius': 'Я не выезжаю к клиенту (клиент приходит ко мне)',
          'hide_schedule': 'Скрыть расписание от других',
          'working_hours': 'Рабочие часы',
          'available_from': 'Доступен с',
          'available_to': 'Доступен до',
          'select_off_days': 'Выберите фиксированные выходные дни',
          'days': '1,2,3,4,5,6,7',
          'radius_val': 'Радиус: {val} км',
          'select_radius': 'Выберите радиус на карте',
          'edit_phone': 'Изменить номер телефона',
          'resend_code': 'Отправить SMS снова',
          'phone_hint': 'например: 0501234567',
          'sms_failed': 'Ошибка SMS: {msg}',
          'auth_error': 'Ошибка аутентификации: {err}',
          'db_error': 'Ошибка базы данных: {err}',
          'location_services_disabled': 'Службы геолокации отключены.',
          'location_permissions_denied': 'Разрешение на геолокацию отклонено',
          'location_permissions_denied_forever':
              'Разрешение на геолокацию отклонено навсегда.',
        };
      case 'am':
        return {
          'title': 'መለያ ፍጠር',
          'subtitle': 'የተረጋገጠ መገለጫ ፍጠሩ እና ወደ Hiro ይቀጥሉ።',
          'access': 'ደህንነቱ የተጠበቀ ምዝገባ',
          'profile_card_title': 'የመለያ ዝርዝሮች',
          'profile_card_subtitle': 'የስልክ ማረጋገጫ በፊት ጥቂት ፈጣን ዝርዝሮች።',
          'phone_card_title': 'የስልክ ማረጋገጫ',
          'phone_card_subtitle': 'መለያዎን ለማጠናቀቅ የSMS ኮድ ያስገቡ።',
          'feature_profile_title': 'ግልጽ መገለጫ',
          'feature_profile_body': 'መለያዎን የሚያዘጋጁ መሠረታዊ ዝርዝሮች።',
          'feature_phone_title': 'ፈጣን ማረጋገጫ',
          'feature_phone_body': 'አጭር የSMS ኮድ የታማኝ መዳረሻን ይጠብቃል።',
          'feature_pro_title': 'ለሙያዊዎች ዝግጁ',
          'feature_pro_body': 'የስራ ክልል፣ ሰዓታት እና ሙያዎች በአንድ ሂደት።',
          'phone_label': 'የስልክ ቁጥር',
          'phone_subtitle': 'ለማረጋገጥ እና ለማጠናቀቅ የስልክ ቁጥርዎን ያስገቡ',
          'send_code': 'የማረጋገጫ ኮድ ላክ',
          'verify_code': 'ያረጋግጡ እና ያጠናቅቁ',
          'enter_code': 'የSMS ኮድ ያስገቡ',
          'name_label': 'ሙሉ ስም',
          'email_label': 'ኢሜይል',
          'town_label': 'ከተማ',
          'user_type': 'የተጠቃሚ አይነት',
          'normal': 'ደንበኛ',
          'pro': 'ባለሙያ',
          'professions': 'ሙያዎችን ይምረጡ',
          'spoken_languages': 'የሚነገሩ ቋንቋዎች',
          'spoken_languages_required': 'ቢያንስ አንድ ቋንቋ ይምረጡ',
          'alt_phone': 'ተጨማሪ ስልክ (አማራጭ)',
          'desc_label': 'መግለጫ',
          'desc_helper': 'ስለ ተሞክሮዎ ፣ ልዩነቶችዎ እና የሚሰጡት አገልግሎት አጭር ማጠቃለያ ይጻፉ።',
          'desc_generate_button': 'መግለጫ ፍጠር',
          'desc_assistant_title': 'መግለጫ ማዘጋጀት',
          'desc_assistant_subtitle':
              'ጥቂት አጭር ጥያቄዎችን ይመልሱ፣ Firebase AI የሚታረም መግለጫ ያቀርባል እና ማስተካከል ይችላሉ።',
          'desc_assistant_section_background': 'ተሞክሮ እና ታሪክ',
          'desc_assistant_section_service': 'የአገልግሎት ዝርዝሮች',
          'desc_assistant_validation': 'መግለጫ ለመፍጠር ሁሉንም መስኮች ይሙሉ።',
          'desc_question_years': 'ስንት ዓመት ተሞክሮ አለዎት?',
          'desc_question_years_hint': 'ምሳሌ፡ 6',
          'desc_question_specialties': 'በምን ይለያያሉ?',
          'desc_question_specialties_hint': 'ምሳሌ፡ የኤሌክትሪክ ጥገና፣ መጫን፣ ችግኝ መፈለግ',
          'desc_question_service_style': 'የአገልግሎትዎን ዘይቤ እንዴት ይገልጹታል?',
          'desc_question_service_style_hint': 'ምሳሌ፡ ወዳጃዊ፣ ትክክለኛ፣ ንጹህ፣ ታማኝ',
          'desc_question_things_you_do': 'የሚያደርጉትን ነገሮች ይጻፉ',
          'desc_question_things_you_do_hint': 'ምሳሌ፡ መጫን፣ ጥገና፣ ጥገና ሥራ፣ ምርመራ',
          'desc_question_things_you_dont_do': 'የማያደርጉትን ነገሮች ይጻፉ',
          'desc_question_things_you_dont_do_hint':
              'ምሳሌ፡ አስቸኳይ ስራ የለም፣ ኢንዱስትሪያል ስራ የለም፣ በሳምንት መጨረሻ ጥሪ የለም',
          'desc_generate_action': 'በAI ፍጠር',
          'desc_generate_loading': 'በመፍጠር ላይ...',
          'desc_ai_generation_error':
              'አሁን መግለጫ ማፍጠር አልቻልንም። Firebase AI Logic ተዘጋጅቶ መኖሩን ያረጋግጡ እና ድጋሚ ይሞክሩ።',
          'desc_generated_profession_fallback': 'አገልግሎት ሰጪ',
          'desc_generated_town': 'በ{town} አካባቢ እሰራለሁ።',
          'agree_prefix': 'እስማማለሁ ',
          'and': 'እና ',
          'terms_link': 'የአጠቃቀም ውል',
          'privacy_link': 'የግላዊነት ፖሊሲ',
          'finish': 'ወደ የስልክ ማረጋገጫ ቀጥል',
          'pay': 'ወደ ምዝገባ ቀጥል',
          'req': 'ያስፈልጋል',
          'policy_err': 'ከቃላቱ ጋር መስማማት አለብዎት',
          'invalid_phone': 'እባክዎ ትክክለኛ የእስራኤል የስልክ ቁጥር ያስገቡ (05XXXXXXXX)',
          'error_verify': 'የኮድ ማረጋገጫ ስህተት',
          'search_hint': 'ፈልግ...',
          'terms_title': 'የአጠቃቀም ውል',
          'terms_content': 'የአጠቃቀም ውል...',
          'privacy_title': 'የግላዊነት ፖሊሲ',
          'privacy_content': 'የግላዊነት ፖሊሲ...',
          'cancel': 'ሰርዝ',
          'close': 'ዝጋ',
          'current_loc': 'የአሁኑ ቦታ',
          'pick_map': 'በካርታ ላይ ምረጥ',
          'work_radius': 'የስራ ክልል',
          'work_radius_help': 'አገልግሎትዎ እስከ ምን ርቀት እንደሚደርስ ይወስናል።',
          'disable_radius': 'ወደ ደንበኛ አልመጣም (ደንበኛው ወደ እኔ ይመጣል)',
          'hide_schedule': 'መርሃ ግብርን ከሌሎች ሰዎች ደብቅ',
          'working_hours': 'የስራ ሰዓታት',
          'available_from': 'የሚገኝ ከ',
          'available_to': 'የሚገኝ እስከ',
          'select_off_days': 'ቋሚ እረፍት ቀናት ይምረጡ',
          'days': '1,2,3,4,5,6,7',
          'radius_val': 'ክልል: {val} ኪሜ',
          'select_radius': 'በካርታ ላይ ክልል ይምረጡ',
          'edit_phone': 'የስልክ ቁጥር ያስተካክሉ',
          'resend_code': 'SMS እንደገና ላክ',
          'phone_hint': 'ለምሳሌ፡ 0501234567',
          'sms_failed': 'የSMS መላክ አልተሳካም: {msg}',
          'auth_error': 'የማረጋገጫ ስህተት: {err}',
          'db_error': 'የውሂብ ጎታ ስህተት: {err}',
          'location_services_disabled': 'የቦታ አገልግሎቶች ተዘግተዋል።',
          'location_permissions_denied': 'የቦታ ፈቃዶች ተከልክለዋል',
          'location_permissions_denied_forever': 'የቦታ ፈቃዶች በቋሚነት ተከልክለዋል።',
        };
      default:
        return {
          'title': 'Create Account',
          'subtitle': 'Create a verified profile and continue to Hiro.',
          'access': 'Secure Registration',
          'profile_card_title': 'Account Details',
          'profile_card_subtitle':
              'A few quick details before phone verification.',
          'phone_card_title': 'Phone Verification',
          'phone_card_subtitle':
              'Enter the SMS code to finish creating your account.',
          'feature_profile_title': 'Clear profile',
          'feature_profile_body': 'Basic details that prepare your account.',
          'feature_phone_title': 'Fast verification',
          'feature_phone_body': 'A short SMS code keeps access trusted.',
          'feature_pro_title': 'Pro ready',
          'feature_pro_body':
              'Work radius, hours, and professions in one flow.',
          'phone_label': 'Phone Number',
          'phone_subtitle': 'Enter your phone number to verify and complete',
          'send_code': 'Send Verification Code',
          'verify_code': 'Verify & Complete',
          'enter_code': 'Enter SMS Code',
          'name_label': 'Full Name',
          'email_label': 'Email',
          'town_label': 'City',
          'user_type': 'User Type',
          'normal': 'Client',
          'pro': 'Professional',
          'professions': 'Select Professions',
          'spoken_languages': 'Spoken Languages',
          'spoken_languages_required': 'Select at least one language',
          'alt_phone': 'Alt Phone (Optional)',
          'desc_label': 'Description',
          'desc_helper':
              'Write a short summary of your experience, specialties, and the service you provide.',
          'desc_generate_button': 'Generate description',
          'desc_assistant_title': 'Generate Description',
          'desc_assistant_subtitle':
              'Answer a few short questions and Firebase AI will create a polished description you can edit.',
          'desc_assistant_section_background': 'Background',
          'desc_assistant_section_service': 'Service details',
          'desc_assistant_validation':
              'Fill in all fields to generate your description.',
          'desc_question_years': 'How many years of experience do you have?',
          'desc_question_years_hint': 'Example: 6',
          'desc_question_specialties': 'What do you specialize in?',
          'desc_question_specialties_hint':
              'Example: electrical repairs, installations, troubleshooting',
          'desc_question_service_style':
              'How would you describe your service style?',
          'desc_question_service_style_hint':
              'Example: friendly, precise, clean, reliable',
          'desc_question_things_you_do': 'Write about the things you do',
          'desc_question_things_you_do_hint':
              'Example: installations, repairs, maintenance, inspections',
          'desc_question_things_you_dont_do':
              'Write about the things you do not do',
          'desc_question_things_you_dont_do_hint':
              'Example: no emergency jobs, no industrial work, no weekend calls',
          'desc_generate_action': 'Generate with AI',
          'desc_generate_loading': 'Generating...',
          'desc_ai_generation_error':
              'We could not generate a description right now. Make sure Firebase AI Logic is configured, then try again.',
          'desc_generated_profession_fallback': 'service',
          'desc_generated_town': ' I work in the {town} area.',
          'agree_prefix': 'I agree to the ',
          'and': ' and ',
          'terms_link': 'Terms of Use',
          'privacy_link': 'Privacy Policy',
          'finish': 'Continue to Phone Verification',
          'pay': 'Proceed to Subscription',
          'req': 'Required',
          'policy_err': 'You must agree to the terms',
          'invalid_phone':
              'Please enter a valid Israeli phone number (05XXXXXXXX)',
          'error_verify': 'Error verifying code',
          'search_hint': 'Search...',
          'terms_title': 'Terms of Use',
          'terms_content': 'Terms of Use...',
          'privacy_title': 'Privacy Policy',
          'privacy_content': 'Privacy Policy...',
          'cancel': 'Cancel',
          'close': 'Close',
          'current_loc': 'Current Location',
          'pick_map': 'Select on Map',
          'work_radius': 'Work Radius',
          'work_radius_help':
              'Defines how far your service reaches from your location.',
          'disable_radius':
              'I do not travel to customers (customers come to me)',
          'hide_schedule': 'Hide schedule from others',
          'working_hours': 'Working Hours',
          'available_from': 'Available from',
          'available_to': 'Available to',
          'select_off_days': 'Select fixed days off',
          'days': '1,2,3,4,5,6,7',
          'radius_val': 'Radius: {val} km',
          'select_radius': 'Select radius on Map',
          'edit_phone': 'Edit Phone Number',
          'resend_code': 'Send SMS Again',
          'phone_hint': 'e.g. 0501234567',
          'sms_failed': 'SMS failed: {msg}',
          'auth_error': 'Auth Error: {err}',
          'db_error': 'Database Error: {err}',
          'location_services_disabled': 'Location services are disabled.',
          'location_permissions_denied': 'Location permissions are denied',
          'location_permissions_denied_forever':
              'Location permissions are permanently denied.',
        };
    }
  }

  String _normalizePhone(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('972')) {
      digits = digits.substring(3);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+972$digits';
  }

  String _phoneAlreadyExistsMessage() {
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (localeCode) {
      case 'he':
        return 'מספר הטלפון הזה כבר רשום במערכת.';
      case 'ar':
        return 'رقم الهاتف هذا مسجل بالفعل في النظام.';
      case 'ru':
        return 'Этот номер телефона уже зарегистрирован в системе.';
      case 'am':
        return 'ይህ የስልክ ቁጥር ቀድሞ በስርዓቱ ውስጥ ተመዝግቧል።';
      default:
        return 'This phone number is already registered.';
    }
  }

  Future<void> _handleSendCode() async {
    final strings = _getLocalizedStrings(context);
    String input = _phoneController.text.trim();
    if (input.isEmpty) return;

    String phone = _normalizePhone(input);
    final regExp = RegExp(r'^\+9725\d{8}$');

    if (!regExp.hasMatch(phone)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['invalid_phone']!)));
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _onPhoneVerifiedAndSignedIn();
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  strings['sms_failed']!.replaceAll('{msg}', e.message ?? ''),
                ),
              ),
            );
          }
        },
        codeSent: (verificationId, resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _codeSent = true;
              _loading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_smsDialogOpen) {
                _showSmsVerificationDialog();
              }
            });
          }
          AnalyticsService.logSignUpCodeRequested(
            userType: _userType == UserType.worker ? 'worker' : 'customer',
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['auth_error']!.replaceAll('{err}', e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showSmsVerificationDialog() async {
    final strings = _getLocalizedStrings(context);
    _smsDialogOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: Directionality.of(context),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 44,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1976D2,
                          ).withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.sms_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    strings['phone_card_title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF070B18),
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings['phone_card_subtitle']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _normalizePhone(_phoneController.text.trim()),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildStyledTextField(
                    controller: _codeController,
                    labelText: strings['enter_code']!,
                    icon: Icons.lock_outline_rounded,
                    required: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _buildPrimaryButton(
                    label: strings['verify_code']!,
                    icon: Icons.verified_rounded,
                    onPressed: _loading ? null : _handleVerifyCode,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    children: [
                      TextButton(
                        onPressed: _loading ? null : _handleSendCode,
                        child: Text(
                          strings['resend_code']!,
                          style: const TextStyle(
                            color: Color(0xFF1976D2),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _codeSent = false;
                                  _verificationId = '';
                                  _codeController.clear();
                                });
                                Navigator.of(dialogContext).pop();
                              },
                        child: Text(
                          strings['edit_phone']!,
                          style: const TextStyle(
                            color: Color(0xFF1976D2),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mounted) {
      setState(() => _smsDialogOpen = false);
    } else {
      _smsDialogOpen = false;
    }
  }

  Future<void> _handleVerifyCode() async {
    final strings = _getLocalizedStrings(context);
    if (_codeController.text.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _codeController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _onPhoneVerifiedAndSignedIn();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['error_verify']!)));
      }
    }
  }

  Map<String, dynamic> _buildWorkerPendingDataWithPhone() {
    return {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _normalizePhone(_phoneController.text.trim()),
      'town': _selectedTown,
      'role': 'worker',
      'isSubscribed': false,
      'subscriptionStatus': 'inactive',
      'subscriptionCanceled': false,
      'professions': _selectedProfessions,
      'spokenLanguages': _selectedSpokenLanguages,
      'optionalPhone': _altPhoneController.text.trim(),
      'description': _descriptionController.text.trim(),
      'workRadius': _workRadius,
      'lat': _workCenter?.latitude,
      'lng': _workCenter?.longitude,
      'hideSchedule': _hideSchedule,
      'disabledDays': _disabledDays,
      'defaultWorkingHours': {
        'from': _formatStoredTime(_workingHoursFrom),
        'to': _formatStoredTime(_workingHoursTo),
      },
      'avgRating': 0.0,
      'reviewCount': 0,
    };
  }

  Future<bool> _linkEmailPasswordToCurrentUser() async {
    final strings = _getLocalizedStrings(context);
    final user = FirebaseAuth.instance.currentUser;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (user == null || email.isEmpty || password.isEmpty) {
      return false;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.linkWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') return true;
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ??
                  (strings['auth_error'] ?? 'Auth Error: {err}').replaceAll(
                    '{err}',
                    e.code,
                  ),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _onPhoneVerifiedAndSignedIn() async {
    final phoneUser = FirebaseAuth.instance.currentUser;
    if (phoneUser == null) return;

    // A collection query by phone would either leak private account data or be
    // denied by secure rules. Once phone ownership is verified, checking the
    // caller's own UID document is both private and rules-compatible.
    final existingProfile = await FirebaseFirestore.instance
        .collection('users')
        .doc(phoneUser.uid)
        .get();
    if (existingProfile.exists && widget.pendingWorkerData == null) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_phoneAlreadyExistsMessage())));
      }
      return;
    }

    final linkedPassword = await _linkEmailPasswordToCurrentUser();
    if (!linkedPassword) return;

    if (_userType == UserType.worker &&
        !SubscriptionAccessService.isEntitledSubscriptionStatus(
          widget.pendingWorkerData?['subscriptionStatus']?.toString(),
        )) {
      // Persist all entered data immediately after phone verification,
      // then continue the Pro subscription step.
      final profileCreated = await _commitUserDataToDatabase(
        navigateToHome: false,
      );
      if (!profileCreated) return;
      final workerPendingData = _buildWorkerPendingDataWithPhone();
      if (mounted) {
        setState(() {
          _loading = false;
          _codeSent = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubscriptionPage(
              email: _emailController.text.trim(),
              pendingUserData: workerPendingData,
              pendingImage: _image,
              isNewRegistration: true,
            ),
          ),
        );
      }
      return;
    }

    await _commitUserDataToDatabase();
  }

  Future<void> _getCurrentLocation() async {
    final strings = _getLocalizedStrings(context);
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw strings['location_services_disabled']!;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw strings['location_permissions_denied']!;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw strings['location_permissions_denied_forever']!;
      }

      Position position = await Geolocator.getCurrentPosition();
      LatLng loc = LatLng(position.latitude, position.longitude);
      setState(() => _workCenter = loc);
      await _updateTownFromLocation(loc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateTownFromLocation(LatLng loc) async {
    try {
      await setLocaleIdentifier('he_IL');
      List<Placemark> placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        String? town =
            placemark.locality ??
            placemark.subLocality ??
            placemark.subAdministrativeArea ??
            placemark.administrativeArea;
        if (town != null && town.isNotEmpty) {
          setState(() => _selectedTown = town);
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<bool> _commitUserDataToDatabase({bool navigateToHome = true}) async {
    final strings = _getLocalizedStrings(context);
    var writeStage = 'profile';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return false;
      }

      final firestore = FirebaseFirestore.instance;
      String imageUrl = "";
      String finalName = _nameController.text.trim();

      if (_image != null) {
        try {
          final ref = FirebaseStorage.instance.ref().child(
            'profile_pictures/${user.uid}.jpg',
          );
          await ref.putFile(_image!).timeout(const Duration(seconds: 15));
          imageUrl = await ref.getDownloadURL();
        } catch (e) {
          debugPrint("STORAGE ERROR: $e");
        }
      }

      double? lat = _workCenter?.latitude;
      double? lng = _workCenter?.longitude;
      if (lat == null && _selectedTown != null) {
        try {
          List<Location> locations = await locationFromAddress(
            "$_selectedTown, Israel",
          );
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (_) {}
      }

      final userData = {
        'uid': user.uid,
        'name': finalName,
        'email': _emailController.text.trim(),
        'phone': _normalizePhone(_phoneController.text.trim()),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'profileImageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'role': _userType == UserType.worker ? 'worker' : 'customer',
        'spokenLanguages': _selectedSpokenLanguages,
      };

      if (_userType == UserType.worker) {
        userData.addAll({
          'professions': _selectedProfessions,
          'spokenLanguages': _selectedSpokenLanguages,
          'optionalPhone': _altPhoneController.text.trim(),
          'description': _descriptionController.text.trim(),
          'workRadius': _workRadius,
          'hideSchedule': _hideSchedule,
          'disabledDays': _disabledDays,
        });
      }
      userData.removeWhere((_, value) => value == null);

      final userRef = firestore.collection('users').doc(user.uid);
      final existingUserSnap = await userRef.get();
      if (!existingUserSnap.exists) {
        // Account totals and other global metadata are server-owned. Including
        // them in this client write makes Firestore reject the whole account
        // creation transaction.
        await userRef.set(userData);
      } else {
        // Returning from subscription verification must only refresh fields
        // that an account owner may edit. Entitlement, role, ratings and
        // creation identity remain controlled by the backend/rules.
        const ownerEditableFields = {
          'name',
          'email',
          'phone',
          'town',
          'lat',
          'lng',
          'profileImageUrl',
          'spokenLanguages',
          'professions',
          'optionalPhone',
          'description',
          'workRadius',
          'hideSchedule',
          'disabledDays',
        };
        final profileUpdates = <String, dynamic>{
          for (final entry in userData.entries)
            if (ownerEditableFields.contains(entry.key)) entry.key: entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await userRef.set(profileUpdates, SetOptions(merge: true));
      }
      if (_userType == UserType.worker) {
        writeStage = 'schedule';
        await firestore
            .collection('users')
            .doc(user.uid)
            .collection('Schedule')
            .doc('info')
            .set({
              'hideSchedule': _hideSchedule,
              'disabledDays': _disabledDays,
              'defaultWorkingHours': {
                'from': _formatStoredTime(_workingHoursFrom),
                'to': _formatStoredTime(_workingHoursTo),
              },
            }, SetOptions(merge: true));
      }
      await user.updateDisplayName(finalName);

      await AnalyticsService.logSignUpCompleted(
        userType: _userType == UserType.worker ? 'worker' : 'customer',
        hasEmail: _emailController.text.trim().isNotEmpty,
      );

      if (mounted && navigateToHome) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MyHomePage()),
          (route) => false,
        );
      }
      return true;
    } catch (e) {
      debugPrint('SIGN-UP FIRESTORE ERROR [$writeStage]: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['db_error']!.replaceAll(
                '{err}',
                '[$writeStage] ${e.toString()}',
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _submitProfile() {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    final strings = _getLocalizedStrings(context);

    if (_selectedTown == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['town_label']!)));
      return;
    }

    if (_userType == UserType.worker && _selectedProfessions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['professions']!)));
      return;
    }

    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['policy_err']!)));
      return;
    }

    _handleSendCode();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAnimationControllers();
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final backgroundController = _backgroundAnimationController;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: backgroundController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _SignUpBackgroundPainter(
                          backgroundController.value,
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(child: _buildCurrentStep(isRtl, constraints)),
                if (_loading) _buildLoadingOverlay(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCurrentStep(bool isRtl, BoxConstraints constraints) {
    final strings = _getLocalizedStrings(context);
    final isWide = constraints.maxWidth >= 1080;
    final horizontalPadding = isWide
        ? 64.0
        : (constraints.maxWidth < 420 ? 20.0 : 28.0);
    final verticalPadding = isWide ? 56.0 : 28.0;

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(
            0,
            constraints.maxHeight - MediaQuery.paddingOf(context).vertical,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _buildReturnBackArrow(),
              ),
              const SizedBox(height: 10),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _buildStepLayout(
                      key: ValueKey(_currentStep),
                      strings: strings,
                      isRtl: isRtl,
                      isWide: isWide,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnBackArrow() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const BackButtonIcon(),
        color: const Color(0xFF1976D2),
      ),
    );
  }

  Widget _buildStepLayout({
    required Key key,
    required Map<String, String> strings,
    required bool isRtl,
    required bool isWide,
  }) {
    final compact = !isWide;
    final formWidth = _currentStep == SignUpStep.profile ? 660.0 : 520.0;
    final intro = Expanded(
      child: _buildAnimatedEntry(
        delay: 0,
        begin: isRtl ? const Offset(0.06, 0) : const Offset(-0.06, 0),
        child: _buildIntroPanel(strings, compact: false),
      ),
    );
    final form = _buildAnimatedEntry(
      delay: 0.14,
      begin: isRtl ? const Offset(-0.05, 0) : const Offset(0.05, 0),
      child: SizedBox(
        width: compact ? double.infinity : formWidth,
        child: AnimatedBuilder(
          animation: _backgroundAnimationController,
          builder: (context, child) {
            final offset =
                math.sin(_backgroundAnimationController.value * math.pi * 2) *
                4;
            return Transform.translate(offset: Offset(0, offset), child: child);
          },
          child: _currentStep == SignUpStep.profile
              ? _buildProfileStep(strings, compact: compact)
              : _buildPhoneStep(strings, isRtl, compact: compact),
        ),
      ),
    );

    if (!isWide) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnimatedEntry(
            delay: 0,
            child: _buildIntroPanel(strings, compact: true),
          ),
          const SizedBox(height: 24),
          form,
        ],
      );
    }

    const gap = SizedBox(width: 64);
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: isRtl ? [form, gap, intro] : [intro, gap, form],
    );
  }

  Widget _buildAnimatedEntry({
    required Widget child,
    double delay = 0,
    Offset begin = const Offset(0, 0.08),
  }) {
    final start = delay.clamp(0.0, 0.9).toDouble();
    final animation = CurvedAnimation(
      parent: _introAnimationController,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildIntroPanel(
    Map<String, String> strings, {
    required bool compact,
  }) {
    final isPhoneStep = _currentStep == SignUpStep.phone;
    final textAlign = compact ? TextAlign.center : TextAlign.start;
    final alignment = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        _buildAccessPill(strings),
        SizedBox(height: compact ? 24 : 28),
        Text(
          isPhoneStep ? strings['phone_card_title']! : strings['title']!,
          textAlign: textAlign,
          style: TextStyle(
            color: const Color(0xFF070B18),
            fontSize: compact ? 40 : 56,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 520 : 620),
          child: Text(
            isPhoneStep ? strings['phone_subtitle']! : strings['subtitle']!,
            textAlign: textAlign,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 20,
              height: 1.45,
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 48),
          _buildFeatureHighlights(strings),
        ],
      ],
    );
  }

  Widget _buildAccessPill(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF1976D2),
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              strings['access']!.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureHighlights(Map<String, String> strings) {
    final features = [
      _SignUpFeature(
        icon: Icons.badge_outlined,
        title: strings['feature_profile_title']!,
        body: strings['feature_profile_body']!,
      ),
      _SignUpFeature(
        icon: Icons.sms_outlined,
        title: strings['feature_phone_title']!,
        body: strings['feature_phone_body']!,
      ),
      _SignUpFeature(
        icon: Icons.work_outline_rounded,
        title: strings['feature_pro_title']!,
        body: strings['feature_pro_body']!,
      ),
    ];

    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: [
        for (var index = 0; index < features.length; index++)
          _buildAnimatedEntry(
            delay: 0.24 + index * 0.06,
            begin: const Offset(0, 0.12),
            child: SizedBox(
              width: 190,
              height: 156,
              child: _buildFeatureCard(features[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureCard(_SignUpFeature feature) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2A41).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(feature.icon, color: const Color(0xFF1976D2), size: 34),
          const Spacer(),
          Text(
            feature.title,
            style: const TextStyle(
              color: Color(0xFF101827),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            feature.body,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneStep(
    Map<String, String> strings,
    bool isRtl, {
    required bool compact,
  }) {
    return _buildStepCard(
      compact: compact,
      icon: Icons.phone_iphone_rounded,
      title: strings['phone_card_title']!,
      subtitle: strings['phone_card_subtitle']!,
      leading: widget.pendingWorkerData == null
          ? _buildBackButton(strings, isRtl)
          : null,
      child: Column(
        children: [
          _buildStyledTextField(
            controller: _phoneController,
            labelText: strings['phone_label']!,
            icon: Icons.phone_iphone_rounded,
            required: true,
            keyboardType: TextInputType.phone,
            hintText: strings['phone_hint'],
            enabled: !_codeSent,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _codeSent
                ? Padding(
                    key: const ValueKey('code-field'),
                    padding: const EdgeInsets.only(top: 16),
                    child: _buildStyledTextField(
                      controller: _codeController,
                      labelText: strings['enter_code']!,
                      icon: Icons.lock_outline_rounded,
                      required: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-code-field')),
          ),
          const SizedBox(height: 28),
          _buildPrimaryButton(
            label: _codeSent ? strings['verify_code']! : strings['send_code']!,
            icon: _codeSent ? Icons.verified_rounded : Icons.sms_outlined,
            onPressed: _loading
                ? null
                : (_codeSent ? _handleVerifyCode : _handleSendCode),
          ),
          if (_codeSent)
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _loading ? null : _handleSendCode,
                    child: Text(
                      strings['resend_code']!,
                      style: const TextStyle(
                        color: Color(0xFF1976D2),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _codeSent = false),
                    child: Text(
                      strings['edit_phone']!,
                      style: const TextStyle(
                        color: Color(0xFF1976D2),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileStep(
    Map<String, String> strings, {
    required bool compact,
  }) {
    return _buildStepCard(
      compact: compact,
      icon: Icons.person_add_rounded,
      title: strings['profile_card_title']!,
      subtitle: strings['profile_card_subtitle']!,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildImagePicker(),
            const SizedBox(height: 32),
            _buildStyledTextField(
              controller: _nameController,
              labelText: strings['name_label']!,
              icon: Icons.person_outline,
              required: true,
              validator: (v) => v!.isEmpty ? strings['req'] : null,
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _emailController,
              labelText: strings['email_label']!,
              icon: Icons.email_outlined,
              required: true,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return strings['req'];
                final isValid = RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(email);
                return isValid
                    ? null
                    : (strings['email_invalid'] ?? 'Enter a valid email');
              },
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _passwordController,
              labelText: strings['password_label'] ?? 'Password',
              icon: Icons.lock_outline_rounded,
              required: true,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
              validator: (value) {
                if ((value ?? '').length < 6) {
                  return strings['password_min_error'] ??
                      'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _confirmPasswordController,
              labelText:
                  strings['confirm_password_label'] ?? 'Confirm Password',
              icon: Icons.lock_reset_rounded,
              required: true,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return strings['password_match_error'] ??
                      'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _phoneController,
              labelText: strings['phone_label']!,
              icon: Icons.phone_iphone_rounded,
              required: true,
              keyboardType: TextInputType.phone,
              hintText: strings['phone_hint'],
              validator: (value) {
                final phone = _normalizePhone(value ?? '');
                final isValid = RegExp(r'^\+9725\d{8}$').hasMatch(phone);
                return isValid ? null : strings['invalid_phone'];
              },
            ),
            const SizedBox(height: 16),
            _buildLocationSelectionSection(strings),
            const SizedBox(height: 24),
            _buildSpokenLanguagesSelector(strings),
            const SizedBox(height: 24),
            _buildTypeSelector(strings),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _userType == UserType.worker
                  ? Column(
                      key: const ValueKey('worker-fields'),
                      children: [
                        const SizedBox(height: 24),
                        _buildWorkRadiusSelector(strings),
                        const SizedBox(height: 24),
                        _buildScheduleSection(strings),
                        const SizedBox(height: 24),
                        _buildMultiSelectProfessions(strings),
                        const SizedBox(height: 16),
                        _buildStyledTextField(
                          controller: _altPhoneController,
                          labelText: strings['alt_phone']!,
                          icon: Icons.phone_android_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        _buildStyledTextField(
                          controller: _descriptionController,
                          labelText: strings['desc_label']!,
                          helperText: strings['desc_helper']!,
                          icon: Icons.description_outlined,
                          required: true,
                          maxLines: 3,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? strings['req']
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => _openDescriptionAssistant(strings),
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: Text(strings['desc_generate_button']!),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF1976D2),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('customer-fields')),
            ),
            const SizedBox(height: 24),
            _buildPolicyCheckbox(strings),
            const SizedBox(height: 32),
            _buildPrimaryButton(
              label: _userType == UserType.worker
                  ? strings['pay']!
                  : strings['finish']!,
              icon: _userType == UserType.worker
                  ? Icons.workspace_premium_outlined
                  : Icons.arrow_forward_rounded,
              onPressed: _submitProfile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required bool compact,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? leading,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 24 : 38),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(compact ? 28 : 34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 48,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Align(alignment: AlignmentDirectional.centerStart, child: leading),
            const SizedBox(height: 8),
          ],
          _buildLogoMark(icon),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF070B18),
              fontSize: compact ? 31 : 36,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }

  Widget _buildLogoMark(IconData icon) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 34),
    );
  }

  Widget _buildBackButton(Map<String, String> strings, bool isRtl) {
    return TextButton.icon(
      onPressed: () => setState(() => _currentStep = SignUpStep.profile),
      icon: Icon(
        isRtl
            ? Icons.arrow_forward_ios_rounded
            : Icons.arrow_back_ios_new_rounded,
        size: 16,
      ),
      label: Text(strings['edit_phone']!),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF1976D2),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF8ABCEA),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.45),
        child: const Center(
          child: SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              color: Color(0xFF1976D2),
              strokeWidth: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1976D2).withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 55,
              backgroundColor: Colors.grey[100],
              backgroundImage: _image != null ? FileImage(_image!) : null,
              child: _image == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 50,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCheckbox(Map<String, String> strings) {
    return Row(
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _agreedToPolicy,
            onChanged: (v) => setState(() => _agreedToPolicy = v!),
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF1976D2);
              }
              return Colors.white;
            }),
            side: const BorderSide(color: Color(0xFFDCE5EE)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              children: [
                TextSpan(text: strings['agree_prefix']!),
                TextSpan(
                  text: strings['terms_link']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsOfServicePage(),
                        ),
                      );
                    },
                ),
                TextSpan(text: strings['and']!),
                TextSpan(
                  text: strings['privacy_link']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      );
                    },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSelectionSection(Map<String, String> strings) {
    final townController = TextEditingController(text: _selectedTown ?? '');
    return Column(
      children: [
        _buildStyledTextField(
          controller: townController,
          labelText: strings['town_label']!,
          icon: Icons.location_on_outlined,
          required: true,
          readOnly: true,
          onTap: _openMapPicker,
          validator: (v) => (v == null || v.isEmpty) ? strings['req'] : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location, size: 16),
                label: Text(
                  strings['current_loc']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(
                  strings['pick_map']!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.5),
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
    );
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPicker(initialCenter: _workCenter),
      ),
    );
    if (result != null && result is LatLng) {
      setState(() {
        _workCenter = result;
      });
      _updateTownFromLocation(result);
    }
  }

  Widget _buildWorkRadiusSelector(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radar_rounded,
                color: Color(0xFF1976D2),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                strings['work_radius']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            strings['work_radius_help']!,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _disableWorkRadius,
            activeThumbColor: const Color(0xFF1976D2),
            activeTrackColor: const Color(0xFFB9D9F6),
            title: Text(
              strings['disable_radius']!,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _disableWorkRadius = value;
                if (_disableWorkRadius) {
                  if (_workRadius > 0) {
                    _savedWorkRadius = _workRadius;
                  }
                  _workRadius = 0;
                } else {
                  _workRadius = _savedWorkRadius > 0
                      ? _savedWorkRadius
                      : 15000.0;
                }
              });
            },
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                strings['radius_val']!.replaceFirst(
                  '{val}',
                  (_workRadius / 1000).toStringAsFixed(1),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
              TextButton.icon(
                onPressed: _disableWorkRadius
                    ? null
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MapRadiusPicker(
                              initialCenter: _workCenter,
                              initialRadius: _workRadius,
                            ),
                          ),
                        );
                        if (result != null) {
                          setState(() {
                            _workCenter = result['center'];
                            _workRadius = result['radius'];
                            if (_workRadius > 0) {
                              _savedWorkRadius = _workRadius;
                            }
                          });
                          if (_workCenter != null) {
                            _updateTownFromLocation(_workCenter!);
                          }
                        }
                      },
                icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                label: Text(strings['select_radius']!),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(Map<String, String> strings) {
    final dayNames = _parseDayNames(strings['days']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hideSchedule,
            activeThumbColor: const Color(0xFF1976D2),
            activeTrackColor: const Color(0xFFB9D9F6),
            title: Text(
              strings['hide_schedule']!,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            onChanged: (value) => setState(() => _hideSchedule = value),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.schedule_rounded,
              color: Color(0xFF1976D2),
            ),
            title: Text(
              strings['working_hours']!,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            subtitle: Text(
              '${strings['available_from']!} ${_displayTime(_workingHoursFrom)}   ${strings['available_to']!} ${_displayTime(_workingHoursTo)}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await _pickWorkingHour(isStart: true);
              if (!mounted) return;
              await _pickWorkingHour(isStart: false);
            },
          ),
          const SizedBox(height: 8),
          Text(
            strings['select_off_days']!,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              final dayNum = _displayWeekdayOrder[index];
              final isOff = _disabledDays.contains(dayNum);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isOff) {
                      _disabledDays.remove(dayNum);
                    } else {
                      _disabledDays.add(dayNum);
                    }
                  });
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isOff
                        ? Colors.red.withValues(alpha: 0.1)
                        : const Color(0xFF1976D2).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isOff ? Colors.red : const Color(0xFF1976D2),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      dayNames[index],
                      style: TextStyle(
                        color: isOff ? Colors.red : const Color(0xFF1976D2),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  List<String> _parseDayNames(String? rawDays) {
    final fallback = const ['1', '2', '3', '4', '5', '6', '7'];
    final parsed = (rawDays ?? '')
        .split(RegExp(r'[,،，፣]'))
        .map((day) => day.trim())
        .where((day) => day.isNotEmpty)
        .toList();

    if (parsed.length >= 7) {
      return parsed.take(7).toList();
    }

    return fallback;
  }

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final previewLabels = _selectedProfessions
        .take(3)
        .map((profession) => _labelForStoredProfession(profession, localeCode))
        .toList();
    final subtitle = _selectedProfessions.isEmpty
        ? strings['search_hint']!
        : previewLabels.join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openProfessionSelector(strings),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _selectedProfessions.isEmpty
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF1976D2).withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.work_outline_rounded,
                    color: Color(0xFF1976D2),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings['professions']!,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _selectedProfessions.isEmpty
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF475569),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    '${_selectedProfessions.length}',
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
        if (_selectedProfessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedProfessions
                .map(
                  (prof) => Chip(
                    label: Text(
                      _labelForStoredProfession(prof, localeCode),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    backgroundColor: const Color(
                      0xFF1976D2,
                    ).withValues(alpha: 0.1),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () =>
                        setState(() => _selectedProfessions.remove(prof)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSpokenLanguagesSelector(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;

    return FormField<List<String>>(
      initialValue: _selectedSpokenLanguages,
      validator: (_) => _selectedSpokenLanguages.isEmpty
          ? strings['spoken_languages_required']
          : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.language_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              Text(
                strings['spoken_languages']!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _spokenLanguageOptions.map((language) {
              final selected = _selectedSpokenLanguages.contains(language);
              return FilterChip(
                label: Text(_spokenLanguageLabel(language, localeCode)),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedSpokenLanguages.add(language);
                    } else {
                      _selectedSpokenLanguages.remove(language);
                    }
                  });
                  field.didChange(_selectedSpokenLanguages);
                },
                selectedColor: const Color(0xFF1976D2).withValues(alpha: 0.14),
                checkmarkColor: const Color(0xFF1976D2),
                backgroundColor: const Color(0xFFF8FAFC),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF1976D2)
                      : const Color(0xFFE2E8F0),
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xFF0F4C9A)
                      : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          if (field.hasError) ...[
            const SizedBox(height: 8),
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  String _spokenLanguageLabel(String language, String localeCode) {
    const labels = {
      'Hebrew': {
        'en': 'Hebrew',
        'he': 'עברית',
        'ar': 'العبرية',
        'ru': 'Иврит',
        'am': 'ዕብራይስጥ',
      },
      'Arabic': {
        'en': 'Arabic',
        'he': 'ערבית',
        'ar': 'العربية',
        'ru': 'Арабский',
        'am': 'አረብኛ',
      },
      'English': {
        'en': 'English',
        'he': 'אנגלית',
        'ar': 'الإنجليزية',
        'ru': 'Английский',
        'am': 'እንግሊዝኛ',
      },
      'Russian': {
        'en': 'Russian',
        'he': 'רוסית',
        'ar': 'الروسية',
        'ru': 'Русский',
        'am': 'ሩሲኛ',
      },
      'Amharic': {
        'en': 'Amharic',
        'he': 'אמהרית',
        'ar': 'الأمهرية',
        'ru': 'Амхарский',
        'am': 'አማርኛ',
      },
    };

    return labels[language]?[localeCode] ?? labels[language]?['en'] ?? language;
  }

  Widget _buildTypeSelector(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings['user_type']!,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTypeButton(strings['normal']!, UserType.normal),
              ),
              Expanded(
                child: _buildTypeButton(strings['pro']!, UserType.worker),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeButton(String label, UserType type) {
    final isSelected = _userType == type;
    return GestureDetector(
      onTap: () => _handleUserTypeSelection(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? const Color(0xFF1976D2) : Colors.grey[600],
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _handleUserTypeSelection(UserType type) async {
    if (type == UserType.worker && kIsWeb) {
      await _openWorkerStoreListing();
      return;
    }

    if (!mounted) return;
    setState(() => _userType = type);
  }

  Future<void> _openWorkerStoreListing() async {
    final targetUri = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => _appleStoreWorkerAppUri,
      _ => _googlePlayWorkerAppUri,
    };

    final launched = await launchUrl(
      targetUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the store right now. Please try again.',
          ),
        ),
      );
    }
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? hintText,
    String? helperText,
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
    TextAlign textAlign = TextAlign.start,
    ValueChanged<String>? onChanged,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRequiredLabel(labelText, required: required),
        const SizedBox(height: 9),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          onChanged: onChanged,
          focusNode: focusNode,
          textAlign: textAlign,
          obscureText: obscureText,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 21),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: enabled
                ? const Color(0xFFF9FAFB)
                : const Color(0xFFEFF4FA),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF1976D2),
                width: 1.4,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE11D48)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFFE11D48),
                width: 1.4,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildRequiredLabel(String label, {bool required = false}) {
    if (!required) {
      return Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: Color(0xFF374151),
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: Color(0xFF374151),
        ),
        children: [
          TextSpan(text: label),
          const TextSpan(
            text: ' *',
            style: TextStyle(
              color: Color(0xFFE11D48),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignUpFeature {
  const _SignUpFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _SignUpBackgroundPainter extends CustomPainter {
  const _SignUpBackgroundPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final eased = Curves.easeInOut.transform(progress);
    final begin = Alignment.lerp(Alignment.topLeft, Alignment.topRight, eased)!;
    final end = Alignment.lerp(
      Alignment.bottomRight,
      Alignment.bottomLeft,
      eased,
    )!;

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: const [
          Color(0xFFFDFEFF),
          Color(0xFFEAF5FF),
          Color(0xFFF7FBFF),
          Color(0xFFE3F8FF),
        ],
        stops: const [0, 0.38, 0.68, 1],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final width = size.width;
    final height = size.height;
    final phase = progress * math.pi * 2;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(120, size.shortestSide * 0.18)
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.055)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 54);
    final path = Path()
      ..moveTo(-width * 0.2, height * (0.22 + math.sin(phase) * 0.03))
      ..cubicTo(
        width * 0.24,
        height * (0.02 + math.cos(phase) * 0.04),
        width * 0.58,
        height * (0.54 + math.sin(phase) * 0.03),
        width * 1.2,
        height * (0.25 + math.cos(phase) * 0.03),
      );
    canvas.drawPath(path, highlightPaint);

    final lowerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(90, size.shortestSide * 0.13)
      ..color = const Color(0xFF62D6E8).withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46);
    final lowerPath = Path()
      ..moveTo(width * 0.36, height * 1.12)
      ..cubicTo(
        width * (0.46 + math.sin(phase) * 0.04),
        height * 0.78,
        width * (0.72 + math.cos(phase) * 0.03),
        height * 0.95,
        width * 1.16,
        height * (0.65 + math.sin(phase) * 0.04),
      );
    canvas.drawPath(lowerPath, lowerPaint);
  }

  @override
  bool shouldRepaint(covariant _SignUpBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
