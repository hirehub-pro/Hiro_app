import 'dart:io';
import 'dart:math' as math;

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
  static const List<int> _displayWeekdayOrder = [7, 1, 2, 3, 4, 5, 6];
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _descriptionController = TextEditingController();

  TextEditingController? _professionsSearchController;

  late SignUpStep _currentStep;
  late UserType _userType;

  String? _selectedTown;
  List<String> _selectedProfessions = [];
  List<Map<String, dynamic>> _professionItems = [];

  bool _loading = false;
  bool _autoCompletingFromPaidWorker = false;
  bool _agreedToPolicy = false;
  bool _codeSent = false;
  String _verificationId = "";
  File? _image;
  final ImagePicker _picker = ImagePicker();
  DateTime? _dateOfBirth;

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
        labelText: label,
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
  double _workRadius = 5000.0;
  bool _hideSchedule = false;
  List<int> _disabledDays = [];
  TimeOfDay _workingHoursFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _workingHoursTo = const TimeOfDay(hour: 16, minute: 0);

  @override
  void initState() {
    super.initState();
    _ensureAnimationControllers();

    _currentStep = widget.startAtStep == 1
        ? SignUpStep.phone
        : SignUpStep.profile;
    _image = widget.pendingWorkerImage;

    if (widget.pendingWorkerData != null) {
      _userType = UserType.worker;
      _nameController.text = widget.pendingWorkerData!['name'] ?? "";
      _emailController.text = widget.pendingWorkerData!['email'] ?? "";
      _selectedTown = widget.pendingWorkerData!['town'];
      _selectedProfessions = List<String>.from(
        widget.pendingWorkerData!['professions'] ?? [],
      ).map(ProfessionLocalization.toCanonical).toList();
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
      _dateOfBirth = _parseDateOfBirth(
        widget.pendingWorkerData!['dateOfBirth'],
      );
      if (_dateOfBirth != null) {
        _dobController.text = _formatDate(_dateOfBirth!);
      }
      _phoneController.text =
          widget.pendingWorkerData!['phone'] ??
          (FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
      _agreedToPolicy = true;
    } else {
      _userType = UserType.normal;
    }

    _loadProfessionItems();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryFinalizePaidWorkerRegistrationAfterSubscription();
    });
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

  String _labelForStoredProfession(String profession, String localeCode) {
    final item = _findProfessionItem(profession);
    if (item != null) {
      return _professionLabel(item, localeCode);
    }
    return ProfessionLocalization.toLocalized(profession, localeCode);
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
    _dobController.dispose();
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
          'email_label': 'אימייל (אופציונלי)',
          'dob_label': 'תאריך לידה',
          'dob_hint': 'בחר תאריך לידה',
          'dob_required': 'יש לבחור תאריך לידה',
          'town_label': 'עיר',
          'user_type': 'סוג חשבון',
          'normal': 'לקוח',
          'pro': 'בעל מקצוע',
          'professions': 'בחר מקצועות',
          'alt_phone': 'טלפון נוסף (אופציונלי)',
          'desc_label': 'ספר על עצמך',
          'desc_helper':
              'כתוב בקצרה מה הניסיון שלך, באילו עבודות אתה מתמחה, ואיזה שירות אתה נותן.',
          'desc_generate_button': 'יצירה אוטומטית',
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
          'hide_schedule': 'הסתר לוח זמנים מאחרים',
          'working_hours': 'שעות עבודה',
          'available_from': 'זמין מ-',
          'available_to': 'זמין עד',
          'select_off_days': 'בחר ימי חופש קבועים',
          'days': 'א,ב,ג,ד,ה,ו,ש',
          'radius_val': 'רדיוס: {val} ק"מ',
          'select_radius': 'בחר רדיוס על המפה',
          'edit_phone': 'ערוך מספר טלפון',
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
          'email_label': 'Email (Optional)',
          'dob_label': 'Date of Birth',
          'dob_hint': 'Select date of birth',
          'dob_required': 'Date of birth is required',
          'town_label': 'City',
          'user_type': 'User Type',
          'normal': 'Client',
          'pro': 'Professional',
          'professions': 'Select Professions',
          'alt_phone': 'Alt Phone (Optional)',
          'desc_label': 'Description',
          'desc_helper':
              'Write a short summary of your experience, specialties, and the service you provide.',
          'desc_generate_button': 'Generate for me',
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
          'hide_schedule': 'Hide schedule from others',
          'working_hours': 'Working Hours',
          'available_from': 'Available from',
          'available_to': 'Available to',
          'select_off_days': 'Select fixed days off',
          'days': 'Su,Mo,Tu,We,Th,Fr,Sa',
          'radius_val': 'Radius: {val} km',
          'select_radius': 'Select radius on Map',
          'edit_phone': 'Edit Phone Number',
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

  DateTime? _parseDateOfBirth(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth = DateTime(picked.year, picked.month, picked.day);
      _dobController.text = _formatDate(_dateOfBirth!);
    });
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
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _onPhoneVerifiedAndSignedIn();
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("SMS failed: ${e.message}")));
          }
        },
        codeSent: (verificationId, resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _codeSent = true;
              _loading = false;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Auth Error: $e")));
      }
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
      'dateOfBirth': _dateOfBirth != null
          ? Timestamp.fromDate(_dateOfBirth!)
          : null,
      'phone': _normalizePhone(_phoneController.text.trim()),
      'town': _selectedTown,
      'role': 'worker',
      'isSubscribed': false,
      'subscriptionStatus': 'inactive',
      'subscriptionCanceled': false,
      'professions': _selectedProfessions,
      'optionalPhone': _altPhoneController.text.trim(),
      'description': _descriptionController.text.trim(),
      'workRadius': _workRadius,
      'workCenterLat': _workCenter?.latitude,
      'workCenterLng': _workCenter?.longitude,
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

  Future<void> _onPhoneVerifiedAndSignedIn() async {
    if (_userType == UserType.worker &&
        !SubscriptionAccessService.isEntitledSubscriptionStatus(
          widget.pendingWorkerData?['subscriptionStatus']?.toString(),
        )) {
      // Persist all entered data immediately after phone verification,
      // then continue the Pro subscription step.
      await _commitUserDataToDatabase(navigateToHome: false);
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
    setState(() => _loading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
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
      List<Placemark> placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        String? town =
            placemarks.first.locality ?? placemarks.first.subLocality;
        if (town != null && town.isNotEmpty) {
          setState(() => _selectedTown = town);
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _commitUserDataToDatabase({bool navigateToHome = true}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
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
        'dateOfBirth': _dateOfBirth != null
            ? Timestamp.fromDate(_dateOfBirth!)
            : null,
        'phone': _normalizePhone(_phoneController.text.trim()),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'profileImageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'role': _userType == UserType.worker ? 'worker' : 'customer',
      };

      if (_userType == UserType.worker) {
        final bool hasActiveSubscriptionFromPending =
            SubscriptionAccessService.isEntitledSubscriptionStatus(
              widget.pendingWorkerData?['subscriptionStatus']?.toString(),
            );
        final DateTime now = DateTime.now();
        final DateTime defaultExpiry = now.add(const Duration(days: 30));
        final DateTime? pendingDate = DateTime.tryParse(
          widget.pendingWorkerData?['subscriptionDate']?.toString() ?? '',
        );
        final DateTime? pendingExpiry = DateTime.tryParse(
          widget.pendingWorkerData?['subscriptionExpiresAt']?.toString() ?? '',
        );

        userData.addAll({
          'professions': _selectedProfessions,
          'optionalPhone': _altPhoneController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isSubscribed': hasActiveSubscriptionFromPending,
          'subscriptionStatus': hasActiveSubscriptionFromPending
              ? 'active'
              : 'inactive',
          'subscriptionCanceled': false,
          'subscriptionProductId':
              widget.pendingWorkerData?['subscriptionProductId'],
          'subscriptionPlatform':
              widget.pendingWorkerData?['subscriptionPlatform'],
          'subscriptionPurchaseId':
              widget.pendingWorkerData?['subscriptionPurchaseId'],
          'subscriptionPurchaseToken':
              widget.pendingWorkerData?['subscriptionPurchaseToken'],
          'subscriptionTransactionDate':
              widget.pendingWorkerData?['subscriptionTransactionDate'],
          'workRadius': _workRadius,
          'workCenterLat': _workCenter?.latitude,
          'workCenterLng': _workCenter?.longitude,
          'hideSchedule': _hideSchedule,
          'disabledDays': _disabledDays,
          'subscriptionDate': hasActiveSubscriptionFromPending
              ? Timestamp.fromDate(pendingDate ?? now)
              : null,
          'subscriptionExpiresAt': hasActiveSubscriptionFromPending
              ? Timestamp.fromDate(pendingExpiry ?? defaultExpiry)
              : null,
          'avgRating': 0.0,
          'reviewCount': 0,
        });
      }

      final userRef = firestore.collection('users').doc(user.uid);
      final statsRef = firestore.collection('metadata').doc('stats');
      final systemRef = firestore.collection('metadata').doc('system');
      final targetRole = (userData['role'] ?? 'customer')
          .toString()
          .toLowerCase();

      await firestore.runTransaction((tx) async {
        final existingUserSnap = await tx.get(userRef);
        final existingRole = (existingUserSnap.data()?['role'] ?? '')
            .toString()
            .toLowerCase();

        tx.set(userRef, userData, SetOptions(merge: true));

        final statsUpdates = <String, dynamic>{};
        final systemUpdates = <String, dynamic>{};
        if (!existingUserSnap.exists || existingRole.isEmpty) {
          if (targetRole == 'worker') {
            statsUpdates['totalWorkers'] = FieldValue.increment(1);
            systemUpdates['workersCount'] = FieldValue.increment(1);
          } else if (targetRole == 'customer') {
            statsUpdates['totalCustomers'] = FieldValue.increment(1);
          }
        } else if (existingRole != targetRole) {
          if (existingRole == 'worker') {
            statsUpdates['totalWorkers'] = FieldValue.increment(-1);
            systemUpdates['workersCount'] = FieldValue.increment(-1);
          } else if (existingRole == 'customer') {
            statsUpdates['totalCustomers'] = FieldValue.increment(-1);
          }

          if (targetRole == 'worker') {
            statsUpdates['totalWorkers'] = FieldValue.increment(1);
            systemUpdates['workersCount'] = FieldValue.increment(1);
          } else if (targetRole == 'customer') {
            statsUpdates['totalCustomers'] = FieldValue.increment(1);
          }
        }

        if (statsUpdates.isNotEmpty) {
          statsUpdates['updatedAt'] = FieldValue.serverTimestamp();
          tx.set(statsRef, statsUpdates, SetOptions(merge: true));
        }
        if (systemUpdates.isNotEmpty) {
          systemUpdates['updatedAt'] = FieldValue.serverTimestamp();
          tx.set(systemRef, systemUpdates, SetOptions(merge: true));
        }
      });
      if (_userType == UserType.worker) {
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
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Database Error: $e")));
      }
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

    if (_userType == UserType.worker) {
      setState(() {
        _currentStep = SignUpStep.phone;
      });
    } else {
      setState(() => _currentStep = SignUpStep.phone);
    }
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
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
        ],
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
            keyboardType: TextInputType.phone,
            hintText: 'e.g. 0501234567',
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
              child: TextButton(
                onPressed: () => setState(() => _codeSent = false),
                child: Text(
                  strings['edit_phone']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
              validator: (v) => v!.isEmpty ? strings['req'] : null,
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _emailController,
              labelText: strings['email_label']!,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildStyledTextField(
              controller: _dobController,
              labelText: strings['dob_label']!,
              hintText: strings['dob_hint']!,
              icon: Icons.cake_outlined,
              readOnly: true,
              onTap: _pickDateOfBirth,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? strings['dob_required']
                  : null,
            ),
            const SizedBox(height: 16),
            _buildLocationSelectionSection(strings),
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
                onPressed: () async {
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
    final dayNames = strings['days']!.split(',');
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

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final options = _professionItems.isNotEmpty
        ? _professionItems
        : ProfessionLocalization.canonicalProfessions
              .map((profession) => <String, dynamic>{'en': profession})
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              final query = textEditingValue.text.trim().toLowerCase();
              final matchingItems = query.isEmpty
                  ? options
                  : options.where(
                      (item) => _professionSearchTerms(
                        item,
                      ).any((term) => term.contains(query)),
                    );
              return matchingItems
                  .map((item) => _professionLabel(item, localeCode))
                  .toSet()
                  .toList();
            },
            onSelected: (selection) {
              final matchedItem = _findProfessionItem(selection);
              final canonical = matchedItem != null
                  ? _professionCanonicalValue(matchedItem)
                  : ProfessionLocalization.toCanonical(selection);
              setState(() {
                if (!_selectedProfessions.contains(canonical)) {
                  _selectedProfessions.add(canonical);
                }
              });
              _professionsSearchController?.clear();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  _professionsSearchController = controller;
                  return _buildStyledTextField(
                    controller: controller,
                    labelText: strings['professions']!,
                    icon: Icons.work_outline,
                    focusNode: focusNode,
                    hintText: strings['search_hint'],
                  );
                },
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
      onTap: () => setState(() => _userType = type),
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

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 9),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          readOnly: readOnly,
          onTap: onTap,
          focusNode: focusNode,
          textAlign: textAlign,
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
