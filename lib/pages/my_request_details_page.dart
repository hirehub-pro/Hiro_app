import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
          'accepted': 'התקבל',
          'rejected': 'נדחה',
          'cancelled': 'בוטל',
          'cancel': 'בטל בקשה',
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
          'accepted': 'تم القبول',
          'rejected': 'تم الرفض',
          'cancelled': 'تم الإلغاء',
          'cancel': 'إلغاء الطلب',
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
          'accepted': 'ተቀባ',
          'rejected': 'ተቀባይነት አላገኘም',
          'cancelled': 'ተሰርዟል',
          'cancel': 'ጥያቄ ሰርዝ',
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
          'accepted': 'Принято',
          'rejected': 'Отклонено',
          'cancelled': 'Отменено',
          'cancel': 'Отменить запрос',
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
          'accepted': 'Accepted',
          'rejected': 'Rejected',
          'cancelled': 'Cancelled',
          'cancel': 'Cancel Request',
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
      default:
        return 'waiting_for_approval';
    }
  }

  String _statusLabel(String status, Map<String, String> strings) {
    switch (status) {
      case 'accepted':
        return strings['accepted']!;
      case 'rejected':
        return strings['rejected']!;
      case 'cancelled':
        return strings['cancelled']!;
      default:
        return strings['waiting_for_approval']!;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.block_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.hourglass_top_rounded;
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
    if (value is Timestamp) {
      return value.toDate().toString();
    }
    if (value is DateTime) {
      return value.toString();
    }
    return '-';
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
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data?.data() ?? widget.initialData;
            final normalizedStatus = _normalizeStatus(
              (data['status'] ?? 'pending').toString(),
            );
            final requestType = _requestTypeLabel(
              (data['type'] ?? 'work_request').toString(),
              strings,
            );
            final from = data['requestedFrom']?.toString();
            final to = data['requestedTo']?.toString();
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
            final professionName =
                (data['profession'] ?? data['professionName'] ?? '')
                    .toString()
                    .trim();
            final latValue = data['latitude'] ?? data['lat'];
            final lngValue = data['longitude'] ?? data['lng'] ?? data['long'];
            final lat = latValue is num
                ? latValue.toDouble()
                : double.tryParse('$latValue');
            final lng = lngValue is num
                ? lngValue.toDouble()
                : double.tryParse('$lngValue');
            final hasMap = lat != null && lng != null;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _statusIcon(normalizedStatus),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${strings['request_type']!}: $requestType',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusLabel(normalizedStatus, strings),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  children: [
                    _detailRow(strings['worker_name']!, workerName),
                    if (professionName.isNotEmpty)
                      _detailRow(strings['profession_name']!, professionName),
                    _detailRow(
                      strings['date']!,
                      (data['date'] ?? '-').toString(),
                    ),
                    if (from != null && to != null)
                      _detailRow(strings['hours']!, '$from - $to'),
                    _detailRow(
                      strings['location']!,
                      (data['locationName'] ?? strings['unknown']!).toString(),
                    ),
                    _detailRow(strings['created_at']!, createdAt),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (hasMap)
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: () => _openMap(lat, lng),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: Text(strings['view_map']!),
                        ),
                      ),
                    if ((data['workerId']?.toString().isNotEmpty ?? false))
                      SizedBox(
                        height: 44,
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                receiverId: data['workerId'].toString(),
                                receiverName:
                                    (data['toName'] ??
                                            data['workerName'] ??
                                            strings['unknown'])
                                        .toString(),
                              ),
                            ),
                          ),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                          label: Text(strings['open_chat']!),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: strings['description']!,
                  children: [
                    Text(
                      description.isEmpty
                          ? strings['no_description']!
                          : description,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        height: 1.35,
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
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
                                    errorBuilder: (_, __, ___) => Container(
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
                  _actionButtons(data, normalizedStatus, strings),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(
    Map<String, dynamic> data,
    String normalizedStatus,
    Map<String, String> strings,
  ) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isCancelling
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
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
