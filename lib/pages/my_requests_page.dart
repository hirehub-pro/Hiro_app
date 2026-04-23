import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/my_request_details_page.dart';
import 'package:untitled1/services/language_provider.dart';

class MyRequestsPage extends StatefulWidget {
  const MyRequestsPage({super.key});

  @override
  State<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends State<MyRequestsPage> {
  String _activeFilter = 'all';

  Map<String, String> _strings(BuildContext context) {
    final code = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (code) {
      case 'he':
        return {
          'title': 'הבקשות שלי',
          'empty': 'לא נמצאו בקשות ששלחת',
          'request': 'בקשה',
          'request_type': 'סוג בקשה',
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
          'all': 'הכל',
          'details': 'פרטי בקשה',
          'no_items_for_filter': 'לא נמצאו בקשות בסטטוס זה',
          'tap_for_details': 'הקשו לצפייה בפרטים',
          'cancel': 'בטל בקשה',
          'cancel_success': 'הבקשה בוטלה',
          'cancel_error': 'נכשל בביטול הבקשה',
          'confirm_title': 'לבטל את הבקשה?',
          'confirm_body': 'פעולה זו תעדכן את סטטוס הבקשה ל-בוטל.',
          'close': 'סגור',
          'ok': 'אישור',
        };
      case 'ar':
        return {
          'title': 'طلباتي',
          'empty': 'لا توجد طلبات قمت بإرسالها',
          'request': 'الطلب',
          'request_type': 'نوع الطلب',
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
          'all': 'الكل',
          'details': 'تفاصيل الطلب',
          'no_items_for_filter': 'لا توجد طلبات بهذه الحالة',
          'tap_for_details': 'اضغط لعرض التفاصيل',
          'cancel': 'إلغاء الطلب',
          'cancel_success': 'تم إلغاء الطلب',
          'cancel_error': 'فشل إلغاء الطلب',
          'confirm_title': 'إلغاء الطلب؟',
          'confirm_body': 'سيتم تحديث حالة الطلب إلى ملغي.',
          'close': 'إغلاق',
          'ok': 'تأكيد',
        };
      case 'am':
        return {
          'title': 'ጥያቄዎቼ',
          'empty': 'የላኩት ጥያቄዎች አልተገኙም',
          'request': 'ጥያቄ',
          'request_type': 'የጥያቄ አይነት',
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
          'all': 'ሁሉም',
          'details': 'የጥያቄ ዝርዝሮች',
          'no_items_for_filter': 'በዚህ ሁኔታ ምንም ጥያቄዎች የሉም',
          'tap_for_details': 'ለዝርዝሮች ይጫኑ',
          'cancel': 'ጥያቄ ሰርዝ',
          'cancel_success': 'ጥያቄው ተሰርዟል',
          'cancel_error': 'ጥያቄውን ማሰረዝ አልተሳካም',
          'confirm_title': 'ይህን ጥያቄ ልሰርዝ?',
          'confirm_body': 'ይህ የጥያቄውን ሁኔታ ወደ ተሰረዘ ያዘምናል።',
          'close': 'ዝጋ',
          'ok': 'እሺ',
        };
      case 'ru':
        return {
          'title': 'Мои запросы',
          'empty': 'Отправленные вами запросы не найдены',
          'request': 'Запрос',
          'request_type': 'Тип запроса',
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
          'all': 'Все',
          'details': 'Детали запроса',
          'no_items_for_filter': 'Нет запросов с таким статусом',
          'tap_for_details': 'Нажмите, чтобы посмотреть детали',
          'cancel': 'Отменить запрос',
          'cancel_success': 'Запрос отменен',
          'cancel_error': 'Не удалось отменить запрос',
          'confirm_title': 'Отменить этот запрос?',
          'confirm_body': 'Статус запроса будет изменен на "отменен".',
          'close': 'Закрыть',
          'ok': 'ОК',
        };
      default:
        return {
          'title': 'My Requests',
          'empty': 'No requests found',
          'request': 'Request',
          'request_type': 'Request Type',
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
          'all': 'All',
          'details': 'Request Details',
          'no_items_for_filter': 'No requests with this status',
          'tap_for_details': 'Tap to view details',
          'cancel': 'Cancel Request',
          'cancel_success': 'Request cancelled',
          'cancel_error': 'Failed to cancel request',
          'confirm_title': 'Cancel this request?',
          'confirm_body': 'This will update the request status to cancelled.',
          'close': 'Close',
          'ok': 'OK',
        };
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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_activeFilter == 'all') return docs;
    return docs.where((doc) {
      final status = _normalizeStatus(
        (doc.data()['status'] ?? 'pending').toString(),
      );
      return status == _activeFilter;
    }).toList();
  }

  String _requestTypeLabel(String type, Map<String, String> strings) {
    switch (type) {
      case 'quote_request':
        return strings['quote_request']!;
      case 'work_request':
      default:
        return strings['work_request']!;
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
      case 'waiting_for_approval':
      case 'pending':
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

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF2D8F5B);
      case 'rejected':
        return const Color(0xFFC0392B);
      case 'cancelled':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFFB7791F);
    }
  }

  int _countByStatus(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String status,
  ) {
    if (status == 'all') return docs.length;
    return docs
        .where(
          (doc) =>
              _normalizeStatus(
                (doc.data()['status'] ?? 'pending').toString(),
              ) ==
              status,
        )
        .length;
  }

  Future<void> _cancelRequest(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
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

    if (confirm != true) return;

    try {
      final workerId = data['workerId']?.toString();
      final workerNotificationId = data['workerNotificationId']?.toString();
      final batch = FirebaseFirestore.instance.batch();

      batch.update(ref, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      if (workerId != null &&
          workerId.isNotEmpty &&
          workerNotificationId != null &&
          workerNotificationId.isNotEmpty) {
        batch.update(
          FirebaseFirestore.instance
              .collection('users')
              .doc(workerId)
              .collection('notifications')
              .doc(workerNotificationId),
          {'status': 'cancelled', 'cancelledAt': FieldValue.serverTimestamp()},
        );
      }

      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['cancel_success']!)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['cancel_error']!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(title: Text(strings['title']!)),
          body: Center(child: Text(strings['empty']!)),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('requests')
        .where('type', whereIn: ['work_request', 'quote_request'])
        .snapshots();

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                  snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                )..sort((a, b) {
                  final at = a.data()['timestamp'] as Timestamp?;
                  final bt = b.data()['timestamp'] as Timestamp?;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                });

            if (docs.isEmpty) {
              return Center(child: Text(strings['empty']!));
            }

            final filteredDocs = _applyFilter(docs);
            final waitingCount = _countByStatus(docs, 'waiting_for_approval');
            final acceptedCount = _countByStatus(docs, 'accepted');
            final rejectedCount = _countByStatus(docs, 'rejected');
            final cancelledCount = _countByStatus(docs, 'cancelled');
            final allCount = docs.length;

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {});
                await Future<void>.delayed(const Duration(milliseconds: 250));
              },
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        _countBadge(
                          label: strings['all']!,
                          value: allCount,
                          color: const Color(0xFF0369A1),
                        ),
                        const SizedBox(width: 8),
                        _countBadge(
                          label: strings['waiting_for_approval']!,
                          value: waitingCount,
                          color: const Color(0xFFB7791F),
                        ),
                        const SizedBox(width: 8),
                        _countBadge(
                          label: strings['accepted']!,
                          value: acceptedCount,
                          color: const Color(0xFF2D8F5B),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    alignment: Alignment.centerLeft,
                    margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      '${strings['rejected']!}: $rejectedCount   ${strings['cancelled']!}: $cancelledCount',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildFilterChip(strings['all']!, 'all'),
                        _buildFilterChip(
                          strings['waiting_for_approval']!,
                          'waiting_for_approval',
                        ),
                        _buildFilterChip(strings['accepted']!, 'accepted'),
                        _buildFilterChip(strings['rejected']!, 'rejected'),
                        _buildFilterChip(strings['cancelled']!, 'cancelled'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              Icon(
                                Icons.inbox_outlined,
                                size: 54,
                                color: Colors.blueGrey.shade200,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  strings['no_items_for_filter']!,
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredDocs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final data = doc.data();
                              final status = _normalizeStatus(
                                (data['status'] ?? 'pending').toString(),
                              );
                              final type = (data['type'] ?? 'work_request')
                                  .toString();
                              final date = (data['date'] ?? '-').toString();
                              final from = data['requestedFrom']?.toString();
                              final to = data['requestedTo']?.toString();
                              final body = (data['jobDescription'] ?? '')
                                  .toString();
                              final statusColor = _statusColor(status);

                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MyRequestDetailsPage(
                                        requestRef: doc.reference,
                                        initialData: data,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.02,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                _statusIcon(status),
                                                color: statusColor,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '${strings['request']!}: ${_requestTypeLabel(type, strings)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                _statusLabel(status, strings),
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '${strings['date']!}: $date',
                                          style: const TextStyle(
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                        if (from != null && to != null)
                                          Text(
                                            '${strings['hours']!}: $from - $to',
                                            style: const TextStyle(
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        if (body.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            body,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF475569),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Text(
                                          strings['tap_for_details']!,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (status ==
                                            'waiting_for_approval') ...[
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: isRtl
                                                ? Alignment.centerLeft
                                                : Alignment.centerRight,
                                            child: OutlinedButton.icon(
                                              onPressed: () => _cancelRequest(
                                                context,
                                                doc.reference,
                                                data,
                                                strings,
                                              ),
                                              icon: const Icon(
                                                Icons.cancel_outlined,
                                              ),
                                              label: Text(strings['cancel']!),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(
                                                  0xFFC0392B,
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFFC0392B),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final bool selected = _activeFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _activeFilter = value;
          });
        },
        selectedColor: const Color(0xFFE0F2FE),
        side: BorderSide(
          color: selected ? const Color(0xFF0EA5E9) : const Color(0xFFE2E8F0),
        ),
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF0369A1) : const Color(0xFF334155),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _countBadge({
    required String label,
    required int value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
