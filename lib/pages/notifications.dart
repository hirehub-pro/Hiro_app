import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:untitled1/pages/my_requests_page.dart';
import 'package:untitled1/pages/request_details.dart';
import 'package:untitled1/services/language_provider.dart';

class NotificationsPage extends StatefulWidget {
  final String initialFilter;

  const NotificationsPage({super.key, this.initialFilter = 'all'});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _selectedFilter = 'all';
  bool _didMarkResponseNotificationsRead = false;

  @override
  void initState() {
    super.initState();
    switch (widget.initialFilter) {
      case 'requests':
      case 'updates':
      case 'broadcasts':
      case 'all':
        _selectedFilter = widget.initialFilter;
      default:
        _selectedFilter = 'all';
    }
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'התראות',
          'empty': 'אין התראות חדשות',
          'clear': 'נקה הכל',
          'accept': 'אישור',
          'decline': 'דחייה',
          'accepted': 'התקבל',
          'declined': 'נדחה',
          'call': 'התקשר',
          'details': 'פרטים',
          'broadcast': 'הודעת מערכת',
          'all': 'הכל',
          'requests': 'בקשות',
          'updates': 'עדכונים',
          'broadcasts': 'מערכת',
          'signed_out': 'יש להתחבר כדי לצפות בהתראות.',
          'personal_count': 'אישיות',
          'system_count': 'מערכת',
          'pending_count': 'ממתינות',
          'swipe_delete': 'החלק למחיקה',
          'deleted': 'ההתראה נמחקה',
          'open_request': 'פתח בקשה',
          'view_details': 'צפה בפרטים',
          'hub_title': 'מרכז ההתראות שלך',
          'notification_fallback': 'התראה',
        };
      case 'ar':
        return {
          'title': 'الإشعارات',
          'empty': 'لا توجد إشعارات جديدة',
          'clear': 'مسح الكل',
          'accept': 'قبول',
          'decline': 'رفض',
          'accepted': 'تم القبول',
          'declined': 'تم الرفض',
          'call': 'اتصال',
          'details': 'التفاصيل',
          'broadcast': 'إعلان نظام',
          'all': 'الكل',
          'requests': 'الطلبات',
          'updates': 'التحديثات',
          'broadcasts': 'النظام',
          'signed_out': 'يرجى تسجيل الدخول لعرض الإشعارات.',
          'personal_count': 'شخصية',
          'system_count': 'النظام',
          'pending_count': 'معلّقة',
          'swipe_delete': 'اسحب للحذف',
          'deleted': 'تم حذف الإشعار',
          'open_request': 'فتح الطلب',
          'view_details': 'عرض التفاصيل',
          'hub_title': 'مركز الإشعارات الخاص بك',
          'notification_fallback': 'إشعار',
        };
      case 'am':
        return {
          'title': 'ማሳወቂያዎች',
          'empty': 'አዲስ ማሳወቂያ የለም',
          'clear': 'ሁሉን አጽዳ',
          'accept': 'ተቀበል',
          'decline': 'እምቢ',
          'accepted': 'ተቀባ',
          'declined': 'ተከለከለ',
          'call': 'ደውል',
          'details': 'ዝርዝሮች',
          'broadcast': 'የስርዓት ማስታወቂያ',
          'all': 'ሁሉም',
          'requests': 'ጥያቄዎች',
          'updates': 'ማዘመኛዎች',
          'broadcasts': 'ስርዓት',
          'signed_out': 'ማሳወቂያዎችን ለማየት እባክዎ ይግቡ።',
          'personal_count': 'የግል',
          'system_count': 'ስርዓት',
          'pending_count': 'በመጠባበቅ',
          'swipe_delete': 'ለመሰረዝ ያንሸራትቱ',
          'deleted': 'ማሳወቂያው ተሰርዟል',
          'open_request': 'ጥያቄ ክፈት',
          'view_details': 'ዝርዝር እይ',
          'hub_title': 'የእርስዎ ማሳወቂያ ማዕከል',
          'notification_fallback': 'ማሳወቂያ',
        };
      case 'ru':
        return {
          'title': 'Уведомления',
          'empty': 'Новых уведомлений нет',
          'clear': 'Очистить все',
          'accept': 'Принять',
          'decline': 'Отклонить',
          'accepted': 'Принято',
          'declined': 'Отклонено',
          'call': 'Позвонить',
          'details': 'Детали',
          'broadcast': 'Системное объявление',
          'all': 'Все',
          'requests': 'Запросы',
          'updates': 'Обновления',
          'broadcasts': 'Система',
          'signed_out': 'Войдите, чтобы просмотреть уведомления.',
          'personal_count': 'Личные',
          'system_count': 'Система',
          'pending_count': 'В ожидании',
          'swipe_delete': 'Смахните для удаления',
          'deleted': 'Уведомление удалено',
          'open_request': 'Открыть запрос',
          'view_details': 'Посмотреть детали',
          'hub_title': 'Ваш центр уведомлений',
          'notification_fallback': 'Уведомление',
        };
      default:
        return {
          'title': 'Notifications',
          'empty': 'No new notifications',
          'clear': 'Clear All',
          'accept': 'Accept',
          'decline': 'Decline',
          'accepted': 'Accepted',
          'declined': 'Declined',
          'call': 'Call',
          'details': 'Details',
          'broadcast': 'System Broadcast',
          'all': 'All',
          'requests': 'Requests',
          'updates': 'Updates',
          'broadcasts': 'System',
          'signed_out': 'Please sign in to view notifications.',
          'personal_count': 'Personal',
          'system_count': 'System',
          'pending_count': 'Pending',
          'swipe_delete': 'Swipe to delete',
          'deleted': 'Notification deleted',
          'open_request': 'Open request',
          'view_details': 'View details',
          'hub_title': 'Your notification hub',
          'notification_fallback': 'Notification',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final user = FirebaseAuth.instance.currentUser;
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    if (user != null &&
        !user.isAnonymous &&
        !_didMarkResponseNotificationsRead) {
      _didMarkResponseNotificationsRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markResponseNotificationsRead(user.uid);
      });
    }

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            strings['title']!,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
          elevation: 0,
          actions: [
            if (user != null && !user.isAnonymous)
              TextButton(
                onPressed: () => _clearAllNotifications(user.uid),
                child: Text(
                  strings['clear']!,
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        body: (user == null || user.isAnonymous)
            ? _buildSignedOutState(strings)
            : _buildNotificationsBody(context, user.uid, strings, isRtl),
      ),
    );
  }

  Future<void> _markResponseNotificationsRead(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where(
            'type',
            whereIn: ['request_accepted', 'request_declined', 'quote_response'],
          )
          .where('isRead', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Failed to mark response notifications read: $e');
    }
  }

  Widget _buildNotificationsBody(
    BuildContext context,
    String userId,
    Map<String, String> strings,
    bool isRtl,
  ) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CombineLatestStream.combine2(
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .snapshots(),
        FirebaseFirestore.instance
            .collection('system_announcements')
            .snapshots(),
        (QuerySnapshot personal, QuerySnapshot system) {
          final all = <Map<String, dynamic>>[];

          for (final doc in personal.docs) {
            final data = Map<String, dynamic>.from(
              doc.data() as Map<String, dynamic>,
            );
            data['id'] = doc.id;
            data['isBroadcast'] = false;
            all.add(data);
          }

          for (final doc in system.docs) {
            final data = Map<String, dynamic>.from(
              doc.data() as Map<String, dynamic>,
            );
            data['id'] = doc.id;
            data['isBroadcast'] = true;
            data['type'] = 'broadcast';
            data['body'] = data['message'];
            all.add(data);
          }

          all.sort((a, b) {
            final tA = a['timestamp'] as Timestamp?;
            final tB = b['timestamp'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });
          return all;
        },
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final notifications = snapshot.data ?? const [];
        if (notifications.isEmpty) {
          return _buildEmptyState(strings);
        }

        final filtered = notifications.where(_matchesSelectedFilter).toList();
        final personalCount = notifications
            .where((n) => n['isBroadcast'] != true)
            .length;
        final systemCount = notifications
            .where((n) => n['isBroadcast'] == true)
            .length;
        final pendingCount = notifications
            .where(
              (n) =>
                  (n['type'] == 'work_request' ||
                      n['type'] == 'quote_request') &&
                  (n['status'] ?? 'pending') == 'pending',
            )
            .length;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1976D2), Color(0xFF4FC3F7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings['hub_title']!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${notifications.length} ${strings['title']!.toLowerCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildStatChip(
                              strings['personal_count']!,
                              personalCount.toString(),
                            ),
                            _buildStatChip(
                              strings['system_count']!,
                              systemCount.toString(),
                            ),
                            _buildStatChip(
                              strings['pending_count']!,
                              pendingCount.toString(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildFilterChip('all', strings['all']!),
                        _buildFilterChip('requests', strings['requests']!),
                        _buildFilterChip('updates', strings['updates']!),
                        _buildFilterChip('broadcasts', strings['broadcasts']!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        strings['empty']!,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final data = filtered[index];
                        final canDismiss = data['isBroadcast'] != true;
                        final card = _buildNotificationCard(
                          context,
                          data['id'].toString(),
                          data,
                          strings,
                        );

                        if (!canDismiss) return card;

                        return Dismissible(
                          key: ValueKey('notif_${data['id']}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) async {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(userId)
                                .collection('notifications')
                                .doc(data['id'].toString())
                                .delete();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(strings['deleted']!)),
                            );
                          },
                          child: card,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearAllNotifications(String userId) async {
    final firestore = FirebaseFirestore.instance;
    final notificationsSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .get();

    final notificationDocsToDelete =
        <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in notificationsSnapshot.docs) {
      final data = doc.data();
      if (!_canDeleteWithClearAll(data)) {
        continue;
      }
      notificationDocsToDelete.add(doc.reference);
    }

    final requestsSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('requests')
        .get();

    final declinedRequestDocsToDelete =
        <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in requestsSnapshot.docs) {
      final status = (doc.data()['status'] ?? '').toString().toLowerCase();
      if (status == 'declined' || status == 'rejected') {
        declinedRequestDocsToDelete.add(doc.reference);
      }
    }

    final docsToDelete = <DocumentReference<Map<String, dynamic>>>[
      ...notificationDocsToDelete,
      ...declinedRequestDocsToDelete,
    ];

    if (docsToDelete.isEmpty) return;

    const chunkSize = 400;
    for (var i = 0; i < docsToDelete.length; i += chunkSize) {
      final end = (i + chunkSize < docsToDelete.length)
          ? i + chunkSize
          : docsToDelete.length;
      final batch = firestore.batch();
      for (final ref in docsToDelete.sublist(i, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  bool _canDeleteWithClearAll(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final isRequest = type == 'work_request' || type == 'quote_request';

    if (!isRequest) return true;

    return status == 'declined' || status == 'rejected';
  }

  bool _matchesSelectedFilter(Map<String, dynamic> data) {
    final isBroadcast = data['isBroadcast'] == true;
    final type = (data['type'] ?? '').toString();
    switch (_selectedFilter) {
      case 'requests':
        return type == 'work_request' || type == 'quote_request';
      case 'updates':
        return !isBroadcast &&
            type != 'work_request' &&
            type != 'quote_request';
      case 'broadcasts':
        return isBroadcast;
      case 'all':
      default:
        return true;
    }
  }

  String _normalizeRequestStatus(dynamic raw) {
    final status = (raw ?? '').toString().trim().toLowerCase();
    switch (status) {
      case 'pending':
      case 'waiting_for_approval':
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

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedFilter = value),
        selectedColor: const Color(0xFF1976D2),
        backgroundColor: const Color(0xFFF1F5F9),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF475569),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedOutState(Map<String, String> strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1FB),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 42,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              strings['signed_out']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Map<String, String> strings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1FB),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 42,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              strings['empty']!,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    Map<String, String> strings,
  ) {
    final isActionableRequest =
        data['type'] == 'work_request' || data['type'] == 'quote_request';
    final isResponseUpdate =
        data['type'] == 'request_accepted' ||
        data['type'] == 'request_declined' ||
        data['type'] == 'quote_response';
    final isBroadcast = data['isBroadcast'] == true;
    final normalizedStatus = _normalizeRequestStatus(data['status']);
    final canOpenRequest = isActionableRequest;
    final title =
        (data['title'] ??
                (isBroadcast
                    ? strings['broadcast']!
                    : strings['notification_fallback']!))
            .toString();
    final body = (data['body'] ?? data['message'] ?? '').toString();
    final accent = isBroadcast
        ? const Color(0xFF1D4ED8)
        : isActionableRequest
        ? const Color(0xFF0F766E)
        : const Color(0xFF1976D2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (canOpenRequest) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RequestDetailsPage(notificationId: docId, data: data),
              ),
            );
            return;
          }

          if (isResponseUpdate) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyRequestsPage()),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isBroadcast
                  ? const Color(0xFFD6E4FF)
                  : const Color(0xFFE2E8F0),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isBroadcast
                          ? Icons.campaign_rounded
                          : (isActionableRequest
                                ? Icons.assignment_turned_in_outlined
                                : Icons.notifications_active_outlined),
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isBroadcast
                                    ? strings['broadcast']!
                                    : isActionableRequest
                                    ? strings['requests']!
                                    : strings['updates']!,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isActionableRequest &&
                                normalizedStatus != 'pending')
                              _buildStatusBadge(normalizedStatus, strings),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          body,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatTimestamp(data['timestamp']),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isActionableRequest && normalizedStatus == 'pending')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        strings['open_request']!,
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (isResponseUpdate ||
                      !isActionableRequest ||
                      canOpenRequest)
                    Text(
                      strings['view_details']!,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Map<String, String> strings) {
    final normalized = _normalizeRequestStatus(status);
    final isAccepted = normalized == 'accepted';
    final bg = isAccepted ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final fg = isAccepted ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isAccepted ? strings['accepted']! : strings['declined']!,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is! Timestamp) return '';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
