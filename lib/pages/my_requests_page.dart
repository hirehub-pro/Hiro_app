import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  Future<void> _showRequestDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String normalizedStatus,
    Map<String, String> strings,
  ) async {
    final date = (data['date'] ?? '-').toString();
    final from = data['requestedFrom']?.toString();
    final to = data['requestedTo']?.toString();
    final body = (data['jobDescription'] ?? '').toString();
    final location = (data['locationName'] ?? '-').toString();
    final requestType = _requestTypeLabel(
      (data['type'] ?? 'work_request').toString(),
      strings,
    );
    final createdAt = data['timestamp'] is Timestamp
        ? (data['timestamp'] as Timestamp).toDate().toString()
        : '-';
    final color = _statusColor(normalizedStatus);
    final hiddenKeys = <String>{
      'fromId',
      'status',
      'timestamp',
      'jobDescription',
      'requestedFrom',
      'requestedTo',
      'date',
      'locationName',
      'type',
      'images',
      'image',
      'imageUrl',
      'imageURL',
      'latitude',
      'longitude',
      'lat',
      'lng',
      'long',
    };
    final extraEntries =
        data.entries
            .where(
              (entry) => !hiddenKeys.contains(entry.key) && entry.value != null,
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_statusIcon(normalizedStatus), color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings['details']!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(strings['close']!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _detailRow(strings['request_type']!, requestType),
                    _detailRow(strings['date']!, date),
                    if (from != null && to != null)
                      _detailRow(strings['hours']!, '$from - $to'),
                    _detailRow(strings['location']!, location),
                    _detailRow(
                      strings['status']!,
                      _statusLabel(normalizedStatus, strings),
                    ),
                    _detailRow(strings['created_at']!, createdAt),
                    const SizedBox(height: 12),
                    Text(
                      strings['description']!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body.isEmpty ? '-' : body,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        height: 1.35,
                      ),
                    ),
                    if (extraEntries.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        strings['additional_details']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...extraEntries.map(
                        (entry) => _detailRow(
                          entry.key,
                          entry.value is Timestamp
                              ? (entry.value as Timestamp).toDate().toString()
                              : entry.value.toString(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
          {
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          },
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

            return Column(
              children: [
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
                      ? Center(child: Text(strings['no_items_for_filter']!))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
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

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                              color: Colors.white,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _showRequestDetails(
                                  context,
                                  data,
                                  status,
                                  strings,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${strings['request']!}: ${_requestTypeLabel(type, strings)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(
                                                0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _statusIcon(status),
                                                  color: statusColor,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _statusLabel(status, strings),
                                                  style: TextStyle(
                                                    color: statusColor,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('${strings['date']!}: $date'),
                                      if (from != null && to != null)
                                        Text(
                                          '${strings['hours']!}: $from - $to',
                                        ),
                                      if (body.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          body,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF4B5563),
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
                                      if (status == 'waiting_for_approval') ...[
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
}
