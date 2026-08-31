import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/map_app_launcher.dart';
import 'package:untitled1/services/notification_service.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/utils/request_expiration.dart';

class RequestDetailsPage extends StatefulWidget {
  final String notificationId;
  final Map<String, dynamic> data;

  const RequestDetailsPage({
    super.key,
    required this.notificationId,
    required this.data,
  });

  @override
  State<RequestDetailsPage> createState() => _RequestDetailsPageState();
}

class _RequestDetailsPageState extends State<RequestDetailsPage> {
  late TimeOfDay _availableFrom;
  late TimeOfDay _availableTo;
  bool _isLoading = false;
  bool _reviewTrackingStarted = false;
  final _priceController = TextEditingController();
  final _quoteDescController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final reqFrom = widget.data['requestedFrom'];
    final reqTo = widget.data['requestedTo'];

    if (reqFrom != null) {
      try {
        final parts = reqFrom.split(':');
        _availableFrom = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } catch (_) {
        _availableFrom = const TimeOfDay(hour: 8, minute: 0);
      }
    } else {
      _availableFrom = const TimeOfDay(hour: 8, minute: 0);
    }

    if (reqTo != null) {
      try {
        final parts = reqTo.split(':');
        _availableTo = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } catch (_) {
        _availableTo = const TimeOfDay(hour: 16, minute: 0);
      }
    } else {
      _availableTo = const TimeOfDay(hour: 16, minute: 0);
    }

    _markRequestAsSeenAndReviewed();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quoteDescController.dispose();
    super.dispose();
  }

  List<Map<String, String>> _normalizePartialRanges(dynamic value) {
    if (value is List) {
      final ranges = value
          .map((item) => Map<String, String>.from(item as Map))
          .where((item) => item['from'] != null && item['to'] != null)
          .toList();
      ranges.sort(
        (a, b) => _timeStringToMinutes(
          a['from']!,
        ).compareTo(_timeStringToMinutes(b['from']!)),
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

  int _timeStringToMinutes(String value) {
    final parts = value.split(':');
    return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
  }

  String _normalizeRequestStatus(dynamic raw) {
    final status = (raw ?? '').toString().trim().toLowerCase();
    switch (status) {
      case 'waiting_for_approval':
      case 'pending':
        return 'pending';
      case 'accepted':
        return 'accepted';
      case 'declined':
      case 'rejected':
        return 'declined';
      case 'cancelled':
        return 'cancelled';
      default:
        return status;
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
          'title': 'פרטי בקשת עבודה',
          'summary': 'סיכום הבקשה',
          'client': 'לקוח:',
          'location': 'מיקום:',
          'date': 'תאריך:',
          'request_sent_at': 'הבקשה נשלחה:',
          'requested_hours': 'שעות מבוקשות:',
          'job_description': 'תיאור העבודה:',
          'images': 'תמונות מצורפות:',
          'my_arrival': 'מתי אוכל להגיע?',
          'arrival_hint': 'הקשו על שעות ההגעה כדי לעדכן זמינות',
          'from': 'מ-',
          'to': 'עד',
          'accept': 'אישור והוספה ליומן',
          'decline': 'דחיית בקשה',
          'confirm_accept_title': 'לאשר את הבקשה?',
          'confirm_accept_body': 'הבקשה תאושר ותתווסף ליומן שלך.',
          'confirm_decline_title': 'לדחות את הבקשה?',
          'confirm_decline_body': 'הלקוח יקבל הודעה שהבקשה נדחתה.',
          'success': 'הבקשה אושרה בהצלחה',
          'declined': 'הבקשה נדחתה',
          'pending_status': 'הבקשה נבדקה',
          'cancelled_status': 'הבקשה בוטלה',
          'expired_status': 'פג תוקף — ללא מענה',
          'view_map': 'צפה במיקום במפה',
          'close': 'סגור',
          'confirm': 'אישור',
          'error_missing_id': 'שגיאה: חסר מזהה לקוח',
          'error_not_found': 'שגיאה: משתמש לא נמצא',
          'quote_price_label': 'הצעת מחיר:',
          'quote_price_hint': 'הקלד מחיר...',
          'price_required': 'יש להזין מחיר',
          'send_quote': 'שליחת הצעת מחיר',
          'confirm_send_quote_title': 'לשלוח הצעת מחיר?',
          'confirm_send_quote_body': 'הלקוח יקבל את הצעת המחיר שלך.',
          'quote_sent': 'הצעת המחיר נשלחה בהצלחה',
          'quote_description_hint': 'הוסף הערה ללקוח (אופציונלי)...',
          'open_chat': 'פתח צ\'אט',
          'unknown': 'לא ידוע',
          'not_specified': 'לא צוין',
          'no_description': 'לא סופק תיאור',
          'error_prefix': 'שגיאה: {error}',
        };
      case 'ar':
        return {
          'title': 'تفاصيل طلب العمل',
          'summary': 'ملخص الطلب',
          'client': 'العميل:',
          'location': 'الموقع:',
          'date': 'التاريخ:',
          'request_sent_at': 'تاريخ إرسال الطلب:',
          'requested_hours': 'الساعات المطلوبة:',
          'job_description': 'وصف العمل:',
          'images': 'الصور المرفقة:',
          'my_arrival': 'متى يمكنني الوصول؟',
          'arrival_hint': 'اضغط على أوقات الوصول لتحديث التوفر',
          'from': 'من',
          'to': 'إلى',
          'accept': 'قبول وإضافة للجدول',
          'decline': 'رفض الطلب',
          'confirm_accept_title': 'قبول الطلب؟',
          'confirm_accept_body': 'سيتم قبول الطلب وإضافته إلى جدولك.',
          'confirm_decline_title': 'رفض الطلب؟',
          'confirm_decline_body': 'سيتم إشعار العميل بأنه تم رفض الطلب.',
          'success': 'تم قبول الطلب بنجاح',
          'declined': 'تم رفض الطلب',
          'pending_status': 'تمت مراجعة الطلب',
          'cancelled_status': 'تم إلغاء الطلب',
          'expired_status': 'منتهي الصلاحية — دون رد',
          'view_map': 'عرض الموقع على الخريطة',
          'close': 'إغلاق',
          'confirm': 'تأكيد',
          'error_missing_id': 'خطأ: معرف العميل مفقود',
          'error_not_found': 'خطأ: المستخدم غير موجود',
          'quote_price_label': 'عرض السعر:',
          'quote_price_hint': 'اكتب السعر...',
          'price_required': 'يرجى إدخال السعر',
          'send_quote': 'إرسال عرض السعر',
          'confirm_send_quote_title': 'إرسال عرض السعر؟',
          'confirm_send_quote_body': 'سيتلقى العميل عرض السعر الخاص بك.',
          'quote_sent': 'تم إرسال عرض السعر بنجاح',
          'quote_description_hint': 'أضف ملاحظة للعميل (اختياري)...',
          'open_chat': 'فتح المحادثة',
          'unknown': 'غير معروف',
          'not_specified': 'غير محدد',
          'no_description': 'لم يتم تقديم وصف',
          'error_prefix': 'خطأ: {error}',
        };
      case 'am':
        return {
          'title': 'የስራ ጥያቄ ዝርዝሮች',
          'summary': 'የጥያቄ ማጠቃለያ',
          'client': 'ደንበኛ:',
          'location': 'አካባቢ:',
          'date': 'ቀን:',
          'request_sent_at': 'ጥያቄው የተላከበት ጊዜ:',
          'requested_hours': 'የተጠየቁ ሰዓቶች:',
          'job_description': 'የስራ መግለጫ:',
          'images': 'የተያያዙ ምስሎች:',
          'my_arrival': 'መቼ መድረስ እችላለሁ?',
          'arrival_hint': 'የመድረሻ ሰዓቶችን በመጫን ዝግጁነትዎን ያዘምኑ',
          'from': 'ከ',
          'to': 'እስከ',
          'accept': 'ተቀበል እና ወደ መርሃ ግብር አክል',
          'decline': 'ጥያቄውን አትቀበል',
          'confirm_accept_title': 'ይህን ጥያቄ ልቀበል?',
          'confirm_accept_body': 'ጥያቄው ይፀድቃል እና ወደ መርሃ ግብርዎ ይጨምራል።',
          'confirm_decline_title': 'ይህን ጥያቄ ልክድ?',
          'confirm_decline_body': 'ደንበኛው ጥያቄው መተዉን ይቀበላል።',
          'success': 'ጥያቄው በተሳካ ሁኔታ ተቀባ',
          'declined': 'ጥያቄው ተከልክሏል',
          'pending_status': 'ጥያቄው ታይቷል',
          'cancelled_status': 'ጥያቄው ተሰርዟል',
          'expired_status': 'ጊዜው አልፏል — ምላሽ የለም',
          'view_map': 'አካባቢን በካርታ ላይ ክፈት',
          'close': 'ዝጋ',
          'confirm': 'እሺ',
          'error_missing_id': 'ስህተት: የደንበኛ መለያ የለም',
          'error_not_found': 'ስህተት: ተጠቃሚው አልተገኘም',
          'quote_price_label': 'የእርስዎ ዋጋ:',
          'quote_price_hint': 'ዋጋ ያስገቡ...',
          'price_required': 'እባክዎ ዋጋ ያስገቡ',
          'send_quote': 'የዋጋ ቅናሽ ላክ',
          'confirm_send_quote_title': 'ይህን ዋጋ ልላክ?',
          'confirm_send_quote_body': 'ደንበኛው የእርስዎን የዋጋ ቅናሽ ይቀበላል።',
          'quote_sent': 'የዋጋ ቅናሹ በተሳካ ሁኔታ ተልኳል',
          'quote_description_hint': 'ለደንበኛው ማስታወሻ ያክሉ (አማራጭ)...',
          'open_chat': 'ቻት ክፈት',
          'unknown': 'ያልታወቀ',
          'not_specified': 'አልተገለጸም',
          'no_description': 'ምንም መግለጫ አልተሰጠም',
          'error_prefix': 'ስህተት: {error}',
        };
      case 'ru':
        return {
          'title': 'Детали запроса',
          'summary': 'Сводка запроса',
          'client': 'Клиент:',
          'location': 'Локация:',
          'date': 'Дата:',
          'request_sent_at': 'Запрос отправлен:',
          'requested_hours': 'Запрошенные часы:',
          'job_description': 'Описание работы:',
          'images': 'Прикрепленные изображения:',
          'my_arrival': 'Когда я могу приехать?',
          'arrival_hint':
              'Нажмите на время прибытия, чтобы обновить доступность',
          'from': 'С',
          'to': 'До',
          'accept': 'Принять и добавить в расписание',
          'decline': 'Отклонить запрос',
          'confirm_accept_title': 'Принять этот запрос?',
          'confirm_accept_body':
              'Запрос будет принят и добавлен в ваше расписание.',
          'confirm_decline_title': 'Отклонить этот запрос?',
          'confirm_decline_body':
              'Клиент получит уведомление, что вы отклонили запрос.',
          'success': 'Запрос успешно принят',
          'declined': 'Запрос отклонен',
          'pending_status': 'Запрос просмотрен',
          'cancelled_status': 'Запрос отменён',
          'expired_status': 'Срок истёк — нет ответа',
          'view_map': 'Открыть локацию на карте',
          'close': 'Закрыть',
          'confirm': 'Подтвердить',
          'error_missing_id': 'Ошибка: отсутствует ID клиента',
          'error_not_found': 'Ошибка: пользователь не найден',
          'quote_price_label': 'Ваше предложение:',
          'quote_price_hint': 'Введите цену...',
          'price_required': 'Пожалуйста, укажите цену',
          'send_quote': 'Отправить предложение',
          'confirm_send_quote_title': 'Отправить это предложение?',
          'confirm_send_quote_body': 'Клиент получит ваше ценовое предложение.',
          'quote_sent': 'Предложение успешно отправлено',
          'quote_description_hint':
              'Добавьте заметку для клиента (необязательно)...',
          'open_chat': 'Открыть чат',
          'unknown': 'Неизвестно',
          'not_specified': 'Не указано',
          'no_description': 'Описание не предоставлено',
          'error_prefix': 'Ошибка: {error}',
        };
      default:
        return {
          'title': 'Work Request Details',
          'summary': 'Request Summary',
          'client': 'Client:',
          'location': 'Location:',
          'date': 'Date:',
          'request_sent_at': 'Request sent:',
          'requested_hours': 'Requested Hours:',
          'job_description': 'Job Description:',
          'images': 'Attached Images:',
          'my_arrival': 'When can I arrive?',
          'arrival_hint': 'Tap arrival times to update your availability',
          'from': 'From',
          'to': 'To',
          'accept': 'Accept & Add to Schedule',
          'decline': 'Decline Request',
          'confirm_accept_title': 'Accept this request?',
          'confirm_accept_body':
              'This request will be accepted and added to your schedule.',
          'confirm_decline_title': 'Decline this request?',
          'confirm_decline_body':
              'The client will be notified that you declined this request.',
          'success': 'Request accepted successfully',
          'declined': 'Request declined',
          'pending_status': 'Request reviewed',
          'cancelled_status': 'Request cancelled',
          'expired_status': 'Expired — no response',
          'view_map': 'View location on Map',
          'close': 'Close',
          'confirm': 'Confirm',
          'error_missing_id': 'Error: Missing Client ID',
          'error_not_found': 'Error: User not found',
          'quote_price_label': 'Your Quote:',
          'quote_price_hint': 'Enter price...',
          'price_required': 'Please enter a price',
          'send_quote': 'Send Quote',
          'confirm_send_quote_title': 'Send this quote?',
          'confirm_send_quote_body':
              'The client will receive your price quote.',
          'quote_sent': 'Quote sent successfully',
          'quote_description_hint': 'Add a note to the client (optional)...',
          'open_chat': 'Open Chat',
          'unknown': 'Unknown',
          'not_specified': 'Not specified',
          'no_description': 'No description provided',
          'error_prefix': 'Error: {error}',
        };
    }
  }

  Future<void> _confirmAndProcess(bool accept) async {
    final strings = _getLocalizedStrings(context);

    if (isPendingRequestExpired(widget.data)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This request has expired — no response was sent.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          accept
              ? strings['confirm_accept_title']!
              : strings['confirm_decline_title']!,
        ),
        content: Text(
          accept
              ? strings['confirm_accept_body']!
              : strings['confirm_decline_body']!,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings['close']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings['confirm']!),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _processRequest(accept);
    }
  }

  Widget _buildPriceInput(Map<String, String> strings) {
    return _sectionCard(
      title: strings['quote_price_label']!,
      children: [
        TextField(
          controller: _priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: strings['quote_price_hint'],
            prefixIcon: const Icon(Icons.money),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _quoteDescController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: strings['quote_description_hint'],
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.notes_rounded),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndSendQuote() async {
    final price = _priceController.text.trim();
    final strings = _getLocalizedStrings(context);
    if (price.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['price_required']!)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings['confirm_send_quote_title']!),
        content: Text(strings['confirm_send_quote_body']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings['close']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings['confirm']!),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _sendQuoteToClient(price);
    }
  }

  Future<void> _sendQuoteToClient(String price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final clientId = widget.data['fromId'];
    final requestId = widget.data['requestId']?.toString();
    final strings = _getLocalizedStrings(context);
    if (clientId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['error_missing_id']!)));
      return;
    }
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;
    try {
      final notifTitle = strings['send_quote']!;
      final notifBody =
          "${user.displayName ?? 'The professional'} sent you a quote: $price";
      final desc = _quoteDescController.text.trim();
      final batch = firestore.batch();
      final clientNotifRef = firestore
          .collection('users')
          .doc(clientId)
          .collection('notifications')
          .doc();
      batch.set(clientNotifRef, {
        'type': 'quote_response',
        'fromId': user.uid,
        'fromName': user.displayName ?? 'Professional',
        'price': price,
        if (desc.isNotEmpty) 'description': desc,
        'title': notifTitle,
        'body': notifBody,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      batch.update(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .doc(widget.notificationId),
        {'status': 'accepted'},
      );
      if (requestId != null && requestId.isNotEmpty) {
        batch.set(
          firestore
              .collection('users')
              .doc(clientId)
              .collection('requests')
              .doc(requestId),
          {
            'status': 'accepted',
            'quotePrice': price,
            if (desc.isNotEmpty) 'quoteDescription': desc,
            'quoteSentAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      await NotificationService.sendPushNotification(
        targetUserId: clientId,
        title: notifTitle,
        body: notifBody,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['quote_sent']!)));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("FIRESTORE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['error_prefix']!.replaceFirst('{error}', e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openMap() async {
    final lat = widget.data['latitude'];
    final lng = widget.data['longitude'];
    if (lat != null && lng != null) {
      final languageCode = Provider.of<LanguageProvider>(
        context,
        listen: false,
      ).locale.languageCode;
      await MapAppLauncher.openLocation(
        context: context,
        latitude: (lat as num).toDouble(),
        longitude: (lng as num).toDouble(),
        languageCode: languageCode,
      );
    }
  }

  List<String> _extractImageUrls(dynamic raw) {
    if (raw is! List) return const [];
    final urls = <String>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        urls.add(item);
      }
    }
    return urls;
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

  Future<void> _markRequestAsSeenAndReviewed() async {
    if (_reviewTrackingStarted) return;
    _reviewTrackingStarted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final clientId = widget.data['fromId']?.toString();
    final requestId = widget.data['requestId']?.toString();
    final firestore = FirebaseFirestore.instance;

    final workerNotificationId =
        widget.data['workerNotificationId']?.toString() ??
        widget.notificationId;
    final workerNotificationRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(workerNotificationId);

    final workerRequestToMeId = widget.data['workerRequestToMeId']?.toString();
    DocumentReference<Map<String, dynamic>>? workerRequestToMeRef;
    if (workerRequestToMeId != null && workerRequestToMeId.isNotEmpty) {
      workerRequestToMeRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('RequestToMe')
          .doc(workerRequestToMeId);
    }

    DocumentReference<Map<String, dynamic>>? clientRequestRef;
    if (clientId != null &&
        clientId.isNotEmpty &&
        requestId != null &&
        requestId.isNotEmpty) {
      clientRequestRef = firestore
          .collection('users')
          .doc(clientId)
          .collection('requests')
          .doc(requestId);
    }

    final reviewUpdates = <String, dynamic>{
      'seenAt': FieldValue.serverTimestamp(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': user.uid,
    };

    Future<void> updateReviewCopy(
      DocumentReference<Map<String, dynamic>> reference,
      String copyName,
    ) async {
      try {
        await reference.update(reviewUpdates);
      } catch (e) {
        // The request copies are deliberately independent: an older request
        // may be missing one mirror, and that must not block the canonical
        // customer request from being marked as reviewed.
        debugPrint('Request review tracking error ($copyName): $e');
      }
    }

    await Future.wait([
      updateReviewCopy(workerNotificationRef, 'worker notification'),
      if (workerRequestToMeRef != null)
        updateReviewCopy(workerRequestToMeRef, 'worker request'),
      if (clientRequestRef != null)
        updateReviewCopy(clientRequestRef, 'customer request'),
    ]);
  }

  Future<void> _processRequest(bool accept) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final clientId = widget.data['fromId'];
    final requestId = widget.data['requestId']?.toString();
    final strings = _getLocalizedStrings(context);

    if (clientId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['error_missing_id']!)));
      return;
    }

    setState(() => _isLoading = true);

    final firestore = FirebaseFirestore.instance;
    final String date = widget.data['date'];

    try {
      final batch = firestore.batch();
      String? notifTitle;
      String? notifBody;

      if (accept) {
        final fStr =
            "${_availableFrom.hour.toString().padLeft(2, '0')}:${_availableFrom.minute.toString().padLeft(2, '0')}";
        final tStr =
            "${_availableTo.hour.toString().padLeft(2, '0')}:${_availableTo.minute.toString().padLeft(2, '0')}";

        // 2. Update Pro's Schedule in 'Schedule' sub-collection under 'users'
        final scheduleRef = firestore
            .collection('publicWorkerProfiles')
            .doc(user.uid)
            .collection('Schedule')
            .doc('info');

        final scheduleSnapshot = await scheduleRef.get();
        final partialWorkDays =
            (scheduleSnapshot.data()?['partialWorkDays'] as Map?) ?? {};
        final mergedRanges = _normalizePartialRanges(partialWorkDays[date]);
        mergedRanges.add({'from': fStr, 'to': tStr});
        mergedRanges.sort(
          (a, b) => _timeStringToMinutes(
            a['from']!,
          ).compareTo(_timeStringToMinutes(b['from']!)),
        );

        batch.set(scheduleRef, {
          'availableDates': FieldValue.arrayUnion([date]),
          'partialWorkDays.$date': mergedRanges,
        }, SetOptions(merge: true));

        notifTitle = strings['accept'] ?? 'Request Accepted';
        notifBody =
            "${user.displayName ?? 'The professional'} accepted your request for $date. Arrival: $fStr - $tStr";

        // 3. Notify Client in Firestore under 'users' collection
        final clientNotifRef = firestore
            .collection('users')
            .doc(clientId)
            .collection('notifications')
            .doc();
        batch.set(clientNotifRef, {
          'type': 'request_accepted',
          'fromId': user.uid,
          'fromName': user.displayName ?? 'Professional',
          'title': notifTitle,
          'body': notifBody,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        notifTitle = strings['declined'] ?? 'Request Declined';
        notifBody =
            "${user.displayName ?? 'The professional'} cannot make it on $date";

        // Notify Client about Decline in Firestore
        final clientNotifRef = firestore
            .collection('users')
            .doc(clientId)
            .collection('notifications')
            .doc();
        batch.set(clientNotifRef, {
          'type': 'request_declined',
          'fromId': user.uid,
          'fromName': user.displayName ?? 'Professional',
          'title': notifTitle,
          'body': notifBody,
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // 4. Update current notification status in Pro's list under 'users' collection
      batch.update(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .doc(widget.notificationId),
        {'status': accept ? 'accepted' : 'declined'},
      );

      if (requestId != null && requestId.isNotEmpty) {
        batch.set(
          firestore
              .collection('users')
              .doc(clientId)
              .collection('requests')
              .doc(requestId),
          {
            'status': accept ? 'accepted' : 'declined',
            if (accept)
              'acceptedWindow': {
                'from':
                    "${_availableFrom.hour.toString().padLeft(2, '0')}:${_availableFrom.minute.toString().padLeft(2, '0')}",
                'to':
                    "${_availableTo.hour.toString().padLeft(2, '0')}:${_availableTo.minute.toString().padLeft(2, '0')}",
              },
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      // 5. Send FCM Push Notification to Client
      await NotificationService.sendPushNotification(
        targetUserId: clientId,
        title: notifTitle,
        body: notifBody,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept ? strings['success']! : strings['declined']!),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("FIRESTORE ERROR: $e");
      if (mounted) {
        final strings = _getLocalizedStrings(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              strings['error_prefix']!.replaceFirst('{error}', e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final data = widget.data;
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final isQuoteRequest =
        data['type'] == 'quote_request' ||
        data['requestType'] == 'quote_request';
    final normalizedStatus = isPendingRequestExpired(data)
        ? 'expired'
        : _normalizeRequestStatus(data['status']);
    final isPending = normalizedStatus == 'pending';
    final statusColor = _statusColor(normalizedStatus);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(strings['title']!),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusHero(strings, normalizedStatus, statusColor),
                  const SizedBox(height: 12),
                  _buildInfoCard(strings, data),
                  if ((data['fromId'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildQuickActions(strings, data),
                  ],
                  if (isQuoteRequest && isPending) ...[
                    const SizedBox(height: 14),
                    _buildPriceInput(strings),
                  ],
                  if (!isQuoteRequest) ...[
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: strings['my_arrival']!,
                      subtitle: strings['arrival_hint']!,
                      children: [
                        _buildTimePickers(strings, enabled: isPending),
                      ],
                    ),
                  ],
                  if (isPending) ...[
                    const SizedBox(height: 16),
                    _buildActionButtons(strings),
                  ],
                ],
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasMap(Map<String, dynamic> data) =>
      data['latitude'] != null && data['longitude'] != null;

  String _formatRequestSentAt(Map<String, dynamic> data) {
    final rawTimestamp = data['timestamp'] ?? data['createdAt'];
    DateTime? sentAt;

    if (rawTimestamp is Timestamp) {
      sentAt = rawTimestamp.toDate();
    } else if (rawTimestamp is DateTime) {
      sentAt = rawTimestamp;
    } else if (rawTimestamp is int) {
      sentAt = DateTime.fromMillisecondsSinceEpoch(rawTimestamp);
    } else if (rawTimestamp is String) {
      sentAt = DateTime.tryParse(rawTimestamp);
    }

    if (sentAt == null) return '';
    return intl.DateFormat('dd/MM/yyyy • HH:mm').format(sentAt.toLocal());
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF15803D);
      case 'declined':
      case 'expired':
        return const Color(0xFFB91C1C);
      case 'cancelled':
        return const Color(0xFF475569);
      default:
        return const Color(0xFF1976D2);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'declined':
        return Icons.block_rounded;
      case 'expired':
        return Icons.timer_off_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }

  String _statusLabel(String status, Map<String, String> strings) {
    if (status == 'accepted') return strings['success']!;
    if (status == 'declined') return strings['declined']!;
    if (status == 'cancelled') return strings['cancelled_status']!;
    if (status == 'expired') return strings['expired_status']!;
    return strings['pending_status']!;
  }

  Widget _buildStatusHero(
    Map<String, String> strings,
    String status,
    Color statusColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(statusColor, Colors.black, 0.22)!, statusColor],
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
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_statusIcon(status), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(radius: 3.5, backgroundColor: Colors.white),
                const SizedBox(width: 7),
                Text(
                  _statusLabel(status, strings),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    Map<String, String> strings,
    Map<String, dynamic> data,
  ) {
    final imageUrls = _extractImageUrls(data['images']);
    final requestSentAt = _formatRequestSentAt(data);
    final requestDate = data['date']?.toString().trim() ?? '';
    final requestedFrom = data['requestedFrom']?.toString().trim() ?? '';
    final requestedTo = data['requestedTo']?.toString().trim() ?? '';
    final hasRequestedHours =
        requestedFrom.isNotEmpty && requestedTo.isNotEmpty;
    final hasSchedule = requestDate.isNotEmpty || hasRequestedHours;

    return Column(
      children: [
        _sectionCard(
          children: [
            _buildInfoRow(
              Icons.person_outline_rounded,
              strings['client']!,
              (data['fromName'] ?? strings['unknown']!).toString(),
            ),
            _buildInfoRow(
              Icons.location_on_outlined,
              strings['location']!,
              (data['locationName'] ??
                      data['fromLocation'] ??
                      strings['not_specified']!)
                  .toString(),
              onTap: _hasMap(data) ? _openMap : null,
            ),
            _buildInfoRow(
              Icons.outgoing_mail,
              strings['request_sent_at']!,
              requestSentAt.isEmpty ? strings['not_specified']! : requestSentAt,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: strings['job_description']!,
          children: [
            if (hasSchedule) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    if (requestDate.isNotEmpty)
                      _buildScheduleLine(
                        Icons.calendar_month_outlined,
                        strings['date']!,
                        requestDate,
                      ),
                    if (requestDate.isNotEmpty && hasRequestedHours)
                      const SizedBox(height: 8),
                    if (hasRequestedHours)
                      _buildScheduleLine(
                        Icons.schedule_outlined,
                        strings['requested_hours']!,
                        '$requestedFrom - $requestedTo',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              (data['jobDescription'] ?? strings['no_description']!).toString(),
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
            children: [_buildImagesSection(imageUrls)],
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleLine(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 19, color: const Color(0xFF1976D2)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$label $value',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection(List<String> imageUrls) {
    return SizedBox(
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
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 92,
                      height: 92,
                      color: const Color(0xFFF1F5F9),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => Container(
                    width: 92,
                    height: 92,
                    color: const Color(0xFFF1F5F9),
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          );
        },
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

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool showDivider = true,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
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
                          style: TextStyle(
                            color: onTap == null
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF1976D2),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.map_outlined,
                      size: 20,
                      color: Color(0xFF1976D2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }

  Widget _buildTimePickers(Map<String, String> strings, {bool enabled = true}) {
    return Row(
      children: [
        Expanded(
          child: _buildTimeBox(
            icon: Icons.login_rounded,
            label: strings['from']!,
            time: _availableFrom,
            enabled: enabled,
            onPick: (time) => setState(() => _availableFrom = time),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTimeBox(
            icon: Icons.logout_rounded,
            label: strings['to']!,
            time: _availableTo,
            enabled: enabled,
            onPick: (time) => setState(() => _availableTo = time),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeBox({
    required IconData icon,
    required String label,
    required TimeOfDay time,
    bool enabled = true,
    required Function(TimeOfDay) onPick,
  }) {
    return Material(
      color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) onPick(picked);
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: const Color(0xFF475569)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                time.format(context),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(
    Map<String, String> strings,
    Map<String, dynamic> data,
  ) {
    final clientId = data['fromId']?.toString();
    final clientName = (data['fromName'] ?? '').toString();
    final buttons = <Widget>[
      if (clientId != null && clientId.isNotEmpty)
        FilledButton.tonalIcon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ChatPage(receiverId: clientId, receiverName: clientName),
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

  Widget _buildActionButtons(Map<String, String> strings) {
    final isQuoteRequest =
        widget.data['type'] == 'quote_request' ||
        widget.data['requestType'] == 'quote_request';
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _isLoading
                  ? null
                  : (isQuoteRequest
                        ? _confirmAndSendQuote
                        : () => _confirmAndProcess(true)),
              icon: Icon(
                isQuoteRequest
                    ? Icons.send_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              label: Text(
                isQuoteRequest ? strings['send_quote']! : strings['accept']!,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
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
              onPressed: _isLoading ? null : () => _confirmAndProcess(false),
              icon: const Icon(Icons.close_rounded),
              label: Text(
                strings['decline']!,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2),
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
