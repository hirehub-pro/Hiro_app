import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/services/auth_service.dart';
import 'package:untitled1/services/bkmv_export_service.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/sign_in.dart';
import 'package:untitled1/pages/about.dart';
import 'package:untitled1/pages/account_settings.dart';
import 'package:untitled1/pages/help_page.dart';
import 'package:untitled1/pages/privacy_policy_page.dart';
import 'package:untitled1/pages/reports_page.dart';
import 'package:untitled1/pages/terms_of_service_page.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  static const List<int> _displayWeekdayOrder = [7, 1, 2, 3, 4, 5, 6];
  bool _notificationsEnabled = true;
  bool _hideSchedule = false;
  List<int> _disabledDays = []; // 1 = Monday, 7 = Sunday
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
      final scheduleDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final scheduleData = scheduleDoc.data();
        final defaultWorkingHours =
            scheduleData?['defaultWorkingHours'] as Map<String, dynamic>?;
        final notificationsAllowed = await _isNotificationPermissionGranted();
        if (!mounted) return;

        setState(() {
          _userData = data;
          _userRole = data['role'] ?? 'customer';
          _hideSchedule = data['hideSchedule'] ?? false;
          _disabledDays = List<int>.from(data['disabledDays'] ?? []);
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
        await _updateSetting('notificationsEnabled', notificationsAllowed);
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
    await firestore.collection('users').doc(user.uid).update({key: value});

    if (key == 'hideSchedule' || key == 'disabledDays') {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('Schedule')
          .doc('info')
          .set({key: value}, SetOptions(merge: true));
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

  Future<void> _updateWorkingHours() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
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
        await _updateSetting('notificationsEnabled', true);
        return;
      }

      final isGranted = await _requestNotificationPermission();
      if (!mounted) return;

      if (isGranted) {
        setState(() => _notificationsEnabled = true);
        await _updateSetting('notificationsEnabled', true);
      } else if (await _isNotificationPermissionBlocked()) {
        _showPermissionDialog();
        setState(() => _notificationsEnabled = false);
        await _updateSetting('notificationsEnabled', false);
      } else {
        setState(() => _notificationsEnabled = false);
        await _updateSetting('notificationsEnabled', false);
      }
    } else {
      final isGranted = await _isNotificationPermissionGranted();
      if (!mounted) return;

      setState(() => _notificationsEnabled = isGranted);
      if (isGranted) {
        _showPermissionDialog(messageKey: 'permission_controlled_by_phone');
      } else {
        await _updateSetting('notificationsEnabled', false);
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
    await _updateSetting('notificationsEnabled', isGranted);
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

  String _formatCompactDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}$month$day';
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

  Future<Directory> _getBkmvExportDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final directory = Directory(documentsDir.path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> _promptExportEmail() async {
    final initialEmail =
        (FirebaseAuth.instance.currentUser?.email ??
                _userData?['email']?.toString() ??
                '')
            .trim();
    final controller = TextEditingController(text: initialEmail);
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
    final helper = isRtl
        ? 'נעתיק את הכתובת, נפתח שיתוף קבצים, ואז נפתח מייל מוכן לכתובת הזו.'
        : 'We will copy the address, open file sharing, then open an email draft to this address.';
    final invalid = isRtl
        ? 'יש להזין כתובת אימייל תקינה.'
        : 'Enter a valid email address.';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: label,
                      hintText: hint,
                      helperText: helper,
                      errorText: validationMessage,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(isRtl ? 'ביטול' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final email = controller.text.trim();
                    final isValid = RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(email);
                    if (!isValid) {
                      setDialogState(() => validationMessage = invalid);
                      return;
                    }
                    Navigator.pop(dialogContext, email);
                  },
                  child: Text(isRtl ? 'המשך' : 'Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  String _formatAmountForPdf(double value) {
    final formatter = intl.NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _formatCompactDateForDisplay(String yyyymmdd) {
    if (yyyymmdd.length != 8) return yyyymmdd;
    return '${yyyymmdd.substring(6, 8)}/${yyyymmdd.substring(4, 6)}/${yyyymmdd.substring(2, 4)}';
  }

  String _formatCompactTimeForDisplay(String hhmm) {
    if (hhmm.length != 4) return hhmm;
    return '${hhmm.substring(0, 2)}:${hhmm.substring(2, 4)}';
  }

  Future<pw.Font> _loadPdfFont() async {
    final fontData = await rootBundle.load(
      'assets/fonts/Rubik-VariableFont_wght.ttf',
    );
    return pw.Font.ttf(fontData);
  }

  pw.Widget _buildPdfCell(
    String text, {
    required pw.Font font,
    bool isHeader = false,
    pw.Alignment alignment = pw.Alignment.centerRight,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 11 : 10.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.TableRow _buildPdfTableRow(
    List<String> values, {
    required pw.Font font,
    bool isHeader = false,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: isHeader ? pdf.PdfColors.grey200 : null,
      ),
      children: values
          .map(
            (value) => _buildPdfCell(
              value,
              font: font,
              isHeader: isHeader,
              alignment: value == values.first
                  ? pw.Alignment.centerLeft
                  : pw.Alignment.centerRight,
            ),
          )
          .toList(growable: false),
    );
  }

  pw.Widget _buildPrintedSummaryPage(
    BkmvPrintedSummary summary, {
    required pw.Font font,
  }) {
    final visibleRows = summary.rows;
    final displayFromDate = _formatCompactDateForDisplay(summary.fromDate);
    final displayToDate = _formatCompactDateForDisplay(summary.toDate);
    final displayExportDate = _formatCompactDateForDisplay(summary.exportDate);
    final displayExportTime = _formatCompactTimeForDisplay(summary.exportTime);
    final totalMoney = visibleRows.fold<double>(
      0,
      (runningTotal, row) => runningTotal + row.totalAmountIncludingVat,
    );
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'פלט מודפס לפי המבנה הנדרש בסעיף 2.6',
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '${summary.businessName} | ח.פ. ${summary.businessNumber} | $displayFromDate-$displayToDate',
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.35),
              1: pw.FlexColumnWidth(0.8),
              2: pw.FlexColumnWidth(1.45),
              3: pw.FlexColumnWidth(0.7),
            },
            children: [
              _buildPdfTableRow(
                [
                  'סה"כ כספי כולל מע"מ\n(שדה 1223)',
                  'סה"כ כמותי',
                  'סוג המסמך',
                  'מספר המסמך',
                ],
                font: font,
                isHeader: true,
              ),
              for (final row in visibleRows)
                _buildPdfTableRow([
                  _formatAmountForPdf(row.totalAmountIncludingVat),
                  row.quantity.toString(),
                  row.documentTypeLabel,
                  row.documentTypeCode.toString(),
                ], font: font),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'סה"כ כמות: ${summary.totalDocumentQuantity}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: font, fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'סה"כ כספי: ${_formatAmountForPdf(totalMoney)}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(font: font, fontSize: 11),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'הנתונים הופקו באמצעות תוכנת',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  summary.softwareName,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'מספר תעודת רישום:',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  summary.softwareRegistrationNumber,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'תאריך הפקה:',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  '$displayExportDate $displayExportTime',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAnnex4Page(
    BkmvAnnex4Summary summary, {
    required pw.Font font,
  }) {
    final displayFromDate = _formatCompactDateForDisplay(summary.fromDate);
    final displayToDate = _formatCompactDateForDisplay(summary.toDate);
    final displayExportDate = _formatCompactDateForDisplay(summary.exportDate);
    final displayExportTime = _formatCompactTimeForDisplay(summary.exportTime);

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.SizedBox(height: 24),
          pw.Center(
            child: pw.Text(
              'הפקת קבצים במבנה אחיד',
              style: pw.TextStyle(
                font: font,
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline,
              ),
            ),
          ),
          pw.SizedBox(height: 26),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'עבור:',
              style: pw.TextStyle(
                font: font,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'מספר עוסק מורשה: ${summary.businessNumber}',
            style: pw.TextStyle(font: font, fontSize: 14),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'שם בית העסק: ${summary.businessName}',
            style: pw.TextStyle(font: font, fontSize: 14),
          ),
          pw.SizedBox(height: 28),
          pw.Center(
            child: pw.Text(
              '** ביצוע ממשק פתוח הסתיים בהצלחה **',
              style: pw.TextStyle(
                font: font,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'הנתונים נשמרו בנתיב:',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 5,
                child: pw.Text(
                  summary.exportDirectory,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(font: font, fontSize: 14),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'טווח תאריכים:',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 5,
                child: pw.Row(
                  children: [
                    pw.Text(
                      'מתאריך: $displayFromDate',
                      style: pw.TextStyle(font: font, fontSize: 14),
                    ),
                    pw.SizedBox(width: 28),
                    pw.Text(
                      'ועד תאריך: $displayToDate',
                      style: pw.TextStyle(font: font, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'פירוט סך סוגי הרשומות בקובץ BKMVDATA.TXT:',
            style: pw.TextStyle(
              font: font,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 42),
            child: pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(width: 0.6),
                top: pw.BorderSide(width: 0.6),
                bottom: pw.BorderSide(width: 0.6),
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(90),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FixedColumnWidth(80),
              },
              children: [
                _buildPdfTableRow(
                  ['סוג רשומה', 'תיאור', 'כמות'],
                  font: font,
                  isHeader: true,
                ),
                for (final row in summary.rows)
                  _buildPdfTableRow([
                    row.recordCode,
                    row.recordLabel,
                    row.quantity.toString(),
                  ], font: font),
                _buildPdfTableRow(
                  ['סה"כ', '', summary.totalRecords.toString()],
                  font: font,
                  isHeader: true,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Divider(thickness: 2),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'הנתונים הופקו באמצעות תוכנת',
                  style: pw.TextStyle(font: font, fontSize: 13),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  summary.softwareName,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'מספר תעודת רישום:',
                  style: pw.TextStyle(font: font, fontSize: 13),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  summary.softwareRegistrationNumber,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  'תאריך הפקה:',
                  style: pw.TextStyle(font: font, fontSize: 13),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  '$displayExportDate $displayExportTime',
                  style: pw.TextStyle(font: font, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _generateWorkerUniformFiles() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isGeneratingUniformFiles) return;

    try {
      final recipientEmail = await _promptExportEmail();
      if (recipientEmail == null || !mounted) return;

      final selectedRange = await _pickExportDateRange();
      if (selectedRange == null || !mounted) return;

      setState(() => _isGeneratingUniformFiles = true);

      final fromDate = _formatCompactDate(selectedRange.start);
      final toDate = _formatCompactDate(selectedRange.end);
      final directory = await _getBkmvExportDirectory();
      final result = await BkmvExportService.exportForUser(
        firestore: FirebaseFirestore.instance,
        userId: user.uid,
        fromDate: fromDate,
        toDate: toDate,
        rootDirectory: directory,
      );

      if (!result.hasFiles) {
        throw StateError(
          result.warnings.isNotEmpty
              ? result.warnings.join('\n')
              : 'No BKMV files were generated for this range.',
        );
      }

      final font = await _loadPdfFont();
      final timestamp = DateTime.now();
      final stamp =
          '${_formatCompactDate(timestamp)}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}';
      final printedSummaryFile = File(
        '${directory.path}${Platform.pathSeparator}BKMV_printed_summary_$stamp.pdf',
      );
      final annex4File = File(
        '${directory.path}${Platform.pathSeparator}BKMV_annex_4_$stamp.pdf',
      );

      final printedSummaryDoc = pw.Document();
      final annex4Doc = pw.Document();

      for (final package in result.packages) {
        printedSummaryDoc.addPage(
          pw.MultiPage(
            pageFormat: pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) => [
              _buildPrintedSummaryPage(package.summary, font: font),
            ],
          ),
        );
        annex4Doc.addPage(
          pw.MultiPage(
            pageFormat: pdf.PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
            build: (_) => [_buildAnnex4Page(package.annex4Summary, font: font)],
          ),
        );
      }

      await printedSummaryFile.writeAsBytes(
        await printedSummaryDoc.save(),
        flush: true,
      );
      await annex4File.writeAsBytes(await annex4Doc.save(), flush: true);

      final files = <XFile>[
        for (final package in result.packages) ...[
          XFile(package.bkmvFile.path),
          XFile(package.iniFile.path),
        ],
        XFile(printedSummaryFile.path),
        XFile(annex4File.path),
      ];

      await Clipboard.setData(ClipboardData(text: recipientEmail));
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          text: 'Send to: $recipientEmail\nBKMV export bundle',
        ),
      );

      final emailUri = Uri(
        scheme: 'mailto',
        path: recipientEmail,
        queryParameters: {
          'subject': 'BKMV export files',
          'body':
              'BKMV export files are ready.\n\nExport folder:\n${directory.path}\n\nIf the attachments did not transfer automatically from the share step, attach the generated files from this folder.',
        },
      );
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      }

      if (!mounted) return;
      final warningSuffix = result.warnings.isEmpty
          ? ''
          : '\n${result.warnings.join(' | ')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Prepared ${files.length} files for $recipientEmail in ${directory.path}$warningSuffix',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingUniformFiles = false);
      }
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
          'uniform_export': 'הפקת קבצים במבנה אחיד',
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
          'uniform_export': 'إنتاج ملفات بالبنية الموحدة',
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
          'uniform_export': 'Создать файлы в едином формате',
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
          'uniform_export': 'በአንድ መዋቅር ፋይሎችን አውጣ',
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
          'uniform_export': 'Generate Uniform Files',
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

    return _buildGalaxySection(strings['uniform_export']!, [
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
        subtitle: Text(
          isRtl
              ? 'הפקת BKMVDATA, סעיף 2.6 וסעיף 5.4 בפעולה אחת'
              : 'Generate BKMVDATA, section 2.6, and section 5.4 in one action',
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
                                  ? CupertinoColors.systemRed.withOpacity(0.1)
                                  : CupertinoColors.systemBlue.withOpacity(0.1),
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
                header: Text(strings['uniform_export']!),
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      CupertinoIcons.doc_on_doc,
                      color: _isGeneratingUniformFiles
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.systemBlue,
                    ),
                    title: Text(strings['uniform_export']!),
                    subtitle: Text(
                      isRtl
                          ? 'הפקת BKMVDATA, סעיף 2.6 וסעיף 5.4 בפעולה אחת'
                          : 'Generate BKMVDATA, section 2.6, and section 5.4 in one action',
                    ),
                    trailing: _isGeneratingUniformFiles
                        ? const CupertinoActivityIndicator()
                        : const CupertinoListTileChevron(),
                    onTap: _isGeneratingUniformFiles
                        ? null
                        : _generateWorkerUniformFiles,
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

class LanguageDropDown extends StatelessWidget {
  const LanguageDropDown({super.key});

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
      child: PopupMenuButton<String>(
        onSelected: (code) {
          Provider.of<LanguageProvider>(context, listen: false).setLocale(code);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current, style: const TextStyle(color: Colors.grey)),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'en', child: Text('English')),
          const PopupMenuItem(value: 'he', child: Text('עברית')),
          const PopupMenuItem(value: 'ar', child: Text('عربي')),
          const PopupMenuItem(value: 'ru', child: Text('Русский')),
          const PopupMenuItem(value: 'am', child: Text('አማርኛ')),
        ],
      ),
    );
  }
}
