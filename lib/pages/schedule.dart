import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/send_request.dart';

class SchedulePage extends StatefulWidget {
  final String workerId;
  final String workerName;

  const SchedulePage({
    super.key,
    required this.workerId,
    required this.workerName,
  });

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  bool _isLoading = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _reminders = [];
  Map<String, List<Map<String, dynamic>>> _allReminders = {};
  Map<String, String> _dayNotes = {};

  List<String> _availableDates = [];
  List<String> _reminderDates = [];
  Map<String, List<Map<String, String>>> _partialWorkDays = {};
  List<Map<String, String>> _vacations = [];

  bool _isOwnSchedule = false;
  bool _hideScheduleFromOthers = false;
  List<int> _permanentlyDisabledDays = []; // 1=Mon, 7=Sun

  final TextEditingController _notesController = TextEditingController();

  // Updated to use 'users' collection
  DocumentReference get _scheduleDoc => _firestore
      .collection('users')
      .doc(widget.workerId)
      .collection('Schedule')
      .doc('info');

  @override
  void initState() {
    super.initState();
    _checkOwnership();
    _fetchWorkerScheduleConfig();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _checkOwnership() {
    final user = _auth.currentUser;
    if (user != null && user.uid == widget.workerId) {
      setState(() => _isOwnSchedule = true);
    }
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _fetchWorkerScheduleConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _scheduleDoc.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _hideScheduleFromOthers = data['hideSchedule'] ?? false;
          _permanentlyDisabledDays = List<int>.from(data['disabledDays'] ?? []);

          if (data.containsKey('availableDates')) {
            _availableDates = List<String>.from(data['availableDates']);
          }
          if (data.containsKey('reminderDates')) {
            _reminderDates = List<String>.from(data['reminderDates']);
          }
          if (data.containsKey('partialWorkDays')) {
            _partialWorkDays = (data['partialWorkDays'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                _normalizePartialRanges(v),
              ),
            );
          }
          if (data.containsKey('vacations')) {
            _vacations = List<Map<String, String>>.from(
              (data['vacations'] as List).map(
                (v) => Map<String, String>.from(v),
              ),
            );
          }

          if (data.containsKey('dayNotes')) {
            _dayNotes = Map<String, String>.from(data['dayNotes']);
          }

          if (data.containsKey('allReminders')) {
            _allReminders = (data['allReminders'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List)
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(),
              ),
            );
          }
        });

        _updateSelectedDayData();

        if (_isOwnSchedule) {
          await _cleanupPastData();
        }
      }
    } catch (e) {
      debugPrint("Error fetching worker config: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateSelectedDayData() {
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";
    setState(() {
      _reminders = _allReminders[dateStr] ?? [];
      _notesController.text = _dayNotes[dateStr] ?? "";
    });
  }

  Future<void> _cleanupPastData() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool docChanged = false;
    List<String> newAvailableDates = List.from(_availableDates);
    List<String> newReminderDates = List.from(_reminderDates);
    Map<String, List<Map<String, String>>> newPartialDays = Map.from(
      _partialWorkDays,
    );
    List<Map<String, String>> newVacations = List.from(_vacations);
    Map<String, String> newDayNotes = Map.from(_dayNotes);
    Map<String, List<Map<String, dynamic>>> newAllReminders = Map.from(
      _allReminders,
    );

    newAvailableDates.removeWhere((dateStr) {
      try {
        final parts = dateStr.split('-');
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        if (date.isBefore(today)) {
          docChanged = true;
          return true;
        }
      } catch (_) {}
      return false;
    });

    newPartialDays.removeWhere((dateStr, _) {
      try {
        final parts = dateStr.split('-');
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        if (date.isBefore(today)) {
          docChanged = true;
          return true;
        }
      } catch (_) {}
      return false;
    });

    newDayNotes.removeWhere((dateStr, _) {
      try {
        final parts = dateStr.split('-');
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        if (date.isBefore(today)) {
          docChanged = true;
          return true;
        }
      } catch (_) {}
      return false;
    });

    newAllReminders.removeWhere((dateStr, _) {
      try {
        final parts = dateStr.split('-');
        final date = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        if (date.isBefore(today)) {
          docChanged = true;
          return true;
        }
      } catch (_) {}
      return false;
    });

    newReminderDates.removeWhere((dateStr) {
      if (!newAllReminders.containsKey(dateStr) ||
          newAllReminders[dateStr]!.isEmpty) {
        docChanged = true;
        return true;
      }
      return false;
    });

    newVacations.removeWhere((v) {
      try {
        final endParts = v['end']!.split('-');
        final endDate = DateTime(
          int.parse(endParts[0]),
          int.parse(endParts[1]),
          int.parse(endParts[2]),
        );
        if (endDate.isBefore(today)) {
          docChanged = true;
          return true;
        }
      } catch (_) {}
      return false;
    });

    if (docChanged) {
      setState(() {
        _availableDates = newAvailableDates;
        _reminderDates = newReminderDates;
        _partialWorkDays = newPartialDays;
        _vacations = newVacations;
        _dayNotes = newDayNotes;
        _allReminders = newAllReminders;
      });

      await _scheduleDoc.set({
        'availableDates': _availableDates,
        'reminderDates': _reminderDates,
        'partialWorkDays': _partialWorkDays,
        'vacations': _vacations,
        'dayNotes': _dayNotes,
        'allReminders': _allReminders,
      }, SetOptions(merge: true));
    }
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'לוח זמנים',
          'manage_title': 'ניהול לוח זמנים',
          'add_reminder': 'הוסף תזכורת',
          'reminder_hint': 'כתוב כאן את התזכורת...',
          'no_reminders': 'אין תזכורות ליום זה',
          'set_working': 'סמן כיום עבודה',
          'remove_working': 'בטל יום עבודה',
          'set_partial': 'שעות עבודה חלקיות',
          'partial_title': 'בחר שעות עבודה',
          'from': 'מ-',
          'to': 'עד',
          'save': 'שמור',
          'cancel': 'ביטול',
          'ok': 'אישור',
          'confirm_msg':
              'ביטול יום העבודה ימחק את כל התזכורות של יום זה. האם להמשיך?',
          'not_working': 'אין פעילות ביום זה',
          'working_hours': 'שעות עבודה',
          'hidden_msg': 'לוח הזמנים של בעל המקצוע מוסתר',
          'request_work': 'בקש מהמקצוען לעבוד ביום זה',
          'request_hours': 'בקש שעות עבודה נוספות',
          'request_quote': 'בקש הצעת מחיר',
          'set_vacation': 'קבע חופשה',
          'on_vacation': 'בחופשה',
          'cancel_vacation': 'בטל חופשה',
          'vacation_confirm': 'האם אתה בטוח שברצונך לבטל חופשה זו?',
          'permanent_off': 'יום חופש קבוע',
          'weekend_msg': 'לא ניתן לשלוח בקשות ביום חופש קבוע של המקצוען.',
          'vacation_conflict': 'לא ניתן לסמן יום עבודה בזמן חופשה.',
          'work_conflict':
              'לא ניתן לקבוע חופשה ביום עבודה קיים. בטל את יום העבודה קודם.',
          'working_day': 'יום עבודה',
          'has_reminders': 'תזכורות',
          'notes': 'הערות ליום זה',
          'notes_hint': 'כתוב הערות אישיות כאן...',
          'invalid_hours': 'שעת הסיום חייבת להיות אחרי שעת ההתחלה.',
          'overlap_hours': 'טווחי השעות לא יכולים לחפוף זה לזה.',
          'add_time_range': 'הוסף טווח שעות',
          'remove_time_range': 'הסר טווח',
          'time_range': 'טווח שעות',
          'multi_hours_hint': 'אפשר להוסיף כמה טווחי שעות לאותו יום.',
          'selected_hours': 'שעות שנבחרו',
          'edit_hours_hint': 'לחץ על "שעות עבודה חלקיות" כדי לערוך את הטווחים.',
          'clock_hint': 'לחצו על שעת ההתחלה או הסיום כדי לפתוח את השעון.',
          'range_count': 'טווחי שעות',
          'hours_preview': 'תצוגה מקדימה',
          'save_hours_failed': 'שמירת שעות העבודה נכשלה. נסו שוב.',
        };
      default:
        return {
          'title': 'Schedule',
          'manage_title': 'Manage Schedule',
          'add_reminder': 'Add Reminder',
          'reminder_hint': 'Write reminder here...',
          'no_reminders': 'No reminders for this day',
          'set_working': 'Set as Working Day',
          'remove_working': 'Remove Working Day',
          'set_partial': 'Partial Working Hours',
          'partial_title': 'Select Working Hours',
          'from': 'From',
          'to': 'To',
          'save': 'Save',
          'cancel': 'Cancel',
          'ok': 'OK',
          'confirm_msg':
              'Canceling the working day will delete all reminders for this day. Continue?',
          'not_working': 'No activity on this day',
          'working_hours': 'Working Hours',
          'hidden_msg': 'Professional schedule is private',
          'request_work': 'Request pro to work this day',
          'request_hours': 'Request extra working hours',
          'request_quote': 'Request Quote',
          'set_vacation': 'Set Vacation',
          'on_vacation': 'On Vacation',
          'cancel_vacation': 'Cancel Vacation',
          'vacation_confirm': 'Are you sure you want to cancel this vacation?',
          'permanent_off': 'Permanent day off',
          'weekend_msg':
              'Cannot send requests on professional\'s permanent day off.',
          'vacation_conflict': 'Cannot set working day during vacation.',
          'work_conflict':
              'Cannot set vacation on an existing working day. Cancel working day first.',
          'working_day': 'Working Day',
          'has_reminders': 'Reminders',
          'notes': 'Daily Notes',
          'notes_hint': 'Write personal notes here...',
          'invalid_hours': 'End time must be after start time.',
          'overlap_hours': 'Time ranges cannot overlap each other.',
          'add_time_range': 'Add Time Range',
          'remove_time_range': 'Remove Range',
          'time_range': 'Time Range',
          'multi_hours_hint': 'You can add multiple working-hour ranges for the same day.',
          'selected_hours': 'Selected Hours',
          'edit_hours_hint': 'Tap "Partial Working Hours" to edit these ranges.',
          'clock_hint': 'Choose working hours in a simple, clear way.',
          'save_hours_failed': 'Failed to save working hours. Please try again.',
        };
    }
  }

  String _formatWorkingTime(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(time, alwaysUse24HourFormat: true);
  }

  List<Map<String, String>> _normalizePartialRanges(dynamic value) {
    if (value is List) {
      final ranges = value
          .map((item) => Map<String, String>.from(item as Map))
          .where((item) => item['from'] != null && item['to'] != null)
          .toList();
      ranges.sort(
        (a, b) => _compareTimeStrings(a['from']!, b['from']!),
      );
      return ranges;
    }

    if (value is Map) {
      final range = Map<String, String>.from(value);
      if (range['from'] != null && range['to'] != null) {
        return [range];
      }
    }

    return [];
  }

  int _compareTimeStrings(String a, String b) {
    return _timeStringToMinutes(a).compareTo(_timeStringToMinutes(b));
  }

  int _timeToMinutes(TimeOfDay time) => (time.hour * 60) + time.minute;

  int _timeStringToMinutes(String value) {
    final parts = value.split(':');
    return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
  }

  List<Map<String, String>> _getPartialRanges(String dateStr) {
    return List<Map<String, String>>.from(_partialWorkDays[dateStr] ?? const []);
  }

  String _formatPartialRangesText(String dateStr) {
    final ranges = _getPartialRanges(dateStr);
    if (ranges.isEmpty) return '';
    return ranges
        .map((range) => "${range['from']} - ${range['to']}")
        .join(", ");
  }

  Map<String, String>? _getPrimaryPartialRange(String dateStr) {
    final ranges = _getPartialRanges(dateStr);
    if (ranges.isEmpty) return null;
    return ranges.first;
  }

  bool _hasOverlappingRanges(List<Map<String, String>> ranges) {
    final sorted = List<Map<String, String>>.from(ranges)
      ..sort((a, b) => _compareTimeStrings(a['from']!, b['from']!));

    for (int i = 1; i < sorted.length; i++) {
      final previousEnd = _timeStringToMinutes(sorted[i - 1]['to']!);
      final currentStart = _timeStringToMinutes(sorted[i]['from']!);
      if (currentStart < previousEnd) {
        return true;
      }
    }

    return false;
  }

  Future<TimeOfDay?> _showWorkingHoursPicker({
    required TimeOfDay initialTime,
    required String helpText,
  }) async {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.input,
      helpText: helpText,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(alwaysUse24HourFormat: true),
            child: Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(
                  primary: const Color(0xFF1976D2),
                  surface: Colors.white,
                ),
                timePickerTheme: TimePickerThemeData(
                  backgroundColor: Colors.white,
                  dialBackgroundColor: const Color(0xFFEFF6FF),
                  dialHandColor: const Color(0xFF1976D2),
                  hourMinuteColor: const Color(0xFFE2E8F0),
                  hourMinuteTextColor: const Color(0xFF0F172A),
                  hourMinuteShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  dayPeriodShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  dayPeriodBorderSide: const BorderSide(
                    color: Color(0xFFCBD5E1),
                  ),
                  dayPeriodColor: const Color(0xFFE2E8F0),
                  dayPeriodTextColor: const Color(0xFF0F172A),
                  entryModeIconColor: const Color(0xFF1976D2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }

  bool _isVacation(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (var v in _vacations) {
      try {
        final startParts = v['start']!.split('-');
        final endParts = v['end']!.split('-');
        final start = DateTime(
          int.parse(startParts[0]),
          int.parse(startParts[1]),
          int.parse(startParts[2]),
        );
        final end = DateTime(
          int.parse(endParts[0]),
          int.parse(endParts[1]),
          int.parse(endParts[2]),
        );
        if (d.isAtSameMomentAs(start) ||
            d.isAtSameMomentAs(end) ||
            (d.isAfter(start) && d.isBefore(end))) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<void> _cancelVacation(DateTime date) async {
    final strings = _getLocalizedStrings(context);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['cancel_vacation']!),
        content: Text(strings['vacation_confirm']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings['cancel']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(strings['ok']!),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final d = DateTime(date.year, date.month, date.day);
    setState(() {
      _vacations.removeWhere((v) {
        try {
          final startParts = v['start']!.split('-');
          final endParts = v['end']!.split('-');
          final start = DateTime(
            int.parse(startParts[0]),
            int.parse(startParts[1]),
            int.parse(startParts[2]),
          );
          final end = DateTime(
            int.parse(endParts[0]),
            int.parse(endParts[1]),
            int.parse(endParts[2]),
          );
          return (d.isAtSameMomentAs(start) ||
              d.isAtSameMomentAs(end) ||
              (d.isAfter(start) && d.isBefore(end)));
        } catch (_) {
          return false;
        }
      });
    });

    await _scheduleDoc.set({'vacations': _vacations}, SetOptions(merge: true));
  }

  Future<void> _showVacationDialog() async {
    final strings = _getLocalizedStrings(context);
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      for (
        DateTime d = picked.start;
        d.isBefore(picked.end.add(const Duration(days: 1)));
        d = d.add(const Duration(days: 1))
      ) {
        final dStr = "${d.year}-${d.month}-${d.day}";
        if (_availableDates.contains(dStr)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['work_conflict']!)));
          return;
        }
      }

      final startStr =
          "${picked.start.year}-${picked.start.month}-${picked.start.day}";
      final endStr = "${picked.end.year}-${picked.end.month}-${picked.end.day}";

      setState(() {
        _vacations.add({'start': startStr, 'end': endStr});
      });

      await _scheduleDoc.set({
        'vacations': FieldValue.arrayUnion([
          {'start': startStr, 'end': endStr},
        ]),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _addReminder(String text) async {
    if (text.isEmpty) return;
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";

    final reminder = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      if (!_allReminders.containsKey(dateStr)) {
        _allReminders[dateStr] = [];
      }
      _allReminders[dateStr]!.add(reminder);
      _reminders = _allReminders[dateStr]!;
      if (!_reminderDates.contains(dateStr)) {
        _reminderDates.add(dateStr);
      }
    });

    try {
      await _scheduleDoc.set({
        'allReminders': _allReminders,
        'reminderDates': _reminderDates,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error adding reminder: $e");
    }
  }

  Future<void> _deleteReminder(String id) async {
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";
    setState(() {
      if (_allReminders.containsKey(dateStr)) {
        _allReminders[dateStr]!.removeWhere((r) => r['id'] == id);
        _reminders = _allReminders[dateStr]!;
        if (_reminders.isEmpty) {
          _allReminders.remove(dateStr);
          _reminderDates.remove(dateStr);
        }
      }
    });

    try {
      await _scheduleDoc.set({
        'allReminders': _allReminders,
        'reminderDates': _reminderDates,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error deleting reminder: $e");
    }
  }

  Future<void> _toggleWorkingDay() async {
    final strings = _getLocalizedStrings(context);
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";
    final isWorking = _availableDates.contains(dateStr);

    if (_permanentlyDisabledDays.contains(_selectedDay.weekday)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['weekend_msg']!)));
      return;
    }

    if (_isVacation(_selectedDay)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['vacation_conflict']!)));
      return;
    }

    if (isWorking) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings['remove_working']!),
          content: Text(strings['confirm_msg']!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings['cancel']!),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(strings['ok']!),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      setState(() {
        _availableDates.remove(dateStr);
        _partialWorkDays.remove(dateStr);
        _allReminders.remove(dateStr);
        _reminderDates.remove(dateStr);
        _reminders = [];
      });

      await _scheduleDoc.set({
        'availableDates': FieldValue.arrayRemove([dateStr]),
        'partialWorkDays.$dateStr': FieldValue.delete(),
        'allReminders': _allReminders,
        'reminderDates': _reminderDates,
      }, SetOptions(merge: true));
    } else {
      setState(() => _availableDates.add(dateStr));
      await _scheduleDoc.set({
        'availableDates': FieldValue.arrayUnion([dateStr]),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _setPartialHours() async {
    final strings = _getLocalizedStrings(context);
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";

    if (_permanentlyDisabledDays.contains(_selectedDay.weekday)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['weekend_msg']!)));
      return;
    }

    if (_isVacation(_selectedDay)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['vacation_conflict']!)));
      return;
    }

    final ranges = _getPartialRanges(dateStr);
    final editableRanges = ranges.isEmpty
        ? [
            {'from': '08:00', 'to': '16:00'},
          ]
        : ranges.map((range) => Map<String, String>.from(range)).toList();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFF1976D2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings['partial_title']!,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              strings['clock_hint']!,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      strings['multi_hours_hint']!,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          ...List.generate(editableRanges.length, (index) {
                            final range = editableRanges[index];
                            final fromParts = range['from']!.split(':');
                            final toParts = range['to']!.split(':');
                            final from = TimeOfDay(
                              hour: int.parse(fromParts[0]),
                              minute: int.parse(fromParts[1]),
                            );
                            final to = TimeOfDay(
                              hour: int.parse(toParts[0]),
                              minute: int.parse(toParts[1]),
                            );

                            return Container(
                              margin: EdgeInsets.only(
                                bottom: index == editableRanges.length - 1 ? 0 : 14,
                              ),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "${strings['time_range']} ${index + 1}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (editableRanges.length > 1)
                                        IconButton(
                                          onPressed: () {
                                            setDialogState(
                                              () => editableRanges.removeAt(index),
                                            );
                                          },
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            minimumSize: const Size(36, 36),
                                            padding: EdgeInsets.zero,
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFDC2626),
                                          ),
                                          tooltip: strings['remove_time_range'],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildPartialTimeButton(
                                          context: context,
                                          label: strings['from']!,
                                          value: from,
                                          accentColor: const Color(0xFF1976D2),
                                          onTap: () async {
                                            final picked = await _showWorkingHoursPicker(
                                              initialTime: from,
                                              helpText: strings['from']!,
                                            );
                                            if (picked != null) {
                                              setDialogState(() {
                                                editableRanges[index]['from'] =
                                                    "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildPartialTimeButton(
                                          context: context,
                                          label: strings['to']!,
                                          value: to,
                                          accentColor: const Color(0xFF1976D2),
                                          onTap: () async {
                                            final picked = await _showWorkingHoursPicker(
                                              initialTime: to,
                                              helpText: strings['to']!,
                                            );
                                            if (picked != null) {
                                              setDialogState(() {
                                                editableRanges[index]['to'] =
                                                    "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  editableRanges.add({'from': '08:00', 'to': '16:00'});
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF1976D2)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(strings['add_time_range']!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(strings['cancel']!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final normalizedRanges = editableRanges
                                .map((range) => Map<String, String>.from(range))
                                .toList()
                              ..sort(
                                (a, b) => _compareTimeStrings(a['from']!, b['from']!),
                              );

                            final hasInvalidRange = normalizedRanges.any(
                              (range) =>
                                  _timeStringToMinutes(range['to']!) <=
                                  _timeStringToMinutes(range['from']!),
                            );

                            if (hasInvalidRange) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(strings['invalid_hours']!)),
                              );
                              return;
                            }

                            if (_hasOverlappingRanges(normalizedRanges)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(strings['overlap_hours']!)),
                              );
                              return;
                            }

                            setState(() {
                              if (!_availableDates.contains(dateStr)) {
                                _availableDates.add(dateStr);
                              }
                              _partialWorkDays[dateStr] = normalizedRanges;
                            });

                            try {
                              await _scheduleDoc.set({
                                'availableDates': _availableDates,
                                'partialWorkDays': _partialWorkDays,
                              }, SetOptions(merge: true));

                              if (mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              debugPrint("Error saving partial hours: $e");
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings['save_hours_failed']!),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(strings['save']!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPartialTimeButton({
    required BuildContext context,
    required String label,
    required TimeOfDay value,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatWorkingTime(context, value),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";

    final isWorkingDay = _availableDates.contains(dateStr);
    final isPermanentOff = _permanentlyDisabledDays.contains(
      _selectedDay.weekday,
    );
    final onVacation = _isVacation(_selectedDay);
    final isPast = _selectedDay.isBefore(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TableCalendar(
                      firstDay: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        _updateSelectedDayData();
                      },
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(
                          color: Color(0xFF1976D2),
                          fontWeight: FontWeight.bold,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Color(0xFF1976D2),
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      eventLoader: (day) {
                        final dStr = "${day.year}-${day.month}-${day.day}";
                        return _reminderDates.contains(dStr)
                            ? ['reminder']
                            : [];
                      },
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) {
                          final dStr = "${day.year}-${day.month}-${day.day}";
                          if (_isVacation(day))
                            return _dayCircle(day, Colors.red);
                          if (_availableDates.contains(dStr))
                            return _dayCircle(day, Colors.green);
                          if (_permanentlyDisabledDays.contains(day.weekday)) {
                            return _dayCircle(
                              day,
                              Colors.grey.shade300,
                              isTextGrey: true,
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 16,
                        left: 16,
                        right: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _legendItem(Colors.green, strings['working_day']!),
                          const SizedBox(width: 16),
                          _legendItem(Colors.red, strings['on_vacation']!),
                          const SizedBox(width: 16),
                          _legendItem(Colors.orange, strings['has_reminders']!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _isOwnSchedule
                    ? _buildOwnerView(strings)
                    : _buildUserView(
                        strings,
                        isWorkingDay,
                        isPermanentOff,
                        onVacation,
                        isPast,
                      ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _dayCircle(DateTime day, Color color, {bool isTextGrey = false}) {
    return Center(
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Center(
          child: Text(
            "${day.day}",
            style: TextStyle(
              color: isTextGrey ? Colors.grey : color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerView(Map<String, String> strings) {
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";
    final isWorkingDay = _availableDates.contains(dateStr);
    final onVacation = _isVacation(_selectedDay);
    final isPermanentOff = _permanentlyDisabledDays.contains(
      _selectedDay.weekday,
    );

    return Column(
      children: [
        if (isPermanentOff)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.weekend_rounded,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings['permanent_off']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
        _buildOwnerControls(
          strings,
          isWorkingDay,
          onVacation,
          dateStr,
          isPermanentOff,
        ),
        const SizedBox(height: 20),
        if (_getPartialRanges(dateStr).isNotEmpty) ...[
          _buildWorkingHoursSummary(strings, dateStr),
          const SizedBox(height: 20),
        ],
        const SizedBox(height: 20),
        _buildRemindersList(strings),
        _buildAddReminderInput(strings),
      ],
    );
  }

  Widget _buildOwnerControls(
    Map<String, String> strings,
    bool isWorking,
    bool onVac,
    String dateStr,
    bool isPermanentOff,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 24,
        runSpacing: 20,
        children: [
          _controlBtn(
            Icons.work_rounded,
            strings['set_working']!,
            isWorking,
            Colors.green,
            _toggleWorkingDay,
            disabled: isPermanentOff,
          ),
          _controlBtn(
            Icons.more_time_rounded,
            strings['set_partial']!,
            _partialWorkDays.containsKey(dateStr),
            Colors.orange,
            _setPartialHours,
            disabled: isPermanentOff,
          ),
          _controlBtn(
            Icons.beach_access_rounded,
            onVac ? strings['on_vacation']! : strings['set_vacation']!,
            onVac,
            Colors.red,
            onVac ? () => _cancelVacation(_selectedDay) : _showVacationDialog,
          ),
        ],
      ),
    );
  }

  Widget _controlBtn(
    IconData icon,
    String label,
    bool active,
    Color color,
    VoidCallback onTap,
    {bool disabled = false}
  ) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 92,
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: disabled
                  ? Colors.grey.shade100
                  : (active ? color : Colors.white),
              shape: BoxShape.circle,
              border: Border.all(
                color: disabled
                    ? Colors.grey.shade300
                    : (active ? color : Colors.grey.shade200),
              ),
              boxShadow: [
                if (active && !disabled)
                  BoxShadow(color: color.withOpacity(0.3), blurRadius: 8),
              ],
            ),
            child: Icon(
              icon,
              color: disabled
                  ? Colors.grey.shade400
                  : (active ? Colors.white : Colors.grey),
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: disabled
                  ? Colors.grey.shade400
                  : (active ? color : Colors.grey),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildWorkingHoursSummary(Map<String, String> strings, String dateStr) {
    final ranges = _getPartialRanges(dateStr);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings['selected_hours']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings['edit_hours_hint']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ranges.map((range) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  "${range['from']} - ${range['to']}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersList(Map<String, String> strings) {
    if (_reminders.isEmpty)
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          strings['no_reminders']!,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    return Column(
      children: _reminders
          .map(
            (r) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(r['text'], style: const TextStyle(fontSize: 14)),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  onPressed: () => _deleteReminder(r['id']),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildAddReminderInput(Map<String, String> strings) {
    final controller = TextEditingController();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        onSubmitted: (v) {
          _addReminder(v);
          controller.clear();
        },
        decoration: InputDecoration(
          hintText: strings['add_reminder'],
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.add_circle, color: Color(0xFF1976D2)),
            onPressed: () {
              _addReminder(controller.text);
              controller.clear();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUserView(
    Map<String, String> strings,
    bool isWorking,
    bool isOff,
    bool isVac,
    bool isPast,
  ) {
    if (_hideScheduleFromOthers)
      return _emptyState(Icons.lock_outline, strings['hidden_msg']!);
    final dateStr =
        "${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}";

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(
            isVac
                ? Icons.beach_access
                : (isWorking
                      ? Icons.work
                      : (isOff ? Icons.weekend : Icons.work_off)),
            size: 48,
            color: isVac
                ? Colors.red
                : (isWorking ? Colors.green : Colors.grey),
          ),
          const SizedBox(height: 16),
          Text(
            isVac
                ? strings['on_vacation']!
                : isWorking
                ? (_partialWorkDays.containsKey(dateStr)
                      ? strings['working_hours']!
                      : strings['set_working']!)
                : (isOff ? strings['permanent_off']! : strings['not_working']!),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (isWorking && _getPartialRanges(dateStr).isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: _getPartialRanges(dateStr).map((range) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    "${range['from']} - ${range['to']}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (!isPast && !isVac && !isOff) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final partial = isWorking
                      ? _getPrimaryPartialRange(dateStr)
                      : null;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SendRequestPage(
                        workerId: widget.workerId,
                        workerName: widget.workerName,
                        selectedDay: _selectedDay,
                        isExtraHours: isWorking,
                        initialFrom: partial?['from'],
                        initialTo: partial?['to'],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  isWorking
                      ? strings['request_hours']!
                      : strings['request_work']!,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SendRequestPage(
                        workerId: widget.workerId,
                        workerName: widget.workerName,
                        selectedDay: _selectedDay,
                        isQuoteRequest: true,
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  side: const BorderSide(color: Color(0xFF1976D2)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(strings['request_quote']!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String msg) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: Colors.grey),
        const SizedBox(height: 16),
        Text(msg),
      ],
    ),
  );
}
