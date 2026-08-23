import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/map_app_launcher.dart';
import 'package:untitled1/utils/profession_localization.dart';
import 'package:untitled1/utils/request_expiration.dart';

String _requestTimeValue(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _requestDateValue(DateTime value) {
  return '${value.year}-${value.month}-${value.day}';
}

class MyRequestDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;
  final Map<String, dynamic> initialData;

  const MyRequestDetailsPage({
    super.key,
    required this.requestRef,
    required this.initialData,
  });

  @override
  State<MyRequestDetailsPage> createState() => _MyRequestDetailsPageState();
}

class _MyRequestDetailsPageState extends State<MyRequestDetailsPage> {
  bool _isCancelling = false;
  bool _isUpdating = false;
  List<Map<String, dynamic>> _professionItems = [];

  @override
  void initState() {
    super.initState();
    _loadProfessionItems();
  }

  Future<void> _loadProfessionItems() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('metadata')
          .doc('professions')
          .get();
      final rawItems = snapshot.data()?['items'];
      if (rawItems is! List || !mounted) return;

      setState(() {
        _professionItems = rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      });
    } catch (error) {
      debugPrint('Failed to load profession translations: $error');
    }
  }

  String _localizedProfessionName(String profession, String localeCode) {
    final normalized = profession.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    for (final item in _professionItems) {
      final matchesStoredName = const ['en', 'he', 'ar', 'ru', 'am'].any((
        languageCode,
      ) {
        return item[languageCode]?.toString().trim().toLowerCase() ==
            normalized;
      });
      if (!matchesStoredName) continue;

      final localized = item[localeCode]?.toString().trim();
      if (localized != null && localized.isNotEmpty) return localized;

      final english = item['en']?.toString().trim();
      if (english != null && english.isNotEmpty) return english;
    }

    return ProfessionLocalization.toLocalized(profession, localeCode);
  }

  Map<String, String> _strings(BuildContext context) {
    final code = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (code) {
      case 'he':
        return {
          'details': 'פרטי בקשה',
          'request_type': 'סוג בקשה',
          'worker_name': 'שם בעל המקצוע',
          'profession_name': 'מקצוע',
          'work_request': 'בקשת עבודה',
          'quote_request': 'בקשה לתן הצעת מחיר',
          'date': 'תאריך',
          'hours': 'שעות',
          'from_time': 'משעה',
          'to_time': 'עד שעה',
          'schedule_template': 'בתאריך {date} בין השעה {from} ל־{to}',
          'location': 'מיקום',
          'service_location': 'אופן השירות',
          'service_at_provider': 'אני מגיע לבעל המקצוע',
          'service_at_customer': 'בעל המקצוע מגיע אליי',
          'service_online': 'פגישה אונליין',
          'description': 'תיאור',
          'created_at': 'נוצר בתאריך',
          'additional_details': 'פרטים נוספים',
          'status': 'סטטוס',
          'waiting_for_approval': 'ממתין לאישור',
          'reviewed': 'הבקשה נבדקה',
          'accepted': 'התקבל',
          'rejected': 'נדחה',
          'cancelled': 'בוטל',
          'expired': 'פג תוקף — ללא מענה',
          'cancel': 'בטל בקשה',
          'edit_request': 'ערוך בקשה',
          'save_changes': 'שמור שינויים',
          'edit_success': 'הבקשה עודכנה',
          'edit_error': 'עדכון הבקשה נכשל',
          'invalid_time_range': 'שעת הסיום חייבת להיות אחרי שעת ההתחלה',
          'time_must_be_future': 'מועד הבקשה חייב להיות בעתיד',
          'no_longer_pending': 'לא ניתן לערוך בקשה שכבר נענתה',
          'cancel_success': 'הבקשה בוטלה',
          'cancel_error': 'נכשל בביטול הבקשה',
          'confirm_title': 'לבטל את הבקשה?',
          'confirm_body': 'פעולה זו תעדכן את סטטוס הבקשה ל-בוטל.',
          'close': 'סגור',
          'ok': 'אישור',
          'tap_image': 'הקשו על תמונה להגדלה',
          'images': 'תמונות מצורפות',
          'open_chat': 'פתח צ\'אט',
          'view_map': 'פתח מפה',
          'no_description': 'לא סופק תיאור',
          'unknown': 'לא ידוע',
        };
      case 'ar':
        return {
          'details': 'تفاصيل الطلب',
          'request_type': 'نوع الطلب',
          'worker_name': 'اسم المحترف',
          'profession_name': 'المهنة',
          'work_request': 'طلب عمل',
          'quote_request': 'طلب عرض سعر',
          'date': 'التاريخ',
          'hours': 'الساعات',
          'from_time': 'من الساعة',
          'to_time': 'حتى الساعة',
          'schedule_template': 'بتاريخ {date} من الساعة {from} إلى {to}',
          'location': 'الموقع',
          'service_location': 'طريقة تقديم الخدمة',
          'service_at_provider': 'سأذهب إلى المحترف',
          'service_at_customer': 'المحترف سيأتي إلي',
          'service_online': 'جلسة أونلاين',
          'description': 'الوصف',
          'created_at': 'تاريخ الإنشاء',
          'additional_details': 'تفاصيل إضافية',
          'status': 'الحالة',
          'waiting_for_approval': 'بانتظار الموافقة',
          'reviewed': 'تمت مراجعة الطلب',
          'accepted': 'تم القبول',
          'rejected': 'تم الرفض',
          'cancelled': 'تم الإلغاء',
          'expired': 'منتهي الصلاحية — دون رد',
          'cancel': 'إلغاء الطلب',
          'edit_request': 'تعديل الطلب',
          'save_changes': 'حفظ التغييرات',
          'edit_success': 'تم تحديث الطلب',
          'edit_error': 'فشل تحديث الطلب',
          'invalid_time_range': 'يجب أن يكون وقت الانتهاء بعد وقت البدء',
          'time_must_be_future': 'يجب أن يكون موعد الطلب في المستقبل',
          'no_longer_pending': 'لا يمكن تعديل طلب تم الرد عليه',
          'cancel_success': 'تم إلغاء الطلب',
          'cancel_error': 'فشل إلغاء الطلب',
          'confirm_title': 'إلغاء الطلب؟',
          'confirm_body': 'سيتم تحديث حالة الطلب إلى ملغي.',
          'close': 'إغلاق',
          'ok': 'تأكيد',
          'tap_image': 'اضغط على الصورة للتكبير',
          'images': 'الصور المرفقة',
          'open_chat': 'فتح المحادثة',
          'view_map': 'فتح الخريطة',
          'no_description': 'لم يتم تقديم وصف',
          'unknown': 'غير معروف',
        };
      case 'am':
        return {
          'details': 'የጥያቄ ዝርዝሮች',
          'request_type': 'የጥያቄ አይነት',
          'worker_name': 'የባለሙያ ስም',
          'profession_name': 'ሙያ',
          'work_request': 'የስራ ጥያቄ',
          'quote_request': 'የዋጋ ቅናሽ ጥያቄ',
          'date': 'ቀን',
          'hours': 'ሰዓታት',
          'from_time': 'ከሰዓት',
          'to_time': 'እስከ',
          'schedule_template': 'በ{date} ከሰዓት {from} እስከ {to}',
          'location': 'አካባቢ',
          'service_location': 'የአገልግሎት ቦታ',
          'service_at_provider': 'እኔ ወደ ባለሙያው እሄዳለሁ',
          'service_at_customer': 'ባለሙያው ወደ እኔ ይመጣል',
          'service_online': 'ኦንላይን ስብሰባ',
          'description': 'መግለጫ',
          'created_at': 'የተፈጠረበት',
          'additional_details': 'ተጨማሪ ዝርዝሮች',
          'status': 'ሁኔታ',
          'waiting_for_approval': 'ማጽደቅ በመጠባበቅ',
          'reviewed': 'ጥያቄው ታይቷል',
          'accepted': 'ተቀባ',
          'rejected': 'ተቀባይነት አላገኘም',
          'cancelled': 'ተሰርዟል',
          'expired': 'ጊዜው አልፏል — ምላሽ የለም',
          'cancel': 'ጥያቄ ሰርዝ',
          'edit_request': 'ጥያቄውን ያርትዑ',
          'save_changes': 'ለውጦችን አስቀምጥ',
          'edit_success': 'ጥያቄው ተዘምኗል',
          'edit_error': 'ጥያቄውን ማዘመን አልተሳካም',
          'invalid_time_range': 'የማብቂያ ሰዓት ከመጀመሪያው በኋላ መሆን አለበት',
          'time_must_be_future': 'የጥያቄው ጊዜ ወደፊት መሆን አለበት',
          'no_longer_pending': 'ምላሽ የተሰጠውን ጥያቄ ማርትዕ አይቻልም',
          'cancel_success': 'ጥያቄው ተሰርዟል',
          'cancel_error': 'ጥያቄውን ማሰረዝ አልተሳካም',
          'confirm_title': 'ይህን ጥያቄ ልሰርዝ?',
          'confirm_body': 'ይህ የጥያቄውን ሁኔታ ወደ ተሰረዘ ያዘምናል።',
          'close': 'ዝጋ',
          'ok': 'እሺ',
          'tap_image': 'ለማስፋት ምስሉን ይጫኑ',
          'images': 'የተያያዙ ምስሎች',
          'open_chat': 'ቻት ክፈት',
          'view_map': 'ካርታ ክፈት',
          'no_description': 'ምንም መግለጫ አልተሰጠም',
          'unknown': 'ያልታወቀ',
        };
      case 'ru':
        return {
          'details': 'Детали запроса',
          'request_type': 'Тип запроса',
          'worker_name': 'Имя специалиста',
          'profession_name': 'Профессия',
          'work_request': 'Рабочий запрос',
          'quote_request': 'Запрос предложения',
          'date': 'Дата',
          'hours': 'Часы',
          'from_time': 'С',
          'to_time': 'До',
          'schedule_template': '{date}, с {from} до {to}',
          'location': 'Локация',
          'service_location': 'Место оказания услуги',
          'service_at_provider': 'Я еду к специалисту',
          'service_at_customer': 'Специалист приезжает ко мне',
          'service_online': 'Онлайн-сессия',
          'description': 'Описание',
          'created_at': 'Создано',
          'additional_details': 'Дополнительные детали',
          'status': 'Статус',
          'waiting_for_approval': 'Ожидает подтверждения',
          'reviewed': 'Запрос просмотрен',
          'accepted': 'Принято',
          'rejected': 'Отклонено',
          'cancelled': 'Отменено',
          'expired': 'Срок истёк — нет ответа',
          'cancel': 'Отменить запрос',
          'edit_request': 'Изменить запрос',
          'save_changes': 'Сохранить изменения',
          'edit_success': 'Запрос обновлён',
          'edit_error': 'Не удалось обновить запрос',
          'invalid_time_range': 'Время окончания должно быть позже начала',
          'time_must_be_future': 'Дата и время запроса должны быть в будущем',
          'no_longer_pending': 'Запрос с ответом уже нельзя изменить',
          'cancel_success': 'Запрос отменен',
          'cancel_error': 'Не удалось отменить запрос',
          'confirm_title': 'Отменить этот запрос?',
          'confirm_body': 'Статус запроса будет изменен на "отменен".',
          'close': 'Закрыть',
          'ok': 'ОК',
          'tap_image': 'Нажмите на изображение для увеличения',
          'images': 'Прикрепленные изображения',
          'open_chat': 'Открыть чат',
          'view_map': 'Открыть карту',
          'no_description': 'Описание не предоставлено',
          'unknown': 'Неизвестно',
        };
      default:
        return {
          'details': 'Request Details',
          'request_type': 'Request Type',
          'worker_name': 'Worker Name',
          'profession_name': 'Profession',
          'work_request': 'Work Request',
          'quote_request': 'Quote Request',
          'date': 'Date',
          'hours': 'Hours',
          'from_time': 'From',
          'to_time': 'To',
          'schedule_template': 'On {date}, between {from} and {to}',
          'location': 'Location',
          'service_location': 'Service Location',
          'service_at_provider': 'I go to the professional',
          'service_at_customer': 'The professional comes to me',
          'service_online': 'Online session',
          'description': 'Description',
          'created_at': 'Created At',
          'additional_details': 'Additional Details',
          'status': 'Status',
          'waiting_for_approval': 'Waiting for approval',
          'reviewed': 'Request reviewed',
          'accepted': 'Accepted',
          'rejected': 'Rejected',
          'cancelled': 'Cancelled',
          'expired': 'Expired — no response',
          'cancel': 'Cancel Request',
          'edit_request': 'Edit Request',
          'save_changes': 'Save Changes',
          'edit_success': 'Request updated',
          'edit_error': 'Failed to update request',
          'invalid_time_range': 'End time must be after the start time',
          'time_must_be_future': 'The requested date and time must be future',
          'no_longer_pending': 'A request that was answered cannot be edited',
          'cancel_success': 'Request cancelled',
          'cancel_error': 'Failed to cancel request',
          'confirm_title': 'Cancel this request?',
          'confirm_body': 'This will update the request status to cancelled.',
          'close': 'Close',
          'ok': 'OK',
          'tap_image': 'Tap image to preview',
          'images': 'Attached Images',
          'open_chat': 'Open Chat',
          'view_map': 'Open Map',
          'no_description': 'No description provided',
          'unknown': 'Unknown',
        };
    }
  }

  String _normalizeStatus(String rawStatus) {
    switch (rawStatus.toLowerCase().trim()) {
      case 'accepted':
        return 'accepted';
      case 'declined':
      case 'rejected':
        return 'rejected';
      case 'cancelled':
        return 'cancelled';
      case 'expired':
        return 'expired';
      default:
        return 'waiting_for_approval';
    }
  }

  String _statusLabel(String status, Map<String, String> strings) {
    switch (status) {
      case 'reviewed':
        return strings['reviewed']!;
      case 'accepted':
        return strings['accepted']!;
      case 'rejected':
        return strings['rejected']!;
      case 'cancelled':
        return strings['cancelled']!;
      case 'expired':
        return strings['expired']!;
      default:
        return strings['waiting_for_approval']!;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'reviewed':
        return Icons.visibility_rounded;
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.block_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'expired':
        return Icons.timer_off_rounded;
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'reviewed':
        return const Color(0xFF1976D2);
      case 'accepted':
        return const Color(0xFF15803D);
      case 'rejected':
      case 'expired':
        return const Color(0xFFB91C1C);
      case 'cancelled':
        return const Color(0xFF475569);
      default:
        return const Color(0xFFB45309);
    }
  }

  String _requestTypeLabel(String type, Map<String, String> strings) {
    switch (type) {
      case 'quote_request':
        return strings['quote_request']!;
      default:
        return strings['work_request']!;
    }
  }

  String _formatDateTime(dynamic value) {
    final dateTime = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
    if (dateTime == null) return '-';

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(dateTime.day)}/${twoDigits(dateTime.month)}/'
        '${dateTime.year} · ${twoDigits(dateTime.hour)}:'
        '${twoDigits(dateTime.minute)}';
  }

  String _requestedScheduleLabel({
    required String date,
    required String? from,
    required String? to,
    required Map<String, String> strings,
  }) {
    if (date.isEmpty || from == null || to == null) return '';

    return strings['schedule_template']!
        .replaceAll('{date}', date)
        .replaceAll('{from}', from)
        .replaceAll('{to}', to);
  }

  TimeOfDay _parseRequestTime(dynamic value, TimeOfDay fallback) {
    final parts = value?.toString().split(':') ?? const <String>[];
    if (parts.length != 2) return fallback;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  DateTime? _parseRequestDate(dynamic value) {
    final parts = value?.toString().split('-') ?? const <String>[];
    if (parts.length != 3) return null;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  Future<void> _editRequest(
    Map<String, dynamic> data,
    Map<String, String> strings,
  ) async {
    if (_isUpdating || _isCancelling) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final storedDate = _parseRequestDate(data['date']);
    final selectedDate = storedDate != null && !storedDate.isBefore(today)
        ? storedDate
        : today;
    final fromTime = _parseRequestTime(
      data['requestedFrom'],
      const TimeOfDay(hour: 8, minute: 0),
    );
    final toTime = _parseRequestTime(
      data['requestedTo'],
      const TimeOfDay(hour: 16, minute: 0),
    );
    final hasSchedule = data['type']?.toString() != 'quote_request';

    final draft = await showModalBottomSheet<_RequestEditDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _RequestEditSheet(
        strings: strings,
        initialDate: selectedDate,
        firstDate: today,
        initialFromTime: fromTime,
        initialToTime: toTime,
        initialDescription: (data['jobDescription'] ?? '').toString(),
        hasSchedule: hasSchedule,
      ),
    );
    if (draft == null || !mounted) return;

    final result = <String, String>{
      'jobDescription': draft.description,
      if (draft.hasSchedule) ...{
        'date': _requestDateValue(draft.date),
        'requestedFrom': _requestTimeValue(draft.fromTime),
        'requestedTo': _requestTimeValue(draft.toTime),
      },
    };

    setState(() => _isUpdating = true);
    var noLongerPending = false;
    try {
      final firestore = FirebaseFirestore.instance;
      final editedNotificationId = firestore.collection('_ids').doc().id;
      await firestore.runTransaction((transaction) async {
        final latestSnapshot = await transaction.get(widget.requestRef);
        final latestData = latestSnapshot.data();
        if (latestData == null ||
            _displayStatusForEdit(latestData) != 'waiting_for_approval') {
          noLongerPending = true;
          throw StateError('request_is_no_longer_pending');
        }

        final updates = <String, dynamic>{
          ...result,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        transaction.update(widget.requestRef, updates);

        final workerId = latestData['workerId']?.toString();
        if (workerId == null || workerId.isEmpty) return;

        if (latestData['reviewedAt'] != null) {
          final originalRequestType = latestData['type']?.toString();
          transaction.set(
            firestore
                .collection('users')
                .doc(workerId)
                .collection('notifications')
                .doc(editedNotificationId),
            <String, dynamic>{
              ...latestData,
              ...result,
              'type': 'request_edited',
              if (originalRequestType != null && originalRequestType.isNotEmpty)
                'requestType': originalRequestType,
              'title': 'בקשה שצפית בה עודכנה',
              'body': 'הלקוח ערך את פרטי הבקשה לאחר שצפית בה.',
              'isRead': false,
              'timestamp': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        final requestToMeId = latestData['workerRequestToMeId']?.toString();
        if (requestToMeId != null && requestToMeId.isNotEmpty) {
          transaction.set(
            firestore
                .collection('users')
                .doc(workerId)
                .collection('RequestToMe')
                .doc(requestToMeId),
            updates,
            SetOptions(merge: true),
          );
        }

        final notificationId = latestData['workerNotificationId']?.toString();
        if (notificationId != null && notificationId.isNotEmpty) {
          transaction.set(
            firestore
                .collection('users')
                .doc(workerId)
                .collection('notifications')
                .doc(notificationId),
            updates,
            SetOptions(merge: true),
          );
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['edit_success']!)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings[noLongerPending ? 'no_longer_pending' : 'edit_error']!,
          ),
        ),
      );
      debugPrint('Failed to update request: $error');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  String _displayStatusForEdit(Map<String, dynamic> data) {
    return isPendingRequestExpired(data)
        ? 'expired'
        : _normalizeStatus((data['status'] ?? 'pending').toString());
  }

  List<String> _extractImageUrls(Map<String, dynamic> data) {
    final urls = <String>[];

    final images = data['images'];
    if (images is List) {
      for (final item in images) {
        if (item is String && item.trim().isNotEmpty) {
          urls.add(item.trim());
        }
      }
    }

    for (final key in const ['imageUrl', 'imageURL', 'image']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        urls.add(value.trim());
      }
    }

    return urls.toSet().toList();
  }

  Future<void> _cancelRequest(
    Map<String, dynamic> data,
    Map<String, String> strings,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings['confirm_title']!),
        content: Text(strings['confirm_body']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings['close']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
            ),
            child: Text(strings['ok']!),
          ),
        ],
      ),
    );

    if (confirm != true || _isCancelling) return;

    setState(() => _isCancelling = true);
    try {
      final workerId = data['workerId']?.toString();
      final workerNotificationId = data['workerNotificationId']?.toString();
      final batch = FirebaseFirestore.instance.batch();

      batch.update(widget.requestRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      if (workerId != null &&
          workerId.isNotEmpty &&
          workerNotificationId != null &&
          workerNotificationId.isNotEmpty) {
        batch.set(
          FirebaseFirestore.instance
              .collection('users')
              .doc(workerId)
              .collection('notifications')
              .doc(workerNotificationId),
          {'status': 'cancelled', 'cancelledAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['cancel_success']!)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['cancel_error']!)));
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 280,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, _, _) => Container(
                    height: 280,
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(ctx),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMap(double lat, double lng) async {
    final languageCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    await MapAppLauncher.openLocation(
      context: context,
      latitude: lat,
      longitude: lng,
      languageCode: languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final code = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = code == 'he' || code == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(strings['details']!),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? widget.initialData;
            final normalizedStatus = isPendingRequestExpired(data)
                ? 'expired'
                : _normalizeStatus((data['status'] ?? 'pending').toString());
            final requestType = _requestTypeLabel(
              (data['type'] ?? 'work_request').toString(),
              strings,
            );
            final from = data['requestedFrom']?.toString();
            final to = data['requestedTo']?.toString();
            final requestedDate = (data['date'] ?? '').toString().trim();
            final requestedSchedule = _requestedScheduleLabel(
              date: requestedDate,
              from: from,
              to: to,
              strings: strings,
            );
            final createdAt = _formatDateTime(data['timestamp']);
            final description = (data['jobDescription'] ?? '')
                .toString()
                .trim();
            final imageUrls = _extractImageUrls(data);
            final workerName =
                (data['toName'] ??
                        data['workerName'] ??
                        data['fromName'] ??
                        strings['unknown'])
                    .toString();
            final professionName = _localizedProfessionName(
              (data['profession'] ?? data['professionName'] ?? '').toString(),
              code,
            );
            final latValue = data['latitude'] ?? data['lat'];
            final lngValue = data['longitude'] ?? data['lng'] ?? data['long'];
            final lat = latValue is num
                ? latValue.toDouble()
                : double.tryParse('$latValue');
            final lng = lngValue is num
                ? lngValue.toDouble()
                : double.tryParse('$lngValue');
            final hasMap = lat != null && lng != null;
            final canChat = data['workerId']?.toString().isNotEmpty ?? false;
            final visualStatus =
                normalizedStatus == 'waiting_for_approval' &&
                    data['reviewedAt'] != null
                ? 'reviewed'
                : normalizedStatus;
            final statusColor = _statusColor(visualStatus);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(statusColor, Colors.black, 0.22)!,
                        statusColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.2),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _statusIcon(visualStatus),
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings['request_type']!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  requestType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    fontSize: 19,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _statusLabel(visualStatus, strings),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  children: [
                    _detailRow(
                      Icons.person_outline_rounded,
                      strings['worker_name']!,
                      workerName,
                    ),
                    if (professionName.isNotEmpty)
                      _detailRow(
                        Icons.handyman_outlined,
                        strings['profession_name']!,
                        professionName,
                      ),
                    _detailRow(
                      Icons.location_on_outlined,
                      strings['location']!,
                      (data['locationName'] ?? strings['unknown']!).toString(),
                    ),
                    _detailRow(
                      Icons.history_rounded,
                      strings['created_at']!,
                      createdAt,
                      showDivider: false,
                    ),
                  ],
                ),
                if (hasMap || canChat) ...[
                  const SizedBox(height: 12),
                  _quickActions(
                    data: data,
                    strings: strings,
                    hasMap: hasMap,
                    latitude: lat,
                    longitude: lng,
                    canChat: canChat,
                  ),
                ],
                const SizedBox(height: 12),
                _sectionCard(
                  title: strings['description']!,
                  children: [
                    if (requestedSchedule.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.event_available_outlined,
                              size: 21,
                              color: Color(0xFF1976D2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  requestedSchedule,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      description.isEmpty
                          ? strings['no_description']!
                          : description,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        height: 1.5,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: strings['images']!,
                    subtitle: strings['tap_image']!,
                    children: [
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageUrls.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final imageUrl = imageUrls[index];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _openImagePreview(imageUrl),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    imageUrl,
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 92,
                                      height: 92,
                                      color: const Color(0xFFF1F5F9),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (normalizedStatus == 'waiting_for_approval')
                  _actionButtons(data, strings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionCard({
    String? title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: const Color(0xFF1976D2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }

  Widget _quickActions({
    required Map<String, dynamic> data,
    required Map<String, String> strings,
    required bool hasMap,
    required double? latitude,
    required double? longitude,
    required bool canChat,
  }) {
    final buttons = <Widget>[
      if (hasMap)
        OutlinedButton.icon(
          onPressed: () => _openMap(latitude!, longitude!),
          icon: const Icon(Icons.map_outlined, size: 20),
          label: Text(strings['view_map']!),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: const Color(0xFF0F172A),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      if (canChat)
        FilledButton.tonalIcon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatPage(
                receiverId: data['workerId'].toString(),
                receiverName:
                    (data['toName'] ?? data['workerName'] ?? strings['unknown'])
                        .toString(),
              ),
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
          label: Text(strings['open_chat']!),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: const Color(0xFFDBEAFE),
            foregroundColor: const Color(0xFF1E3A8A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
    ];

    return Row(
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(child: buttons[index]),
        ],
      ],
    );
  }

  Widget _actionButtons(
    Map<String, dynamic> data,
    Map<String, String> strings,
  ) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _isUpdating || _isCancelling
                  ? null
                  : () => _editRequest(data, strings),
              icon: _isUpdating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
              label: Text(strings['edit_request']!),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isCancelling || _isUpdating
                  ? null
                  : () => _cancelRequest(data, strings),
              icon: _isCancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined),
              label: Text(strings['cancel']!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2),
                disabledBackgroundColor: const Color(0xFFFEE2E2),
                foregroundColor: const Color(0xFFB91C1C),
                elevation: 0,
                side: const BorderSide(color: Color(0xFFFECACA)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestEditDraft {
  const _RequestEditDraft({
    required this.date,
    required this.fromTime,
    required this.toTime,
    required this.description,
    required this.hasSchedule,
  });

  final DateTime date;
  final TimeOfDay fromTime;
  final TimeOfDay toTime;
  final String description;
  final bool hasSchedule;
}

class _RequestEditSheet extends StatefulWidget {
  const _RequestEditSheet({
    required this.strings,
    required this.initialDate,
    required this.firstDate,
    required this.initialFromTime,
    required this.initialToTime,
    required this.initialDescription,
    required this.hasSchedule,
  });

  final Map<String, String> strings;
  final DateTime initialDate;
  final DateTime firstDate;
  final TimeOfDay initialFromTime;
  final TimeOfDay initialToTime;
  final String initialDescription;
  final bool hasSchedule;

  @override
  State<_RequestEditSheet> createState() => _RequestEditSheetState();
}

class _RequestEditSheetState extends State<_RequestEditSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _fromTime;
  late TimeOfDay _toTime;
  late final TextEditingController _descriptionController;
  bool _hasInvalidTimeRange = false;
  bool _timeMustBeFuture = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _fromTime = widget.initialFromTime;
    _toTime = widget.initialToTime;
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: widget.firstDate,
      lastDate: DateTime(widget.firstDate.year + 5),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedDate = picked;
      _timeMustBeFuture = false;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _fromTime : _toTime,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isStart) {
        _fromTime = picked;
      } else {
        _toTime = picked;
      }
      _hasInvalidTimeRange = false;
      _timeMustBeFuture = false;
    });
  }

  void _submit() {
    final fromMinutes = _fromTime.hour * 60 + _fromTime.minute;
    final toMinutes = _toTime.hour * 60 + _toTime.minute;
    if (widget.hasSchedule && toMinutes < fromMinutes) {
      setState(() => _hasInvalidTimeRange = true);
      return;
    }

    final requestedStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _fromTime.hour,
      _fromTime.minute,
    );
    if (widget.hasSchedule && !requestedStart.isAfter(DateTime.now())) {
      setState(() => _timeMustBeFuture = true);
      return;
    }

    Navigator.pop(
      context,
      _RequestEditDraft(
        date: _selectedDate,
        fromTime: _fromTime,
        toTime: _toTime,
        description: _descriptionController.text.trim(),
        hasSchedule: widget.hasSchedule,
      ),
    );
  }

  Widget _timeButton({required bool isStart}) {
    final label = widget.strings[isStart ? 'from_time' : 'to_time']!;
    final value = isStart ? _fromTime : _toTime;
    return OutlinedButton(
      onPressed: () => _pickTime(isStart: isStart),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            _requestTimeValue(value),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_calendar_outlined,
                  color: Color(0xFF1976D2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings['edit_request']!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.hasSchedule) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    '${strings['date']!}: ${_requestDateValue(_selectedDate)}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _timeButton(isStart: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _timeButton(isStart: false)),
                ],
              ),
              if (_hasInvalidTimeRange) ...[
                const SizedBox(height: 8),
                _validationMessage(strings['invalid_time_range']!),
              ],
              if (_timeMustBeFuture) ...[
                const SizedBox(height: 8),
                _validationMessage(strings['time_must_be_future']!),
              ],
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: strings['description']!,
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 56),
                  child: Icon(Icons.notes_rounded),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings['close']!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(strings['save_changes']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _validationMessage(String message) {
    return Text(
      message,
      style: const TextStyle(
        color: Color(0xFFB91C1C),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
