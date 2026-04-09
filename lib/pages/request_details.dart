import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/notification_service.dart';
import 'package:untitled1/pages/chat_page.dart';

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
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quoteDescController.dispose();
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
          'title': 'פרטי בקשת עבודה',
          'summary': 'סיכום הבקשה',
          'client': 'לקוח:',
          'location': 'מיקום:',
          'date': 'תאריך:',
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
        };
      case 'ar':
        return {
          'title': 'تفاصيل طلب العمل',
          'summary': 'ملخص الطلب',
          'client': 'العميل:',
          'location': 'الموقع:',
          'date': 'التاريخ:',
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
        };
      default:
        return {
          'title': 'Work Request Details',
          'summary': 'Request Summary',
          'client': 'Client:',
          'location': 'Location:',
          'date': 'Date:',
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
        };
    }
  }

  Future<void> _confirmAndProcess(bool accept) async {
    final strings = _getLocalizedStrings(context);
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings['quote_price_label']!,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: strings['quote_price_hint'],
              prefixIcon: const Icon(Icons.money),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
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
      final clientDoc = await firestore.collection('users').doc(clientId).get();
      if (!clientDoc.exists) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['error_not_found']!)));
        return;
      }
      final String? clientFcmToken = clientDoc.data()?['fcmToken'];
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
      if (clientFcmToken != null) {
        await NotificationService.sendPushNotification(
          targetToken: clientFcmToken,
          title: notifTitle,
          body: notifBody,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['quote_sent']!)));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("FIRESTORE ERROR: $e");
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openMap() async {
    final lat = widget.data['latitude'];
    final lng = widget.data['longitude'];
    if (lat != null && lng != null) {
      final Uri url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
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
                  errorBuilder: (_, __, ___) => Container(
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
                color: Colors.black.withOpacity(0.45),
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
      // 1. Get Client's FCM Token for push notification from unified 'users' collection
      final clientDoc = await firestore.collection('users').doc(clientId).get();
      if (!clientDoc.exists) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['error_not_found']!)));
        return;
      }
      final String? clientFcmToken = clientDoc.data()?['fcmToken'];

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
            .collection('users')
            .doc(user.uid)
            .collection('Schedule')
            .doc('info');

        batch.set(scheduleRef, {
          'availableDates': FieldValue.arrayUnion([date]),
          'partialWorkDays.$date': {'from': fStr, 'to': tStr},
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
      if (clientFcmToken != null) {
        await NotificationService.sendPushNotification(
          targetToken: clientFcmToken,
          title: notifTitle,
          body: notifBody,
        );
      }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
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
    final isQuoteRequest = data['type'] == 'quote_request';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8FC),
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E3A8A),
          elevation: 0,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(strings, data),
                  if (isQuoteRequest) ...[
                    const SizedBox(height: 14),
                    _buildPriceInput(strings),
                  ],
                  if (!isQuoteRequest) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['my_arrival']!,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strings['arrival_hint']!,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTimePickers(strings),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildOpenChatButton(strings),
                  const SizedBox(height: 20),
                  _buildActionButtons(strings),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    Map<String, String> strings,
    Map<String, dynamic> data,
  ) {
    final hasMap = data['latitude'] != null && data['longitude'] != null;
    final imageUrls = _extractImageUrls(data['images']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings['summary']!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 14),
            _buildInfoRow(
              Icons.person,
              strings['client']!,
              data['fromName'] ?? 'Unknown',
            ),
            const Divider(height: 20),
            _buildInfoRow(
              Icons.location_on,
              strings['location']!,
              data['fromLocation'] ?? 'Not specified',
            ),
            if (hasMap) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _openMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(strings['view_map']!),
                ),
              ),
            ],
            const Divider(height: 20),
            _buildInfoRow(
              Icons.calendar_month,
              strings['date']!,
              data['date'] ?? '',
            ),
            if (data['requestedFrom'] != null) ...[
              const Divider(height: 20),
              _buildInfoRow(
                Icons.access_time,
                strings['requested_hours']!,
                "${data['requestedFrom']} - ${data['requestedTo']}",
              ),
            ],
            const Divider(height: 20),
            _buildInfoRow(
              Icons.description,
              strings['job_description']!,
              data['jobDescription'] ?? 'No description provided',
            ),
            if (imageUrls.isNotEmpty) ...[
              const Divider(height: 20),
              _buildImagesSection(strings['images']!, imageUrls),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagesSection(String label, List<String> imageUrls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: Color(0xFF1976D2),
              size: 24,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                      errorBuilder: (_, __, ___) => Container(
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
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF1976D2), size: 24),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePickers(Map<String, String> strings) {
    return Row(
      children: [
        Expanded(
          child: _buildTimeBox(
            icon: Icons.login_rounded,
            label: strings['from']!,
            time: _availableFrom,
            onPick: (time) => setState(() => _availableFrom = time),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTimeBox(
            icon: Icons.logout_rounded,
            label: strings['to']!,
            time: _availableTo,
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
    required Function(TimeOfDay) onPick,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
          );
          if (picked != null) onPick(picked);
        },
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

  Widget _buildOpenChatButton(Map<String, String> strings) {
    final clientId = widget.data['fromId'];
    final clientName = widget.data['fromName'] ?? '';
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: clientId == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatPage(receiverId: clientId, receiverName: clientName),
                ),
              ),
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(
          strings['open_chat']!,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF1E3A8A)),
          foregroundColor: const Color(0xFF1E3A8A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, String> strings) {
    final isQuoteRequest = widget.data['type'] == 'quote_request';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : (isQuoteRequest
                      ? _confirmAndSendQuote
                      : () => _confirmAndProcess(true)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isQuoteRequest
                      ? Icons.send_rounded
                      : Icons.check_circle_outline_rounded,
                ),
                const SizedBox(width: 8),
                Text(
                  isQuoteRequest ? strings['send_quote']! : strings['accept']!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => _confirmAndProcess(false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.close_rounded),
                const SizedBox(width: 8),
                Text(
                  strings['decline']!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
