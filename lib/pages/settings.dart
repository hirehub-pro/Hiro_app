import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/services/auth_service.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/sign_in.dart';
import 'package:untitled1/pages/about.dart';
import 'package:untitled1/pages/account_settings.dart';
import 'package:untitled1/pages/accounting_export_page.dart';
import 'package:untitled1/pages/help_page.dart';
import 'package:untitled1/pages/privacy_policy_page.dart';
import 'package:untitled1/pages/reports_page.dart';
import 'package:untitled1/pages/terms_of_service_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  static const List<int> _displayWeekdayOrder = [1, 2, 3, 4, 5, 6, 7];
  bool _notificationsEnabled = true;
  bool _hideSchedule = false;
  List<int> _disabledDays = []; // 1 = Sunday, 7 = Saturday
  TimeOfDay _workingHoursFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _workingHoursTo = const TimeOfDay(hour: 16, minute: 0);
  bool _isLoadingSettings = true;
  Map<String, dynamic>? _userData;
  String _userRole = "customer";
  bool _isGeneratingUniformFiles = false;

  bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncNotificationPermissionState();
    }
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _isLoadingSettings = false);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('users').doc(user.uid).get();
      final publicProfileDoc = await firestore
          .collection('publicWorkerProfiles')
          .doc(user.uid)
          .get();
      final scheduleDoc = await firestore
          .collection('publicWorkerProfiles')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final publicData = publicProfileDoc.data() ?? <String, dynamic>{};
        final mergedData = <String, dynamic>{...data};
        if ((data['role'] ?? '').toString().toLowerCase() == 'worker') {
          const publicFields = {
            'hideSchedule',
            'description',
            'email',
            'lat',
            'lng',
            'name',
            'optionalPhone',
            'phone',
            'professions',
            'profileImageUrl',
            'spokenLanguages',
            'town',
            'workRadius',
          };
          mergedData.removeWhere((key, _) => publicFields.contains(key));
          mergedData.addAll(publicData);
        }
        final scheduleData = scheduleDoc.data();
        final defaultWorkingHours =
            scheduleData?['defaultWorkingHours'] as Map<String, dynamic>?;
        final notificationsAllowed = await _isNotificationPermissionGranted();
        if (!mounted) return;

        setState(() {
          _userData = mergedData;
          _userRole = data['role'] ?? 'customer';
          _hideSchedule = scheduleData?['hideSchedule'] ?? false;
          _disabledDays = List<int>.from(
            scheduleData?['disabledDays'] ?? const <int>[],
          );
          _workingHoursFrom = _parseStoredTime(
            defaultWorkingHours?['from']?.toString(),
            fallback: const TimeOfDay(hour: 8, minute: 0),
          );
          _workingHoursTo = _parseStoredTime(
            defaultWorkingHours?['to']?.toString(),
            fallback: const TimeOfDay(hour: 16, minute: 0),
          );
          _notificationsEnabled = notificationsAllowed;
          _isLoadingSettings = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoadingSettings = false);
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
      if (!mounted) return;
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    if (key == 'disabledDays') {
      await firestore
          .collection('publicWorkerProfiles')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .set({key: value}, SetOptions(merge: true));
      return;
    }

    if (key == 'hideSchedule') {
      await firestore
          .collection('publicWorkerProfiles')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .set({
            key: value,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      return;
    }

    await firestore.collection('users').doc(user.uid).update({key: value});
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

  Future<void> _updateWorkingHours() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('publicWorkerProfiles')
        .doc(user.uid)
        .collection('Schedule')
        .doc('info')
        .set({
          'defaultWorkingHours': {
            'from': _formatStoredTime(_workingHoursFrom),
            'to': _formatStoredTime(_workingHoursTo),
          },
        }, SetOptions(merge: true));
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
    await _updateWorkingHours();
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final isAlreadyGranted = await _isNotificationPermissionGranted();
      if (!mounted) return;

      if (isAlreadyGranted) {
        setState(() => _notificationsEnabled = true);
        return;
      }

      final isGranted = await _requestNotificationPermission();
      if (!mounted) return;

      if (isGranted) {
        setState(() => _notificationsEnabled = true);
      } else if (await _isNotificationPermissionBlocked()) {
        _showPermissionDialog();
        setState(() => _notificationsEnabled = false);
      } else {
        setState(() => _notificationsEnabled = false);
      }
    } else {
      final isGranted = await _isNotificationPermissionGranted();
      if (!mounted) return;

      setState(() => _notificationsEnabled = isGranted);
      if (isGranted) {
        _showPermissionDialog(messageKey: 'permission_controlled_by_phone');
      }
    }
  }

  Future<bool> _requestNotificationPermission() async {
    if (kIsWeb) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    if (_isApplePlatform) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    if (_isAndroidPlatform) {
      final notificationsPlugin = FlutterLocalNotificationsPlugin();
      final androidPlugin = notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidPlugin?.requestNotificationsPermission();
      if (granted != null) return granted;
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> _isNotificationPermissionGranted() async {
    if (kIsWeb || _isApplePlatform) {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }

    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> _isNotificationPermissionBlocked() async {
    if (kIsWeb || _isApplePlatform) {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.denied;
    }

    final status = await Permission.notification.status;
    return status.isPermanentlyDenied;
  }

  Future<void> _syncNotificationPermissionState() async {
    final isGranted = await _isNotificationPermissionGranted();
    if (!mounted) return;

    setState(() => _notificationsEnabled = isGranted);
  }

  void _showPermissionDialog({String messageKey = 'permission_denied'}) {
    final strings = _getLocalizedStrings(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['notifications']!),
        content: Text(strings[messageKey]!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['cancel']!),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: Text(strings['settings']!),
          ),
        ],
      ),
    );
  }

  String _formatTaxAuthorityDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<bool> _ensureUniformTaxAuthorityConnection() async {
    final functions = FirebaseFunctions.instanceFor(region: 'me-west1');
    try {
      final status = await functions
          .httpsCallable('getUniformTaxAuthorityConnectionStatus')
          .call<Map<String, dynamic>>();
      if (status.data['connected'] == true) return true;

      final authorization = await functions
          .httpsCallable('createUniformTaxAuthorityAuthorizationUrl')
          .call<Map<String, dynamic>>();
      final uri = Uri.tryParse(
        authorization.data['authorizationUrl']?.toString() ?? '',
      );
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw StateError('The Tax Authority returned an invalid login link.');
      }
      var launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!launched) {
        throw StateError('Could not open the Tax Authority login.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete the Tax Authority authorization, then tap Export again.',
            ),
          ),
        );
      }
      return false;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'Tax Authority connection failed.');
    }
  }

  Future<Map<String, dynamic>> _waitForUniformTaxAuthorityStatus(
    String submissionId,
  ) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'me-west1',
    ).httpsCallable('getUniformTaxAuthoritySubmissionStatus');
    Map<String, dynamic> latest = {'status': 'processing'};
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final response = await callable.call<Map<String, dynamic>>({
        'submissionId': submissionId,
      });
      latest = response.data;
      final status = latest['status']?.toString();
      if (status == 'approved' || status == 'rejected') break;
    }
    return latest;
  }

  Future<DateTimeRange?> _pickExportDateRange() async {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
    );
  }

  Future<String?> _promptExportEmail() async {
    final initialEmail =
        (FirebaseAuth.instance.currentUser?.email ??
                _userData?['email']?.toString() ??
                '')
            .trim();
    var emailValue = initialEmail;
    String? validationMessage;
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';
    final title = isRtl ? 'שליחת קבצים במייל' : 'Email Export Files';
    final label = isRtl
        ? 'לאיזה אימייל לשלוח?'
        : 'Which email should receive the files?';
    final hint = isRtl ? 'name@example.com' : 'name@example.com';
    final invalid = isRtl
        ? 'יש להזין כתובת אימייל תקינה.'
        : 'Enter a valid email address.';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x260F172A),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1976D2,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.file_present_rounded,
                              color: Color(0xFF1976D2),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: initialEmail,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        onChanged: (value) {
                          emailValue = value;
                          if (validationMessage != null) {
                            setDialogState(() => validationMessage = null);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: hint,
                          errorText: validationMessage,
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
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
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1976D2),
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(isRtl ? 'ביטול' : 'Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () {
                                final email = emailValue.trim();
                                final isValid = RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(email);
                                if (!isValid) {
                                  setDialogState(
                                    () => validationMessage = invalid,
                                  );
                                  return;
                                }
                                Navigator.pop(dialogContext, email);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1976D2),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(isRtl ? 'המשך' : 'Continue'),
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
      },
    );
    return result;
  }

  Future<void> _generateWorkerUniformFiles() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isGeneratingUniformFiles) return;
    setState(() => _isGeneratingUniformFiles = true);

    ValueNotifier<_UniformExportProgress>? exportProgress;
    BuildContext? progressDialogContext;
    Future<void>? progressDialogFuture;

    try {
      final isConnected = await _ensureUniformTaxAuthorityConnection();
      if (!isConnected || !mounted) return;

      final recipientEmail = await _promptExportEmail();
      if (recipientEmail == null || !mounted) return;

      final selectedRange = await _pickExportDateRange();
      if (selectedRange == null || !mounted) return;

      exportProgress = ValueNotifier(
        const _UniformExportProgress(
          value: 0.05,
          status: 'Preparing your secure server export…',
        ),
      );
      progressDialogFuture = _showUniformExportProgressDialog(
        exportProgress,
        onDialogBuilt: (dialogContext) {
          progressDialogContext = dialogContext;
        },
      );
      await Future<void>.delayed(Duration.zero);

      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      final idToken = await refreshedUser?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        throw StateError('יש להתחבר מחדש כדי להפיק את קובצי הייצוא.');
      }

      exportProgress.value = const _UniformExportProgress(
        value: 0.2,
        status: 'Generating BKMVDATA and PDF reports on the server…',
      );
      final functions = FirebaseFunctions.instanceFor(region: 'me-west1');
      final generated = await functions
          .httpsCallable(
            'generateUniformExport',
            options: HttpsCallableOptions(timeout: Duration(minutes: 9)),
          )
          .call<Map<String, dynamic>>({
            'fromDate': _formatTaxAuthorityDate(selectedRange.start),
            'toDate': _formatTaxAuthorityDate(selectedRange.end),
            'recipientEmail': recipientEmail,
          });
      final exportId = generated.data['exportId']?.toString().trim();
      if (exportId == null || exportId.isEmpty) {
        throw StateError('The server did not return an export ID.');
      }

      exportProgress.value = const _UniformExportProgress(
        value: 0.75,
        status: 'Testing delivery to the Tax Authority sandbox…',
      );
      final authorityResponse = await functions
          .httpsCallable(
            'submitUniformFilesToTaxAuthority',
            options: HttpsCallableOptions(timeout: Duration(minutes: 5)),
          )
          .call<Map<String, dynamic>>({'exportId': exportId});
      final submissionId = authorityResponse.data['submissionId']?.toString();
      if (submissionId == null || submissionId.isEmpty) {
        throw StateError('The Tax Authority submission ID is missing.');
      }

      exportProgress.value = const _UniformExportProgress(
        value: 0.9,
        status: 'Checking the Tax Authority response…',
      );
      final authorityStatus = await _waitForUniformTaxAuthorityStatus(
        submissionId,
      );
      final authorityState =
          authorityStatus['status']?.toString() ?? 'processing';
      if (authorityState == 'rejected') {
        final files = authorityStatus['files'];
        String? reason;
        if (files is List) {
          for (final entry in files) {
            if (entry is Map) {
              final errorMessage = entry['errorMessage']?.toString().trim();
              final description = entry['description']?.toString().trim();
              final candidate = errorMessage != null && errorMessage.isNotEmpty
                  ? errorMessage
                  : description;
              if (candidate != null && candidate.isNotEmpty) {
                reason = candidate;
                break;
              }
            }
          }
        }
        throw StateError(
          reason == null
              ? 'The Tax Authority rejected the uniform files.'
              : 'The Tax Authority rejected the files: $reason',
        );
      }

      exportProgress.value = const _UniformExportProgress(
        value: 1,
        status: 'Your export is ready!',
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authorityState == 'approved'
                ? 'בדיקת השידור בסביבת הניסוי אושרה. עותק נשלח ל "$recipientEmail"'
                : 'בדיקת השידור התקבלה בסביבת הניסוי ומעובדת. עותק נשלח ל "$recipientEmail"',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'שליחת הקבצים לרשות המסים נכשלה.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      final dialogContext = progressDialogContext;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      if (progressDialogFuture != null) {
        await progressDialogFuture;
      }
      exportProgress?.dispose();
      if (mounted) {
        setState(() => _isGeneratingUniformFiles = false);
      }
    }
  }

  Future<void> _showUniformExportProgressDialog(
    ValueListenable<_UniformExportProgress> progress, {
    required ValueChanged<BuildContext> onDialogBuilt,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        onDialogBuilt(dialogContext);
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                child: ValueListenableBuilder<_UniformExportProgress>(
                  valueListenable: progress,
                  builder: (context, state, _) {
                    final percentage = (state.value * 100).round();
                    final isComplete = state.value >= 1;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: isComplete
                                ? const Color(0xFFE8F7EF)
                                : const Color(0xFFEAF3FF),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isComplete
                                ? Icons.check_rounded
                                : Icons.cloud_upload_rounded,
                            size: 32,
                            color: isComplete
                                ? const Color(0xFF168653)
                                : const Color(0xFF1976D2),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isComplete
                              ? 'Export complete'
                              : 'Generating BKMVDATA files',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            state.status,
                            key: ValueKey(state.status),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: state.value,
                            minHeight: 10,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isComplete
                                  ? const Color(0xFF168653)
                                  : const Color(0xFF1976D2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$percentage%',
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF4D58A)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Color(0xFF9A6700),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Please keep this page open until the export is finished.',
                                  style: TextStyle(
                                    color: Color(0xFF7A5200),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, String> _getLocalizedStrings(
    BuildContext context, {
    bool listen = true,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'הגדרות',
          'notifications': 'התראות',
          'language': 'שפה',
          'about': 'אודות',
          'account': 'חשבון',
          'privacy': 'מדיניות פרטיות',
          'terms': 'תנאי שימוש',
          'delete_account': 'מחיקת חשבון',
          'help': 'עזרה',
          'reports': 'דיווחים',
          'logout': 'התנתקות',
          'appearance': 'מראה',
          'schedule': 'לוח זמנים',
          'hide_schedule': 'הסתר לוח זמנים מאחרים',
          'work_days': 'ימי עבודה',
          'working_hours': 'שעות עבודה',
          'uniform_export_section': 'ייצוא נתונים',
          'uniform_export': 'ייצוא קובץ במבנה אחיד',
          'accounting_export': 'ייצוא להנה״ח חיצונית',
          'available_from': 'זמין מ-',
          'available_to': 'זמין עד',
          'select_off_days': 'בחר ימי חופש קבועים',
          'days': '1,2,3,4,5,6,7',
          'permission_denied':
              'התראות חסומות בהגדרות המכשיר. האם תרצה לפתוח את ההגדרות?',
          'permission_controlled_by_phone':
              'כדי לכבות התראות צריך לשנות את הרשאת ההתראות בהגדרות המכשיר.',
          'settings': 'הגדרות',
          'cancel': 'ביטול',
        };
      case 'ar':
        return {
          'title': 'الإعدادات',
          'notifications': 'الإشعارات',
          'language': 'اللغة',
          'about': 'حول',
          'account': 'الحساب',
          'privacy': 'سياسة الخصوصية',
          'terms': 'شروط الخدمة',
          'delete_account': 'حذف الحساب',
          'help': 'المساعدة',
          'reports': 'البلاغات',
          'logout': 'تسجيل الخروج',
          'appearance': 'المظهر',
          'schedule': 'الجدول الزمني',
          'hide_schedule': 'إخفاء الجدول عن الآخرين',
          'work_days': 'أيام العمل',
          'working_hours': 'ساعات العمل',
          'uniform_export_section': 'تصدير البيانات',
          'uniform_export': 'تصدير ملف موحّد',
          'accounting_export': 'التصدير إلى نظام محاسبة خارجي',
          'available_from': 'متاح من',
          'available_to': 'متاح حتى',
          'select_off_days': 'اختر أيام العطلة الثابتة',
          'days': '1,2,3,4,5,6,7',
          'permission_denied':
              'الإشعارات محظورة في إعدادات الجهاز. هل تريد فتح الإعدادات؟',
          'permission_controlled_by_phone':
              'لإيقاف الإشعارات، غيّر إذن الإشعارات من إعدادات الجهاز.',
          'settings': 'الإعدادات',
          'cancel': 'إلغاء',
        };
      case 'ru':
        return {
          'title': 'Настройки',
          'notifications': 'Уведомления',
          'language': 'Язык',
          'about': 'О приложении',
          'account': 'Аккаунт',
          'privacy': 'Политика конфиденциальности',
          'terms': 'Условия использования',
          'delete_account': 'Удалить аккаунт',
          'help': 'Помощь',
          'reports': 'Жалобы',
          'logout': 'Выйти',
          'appearance': 'Внешний вид',
          'schedule': 'Расписание',
          'hide_schedule': 'Скрыть расписание от других',
          'work_days': 'Рабочие дни',
          'working_hours': 'Рабочие часы',
          'uniform_export_section': 'Экспорт данных',
          'uniform_export': 'Экспорт файла в едином формате',
          'accounting_export': 'Экспорт во внешнюю бухгалтерскую систему',
          'available_from': 'Доступен с',
          'available_to': 'Доступен до',
          'select_off_days': 'Выберите постоянные выходные',
          'days': '1,2,3,4,5,6,7',
          'permission_denied':
              'Уведомления заблокированы в настройках устройства. Открыть настройки?',
          'permission_controlled_by_phone':
              'Чтобы выключить уведомления, измените разрешение уведомлений в настройках устройства.',
          'settings': 'Настройки',
          'cancel': 'Отмена',
        };
      case 'am':
        return {
          'title': 'ቅንብሮች',
          'notifications': 'ማሳወቂያዎች',
          'language': 'ቋንቋ',
          'about': 'ስለ መተግበሪያው',
          'account': 'መለያ',
          'privacy': 'የግላዊነት ፖሊሲ',
          'terms': 'የአጠቃቀም ውል',
          'delete_account': 'መለያ ሰርዝ',
          'help': 'እገዛ',
          'reports': 'ሪፖርቶች',
          'logout': 'ውጣ',
          'appearance': 'መልክ',
          'schedule': 'መርሃ ግብር',
          'hide_schedule': 'መርሃ ግብሩን ከሌሎች ደብቅ',
          'work_days': 'የስራ ቀናት',
          'working_hours': 'የስራ ሰዓቶች',
          'uniform_export_section': 'ውሂብ ወደ ውጭ ላክ',
          'uniform_export': 'ወጥ ቅርጸት ያለውን ፋይል ወደ ውጭ ላክ',
          'accounting_export': 'ወደ ውጫዊ የሂሳብ አያያዝ ስርዓት ላክ',
          'available_from': 'ዝግጁ ከ',
          'available_to': 'ዝግጁ እስከ',
          'select_off_days': 'ቋሚ የእረፍት ቀናትን ይምረጡ',
          'days': '1,2,3,4,5,6,7',
          'permission_denied': 'ማሳወቂያዎች በመሣሪያው ቅንብሮች ውስጥ ታግደዋል። ቅንብሮቹን ልክፈት?',
          'permission_controlled_by_phone':
              'ማሳወቂያዎችን ለማጥፋት በመሣሪያው ቅንብሮች ውስጥ የማሳወቂያ ፈቃዱን ይቀይሩ።',
          'settings': 'ቅንብሮች',
          'cancel': 'ሰርዝ',
        };
      default:
        return {
          'title': 'Settings',
          'notifications': 'Notifications',
          'language': 'Language',
          'about': 'About',
          'account': 'Account',
          'privacy': 'Privacy Policy',
          'terms': 'Terms of Service',
          'delete_account': 'Delete Account',
          'help': 'Help & Support',
          'reports': 'Reports',
          'logout': 'Logout',
          'appearance': 'Appearance',
          'schedule': 'Schedule',
          'hide_schedule': 'Hide schedule from others',
          'work_days': 'Working Days',
          'working_hours': 'Working Hours',
          'uniform_export_section': 'Export Data',
          'uniform_export': 'Export Uniform File',
          'accounting_export': 'Export to Accounting',
          'available_from': 'Available from',
          'available_to': 'Available to',
          'select_off_days': 'Select fixed days off',
          'days': '1,2,3,4,5,6,7',
          'permission_denied':
              'Notifications are blocked in system settings. Would you like to open settings?',
          'permission_controlled_by_phone':
              'To turn notifications off, change the notification permission in your phone settings.',
          'settings': 'Settings',
          'cancel': 'Cancel',
        };
    }
  }

  Future<void> _logout() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SignInPage()),
      (route) => false,
    );
  }

  void _goToAccountSettings() async {
    if (_userData == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountSettingsPage(userData: _userData!),
      ),
    );

    _loadSettings();
  }

  Future<void> _goToAccountingExport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const AccountingExportPage(),
      ),
    );
  }

  void _goToHelpPage() {
    if (_isApplePlatform) {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => const HelpPage()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HelpPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';

    if (_isApplePlatform) {
      return _buildIosSettings(context, strings, isRtl);
    } else {
      return _buildAndroidSettings(context, strings, isRtl);
    }
  }

  Widget _buildScheduleSection(Map<String, String> strings) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();
    if (_isLoadingSettings) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_userRole != 'worker') return const SizedBox.shrink();

    final dayNames = strings['days']!.split(',');

    return _buildGalaxySection(strings['schedule']!, [
      _buildGalaxySwitchTile(
        Icons.calendar_view_day_rounded,
        strings['hide_schedule']!,
        _hideSchedule,
        (v) {
          setState(() => _hideSchedule = v);
          _updateSetting('hideSchedule', v);
        },
      ),
      const Divider(height: 1, indent: 50),
      ListTile(
        leading: const Icon(Icons.schedule_rounded, color: Color(0xFF1976D2)),
        title: Text(
          strings['working_hours']!,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${strings['available_from']!} ${_displayTime(_workingHoursFrom)}   ${strings['available_to']!} ${_displayTime(_workingHoursTo)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () async {
          await _pickWorkingHour(isStart: true);
          if (!mounted) return;
          await _pickWorkingHour(isStart: false);
        },
      ),
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings['select_off_days']!,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    _updateSetting('disabledDays', _disabledDays);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isOff
                          ? Colors.red.withOpacity(0.1)
                          : const Color(0xFF1976D2).withOpacity(0.1),
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
      ),
    ]);
  }

  Widget _buildUniformExportSection(Map<String, String> strings, bool isRtl) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const SizedBox.shrink();
    if (_isLoadingSettings) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_userRole != 'worker') return const SizedBox.shrink();

    return _buildGalaxySection(strings['uniform_export_section']!, [
      ListTile(
        leading: Icon(
          Icons.file_present_rounded,
          color: _isGeneratingUniformFiles
              ? const Color(0xFF94A3B8)
              : const Color(0xFF1976D2),
        ),
        title: Text(
          strings['uniform_export']!,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: _isGeneratingUniformFiles ? const Color(0xFF94A3B8) : null,
          ),
        ),
        trailing: _isGeneratingUniformFiles
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: _isGeneratingUniformFiles ? null : _generateWorkerUniformFiles,
      ),
      ListTile(
        leading: const Icon(
          Icons.account_balance_rounded,
          color: Color(0xFF1976D2),
        ),
        title: Text(
          strings['accounting_export']!,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: _goToAccountingExport,
      ),
    ]);
  }

  Widget _buildAndroidSettings(
    BuildContext context,
    Map<String, String> strings,
    bool isRtl,
  ) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        body: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              expandedHeight: 180,
              backgroundColor: const Color(0xFFF2F2F7),
              elevation: 0,
              pinned: true,
              automaticallyImplyLeading: false,
              actions: [
                if (Navigator.of(context).canPop())
                  IconButton(
                    icon: const BackButtonIcon(),
                    onPressed: () => Navigator.maybePop(context),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  strings['title']!,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 24,
                  bottom: 16,
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildGalaxySection(strings['account']!, [
                        _buildGalaxyTile(
                          Icons.person_outline_rounded,
                          strings['account']!,
                          _goToAccountSettings,
                        ),
                        _buildGalaxyTile(
                          Icons.lock_outline_rounded,
                          strings['privacy']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyPage(),
                              ),
                            );
                          },
                        ),
                        _buildGalaxyTile(
                          Icons.description_outlined,
                          strings['terms']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TermsOfServicePage(),
                              ),
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildScheduleSection(strings),
                      const SizedBox(height: 16),
                      _buildUniformExportSection(strings, isRtl),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['notifications']!, [
                        _buildGalaxySwitchTile(
                          Icons.notifications_none_rounded,
                          strings['notifications']!,
                          _notificationsEnabled,
                          _toggleNotifications,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['language']!, [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: const Icon(
                            Icons.language_rounded,
                            color: Color(0xFF1976D2),
                          ),
                          title: Text(
                            strings['language']!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: const LanguageDropDown(),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildGalaxySection(strings['help']!, [
                        _buildGalaxyTile(
                          Icons.help_outline_rounded,
                          strings['help']!,
                          _goToHelpPage,
                        ),
                        _buildGalaxyTile(
                          Icons.report_problem_outlined,
                          strings['reports']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ReportsPage(),
                              ),
                            );
                          },
                        ),
                        _buildGalaxyTile(
                          Icons.info_outline_rounded,
                          strings['about']!,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AboutPage(),
                              ),
                            );
                          },
                        ),
                      ]),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _logout,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          child: Text(
                            strings['logout']!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalaxySection(String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF8E8E93),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildGalaxyTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF1976D2)),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, color: color),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildGalaxySwitchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFF1976D2).withOpacity(0.5),
        activeThumbColor: const Color(0xFF1976D2),
      ),
    );
  }

  Widget _buildIosSettings(
    BuildContext context,
    Map<String, String> strings,
    bool isRtl,
  ) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          middle: Text(strings['title']!),
          trailing: Navigator.of(context).canPop()
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => Navigator.maybePop(context),
                  child: Icon(
                    isRtl ? CupertinoIcons.forward : CupertinoIcons.back,
                  ),
                )
              : null,
          border: null,
        ),
        child: ListView(
          children: [
            CupertinoListSection.insetGrouped(
              header: Text(strings['account']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.person,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['account']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _goToAccountSettings,
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.lock,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['privacy']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    );
                  },
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.doc_text,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['terms']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const TermsOfServicePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            if (_userRole == 'worker')
              CupertinoListSection.insetGrouped(
                header: Text(strings['schedule']!),
                children: [
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.calendar,
                      color: CupertinoColors.systemIndigo,
                    ),
                    title: Text(strings['hide_schedule']!),
                    trailing: CupertinoSwitch(
                      value: _hideSchedule,
                      onChanged: (v) {
                        setState(() => _hideSchedule = v);
                        _updateSetting('hideSchedule', v);
                      },
                    ),
                  ),
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.time,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['working_hours']!),
                    subtitle: Text(
                      '${strings['available_from']!} ${_displayTime(_workingHoursFrom)}   ${strings['available_to']!} ${_displayTime(_workingHoursTo)}',
                    ),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () async {
                      await _pickWorkingHour(isStart: true);
                      if (!mounted) return;
                      await _pickWorkingHour(isStart: false);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            _updateSetting('disabledDays', _disabledDays);
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isOff
                                  ? CupertinoColors.systemRed.withValues(
                                      alpha: 0.1,
                                    )
                                  : CupertinoColors.systemBlue.withValues(
                                      alpha: 0.1,
                                    ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isOff
                                    ? CupertinoColors.systemRed
                                    : CupertinoColors.systemBlue,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                strings['days']!.split(',')[index],
                                style: TextStyle(
                                  color: isOff
                                      ? CupertinoColors.systemRed
                                      : CupertinoColors.systemBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            if (_userRole == 'worker')
              CupertinoListSection.insetGrouped(
                header: Text(strings['uniform_export_section']!),
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.doc_on_doc,
                      color: _isGeneratingUniformFiles
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['uniform_export']!),
                    trailing: _isGeneratingUniformFiles
                        ? const CupertinoActivityIndicator()
                        : const CupertinoListTileChevron(),
                    onTap: _isGeneratingUniformFiles
                        ? null
                        : _generateWorkerUniformFiles,
                  ),
                  CupertinoListTile(
                    leading: const Icon(
                      CupertinoIcons.building_2_fill,
                      color: CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['accounting_export']!),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _goToAccountingExport,
                  ),
                ],
              ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['notifications']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.bell,
                    color: CupertinoColors.systemRed,
                  ),
                  title: Text(strings['notifications']!),
                  trailing: CupertinoSwitch(
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['language']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.globe,
                    color: CupertinoColors.systemGreen,
                  ),
                  title: Text(strings['language']!),
                  trailing: const LanguageDropDown(),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: Text(strings['help']!),
              children: [
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.question_circle,
                    color: CupertinoColors.systemOrange,
                  ),
                  title: Text(strings['help']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _goToHelpPage,
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.exclamationmark_bubble,
                    color: CupertinoColors.systemBlue,
                  ),
                  title: Text(strings['reports']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const ReportsPage()),
                    );
                  },
                ),
                CupertinoListTile(
                  leading: const Icon(
                    CupertinoIcons.info,
                    color: CupertinoColors.systemGrey,
                  ),
                  title: Text(strings['about']!),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const AboutPage()),
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CupertinoButton(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(10),
                onPressed: _logout,
                child: Text(
                  strings['logout']!,
                  style: const TextStyle(
                    color: CupertinoColors.destructiveRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UniformExportProgress {
  const _UniformExportProgress({required this.value, required this.status});

  final double value;
  final String status;
}

class LanguageDropDown extends StatelessWidget {
  const LanguageDropDown({super.key});

  Future<void> _showLanguagePicker(BuildContext context) async {
    final provider = Provider.of<LanguageProvider>(context, listen: false);
    final locale = provider.locale;
    final options = const [
      ('en', 'English'),
      ('he', 'עברית'),
      ('ar', 'عربي'),
      ('ru', 'Русский'),
      ('am', 'አማርኛ'),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  title: Text(option.$2),
                  trailing: locale.languageCode == option.$1
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF1976D2),
                        )
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option.$1),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      provider.setLocale(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale;
    String current = 'English';
    if (locale.languageCode == 'he') {
      current = 'עברית';
    } else if (locale.languageCode == 'ar')
      current = 'عربي';
    else if (locale.languageCode == 'ru')
      current = 'Русский';
    else if (locale.languageCode == 'am')
      current = 'አማርኛ';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showLanguagePicker(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current, style: const TextStyle(color: Colors.grey)),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
