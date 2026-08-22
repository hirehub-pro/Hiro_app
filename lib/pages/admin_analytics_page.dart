import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  int _totalUsers = 0;
  int _totalWorkers = 0;
  int _totalCustomers = 0;
  int _totalReports = 0;
  int _pendingVerifications = 0;
  int _totalReviews = 0;
  int _totalProjects = 0;
  int _totalChatRooms = 0;
  int _activeBroadcasts = 0;
  int _invoiceCount = 0;
  int _receiptCount = 0;
  int _invoiceReceiptCount = 0;
  int _creditNoteCount = 0;
  String _businessName = '';
  String _businessNumber = '';
  String _appVersion = '';
  bool _maintenanceMode = false;
  List<Map<String, dynamic>> _topProfessions = [];
  List<Map<String, dynamic>> _recentBroadcasts = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Map<String, String> _strings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    if (locale == 'he') {
      return {
        'title': 'אנליטיקת אדמין',
        'subtitle': 'תמונה מלאה של הפעילות באפליקציה',
        'overview': 'סקירה כללית',
        'operations': 'תפעול ומערכת',
        'top_professions': 'מקצועות מובילים בחיפושים',
        'business': 'פרטי מערכת',
        'refresh': 'רענן',
        'total_users': 'סה״כ משתמשים',
        'workers': 'בעלי מקצוע',
        'customers': 'לקוחות',
        'reports': 'דיווחים',
        'pending_verifications': 'אימותים ממתינים',
        'reviews': 'ביקורות',
        'projects': 'פרויקטים',
        'chat_rooms': 'חדרי צ׳אט',
        'active_broadcasts': 'שידורים פעילים',
        'invoice_count': 'חשבוניות',
        'receipt_count': 'קבלות',
        'invoice_receipt_count': 'חשבונית/קבלה',
        'credit_note_count': 'זיכויים',
        'worker_share': 'חלק בעלי מקצוע',
        'customer_share': 'חלק לקוחות',
        'reviews_per_worker': 'ביקורות לעובד',
        'projects_per_worker': 'פרויקטים לעובד',
        'searches': 'חיפושים',
        'maintenance_on': 'תחזוקה פעילה',
        'maintenance_off': 'המערכת פתוחה',
        'business_name': 'שם עסק',
        'business_number': 'מספר עסק',
        'app_version': 'גרסת מינימום',
        'no_professions': 'אין נתוני חיפושים עדיין',
        'health': 'בריאות פלטפורמה',
        'recent_broadcasts': 'שידורים אחרונים',
        'no_broadcasts': 'אין שידורים אחרונים',
        'active_now': 'פעיל עכשיו',
        'scheduled': 'מתוזמן',
        'expired': 'פג תוקף',
      };
    }
    return {
      'title': 'Admin Analytics',
      'subtitle': 'Whole-app activity at a glance',
      'overview': 'Overview',
      'operations': 'Operations',
      'top_professions': 'Top Searched Professions',
      'business': 'System Details',
      'refresh': 'Refresh',
      'total_users': 'Total Users',
      'workers': 'Workers',
      'customers': 'Customers',
      'reports': 'Reports',
      'pending_verifications': 'Pending Verifications',
      'reviews': 'Reviews',
      'projects': 'Projects',
      'chat_rooms': 'Chat Rooms',
      'active_broadcasts': 'Active Broadcasts',
      'invoice_count': 'Invoices',
      'receipt_count': 'Receipts',
      'invoice_receipt_count': 'Invoice / Receipt',
      'credit_note_count': 'Credit Notes',
      'worker_share': 'Worker Share',
      'customer_share': 'Customer Share',
      'reviews_per_worker': 'Reviews per Worker',
      'projects_per_worker': 'Projects per Worker',
      'searches': 'Searches',
      'maintenance_on': 'Maintenance mode on',
      'maintenance_off': 'System open',
      'business_name': 'Business Name',
      'business_number': 'Business Number',
      'app_version': 'Min App Version',
      'no_professions': 'No search analytics yet',
      'health': 'Platform Health',
      'recent_broadcasts': 'Recent Broadcasts',
      'no_broadcasts': 'No recent broadcasts',
      'active_now': 'Active Now',
      'scheduled': 'Scheduled',
      'expired': 'Expired',
    };
  }

  bool _isAnnouncementActive(Map<String, dynamic> data) {
    final now = DateTime.now();
    final startsAt = data['startsAt'] as Timestamp?;
    final expiresAt = data['expiresAt'] as Timestamp?;
    if (startsAt != null && now.isBefore(startsAt.toDate())) {
      return false;
    }
    if (expiresAt != null) {
      return now.isBefore(expiresAt.toDate());
    }

    final timestamp = data['timestamp'] as Timestamp?;
    if (timestamp == null) return false;
    return now.difference(timestamp.toDate()).inHours < 48;
  }

  Future<void> _loadAnalytics() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _firestore.collection('users').get(),
        _firestore.collection('users').where('role', isEqualTo: 'worker').get(),
        _firestore
            .collection('users')
            .where('role', isEqualTo: 'customer')
            .get(),
        _firestore.collection('reports').get(),
        _firestore
            .collection('verifications')
            .where('status', isEqualTo: 'pending')
            .get(),
        _firestore.collectionGroup('reviews').get(),
        _firestore.collectionGroup('projects').get(),
        _firestore.collection('chat_rooms').get(),
        _firestore.collection('system_announcements').get(),
        _firestore.collection('metadata').doc('system').get(),
        _firestore.collection('metadata').doc('invoice_counts').get(),
        _firestore
            .collection('metadata')
            .doc('analytics')
            .collection('professions')
            .orderBy('searchCount', descending: true)
            .limit(5)
            .get(),
      ]);

      final usersSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final workersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final customersSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final reportsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
      final verificationsSnap =
          results[4] as QuerySnapshot<Map<String, dynamic>>;
      final reviewsSnap = results[5] as QuerySnapshot<Map<String, dynamic>>;
      final projectsSnap = results[6] as QuerySnapshot<Map<String, dynamic>>;
      final chatRoomsSnap = results[7] as QuerySnapshot<Map<String, dynamic>>;
      final announcementsSnap =
          results[8] as QuerySnapshot<Map<String, dynamic>>;
      final systemDoc = results[9] as DocumentSnapshot<Map<String, dynamic>>;
      final invoiceCountsDoc =
          results[10] as DocumentSnapshot<Map<String, dynamic>>;
      final professionSnap = results[11] as QuerySnapshot<Map<String, dynamic>>;

      final activeBroadcasts = announcementsSnap.docs.where((doc) {
        final data = doc.data();
        return data['showBanner'] == true || data['isPopup'] == true
            ? _isAnnouncementActive(data)
            : false;
      }).length;
      final recentBroadcasts =
          announcementsSnap.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList()
            ..sort((a, b) {
              final aTs = a['timestamp'] as Timestamp?;
              final bTs = b['timestamp'] as Timestamp?;
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              return bTs.compareTo(aTs);
            });

      final systemData = systemDoc.data() ?? <String, dynamic>{};
      final invoiceCountsData = invoiceCountsDoc.data() ?? <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _totalUsers = usersSnap.docs.length;
        _totalWorkers = workersSnap.docs.length;
        _totalCustomers = customersSnap.docs.length;
        _totalReports = reportsSnap.docs.length;
        _pendingVerifications = verificationsSnap.docs.length;
        _totalReviews = reviewsSnap.docs.length;
        _totalProjects = projectsSnap.docs.length;
        _totalChatRooms = chatRoomsSnap.docs.length;
        _activeBroadcasts = activeBroadcasts;
        _invoiceCount = (invoiceCountsData['invoice'] as num?)?.toInt() ?? 0;
        _receiptCount = (invoiceCountsData['receipt'] as num?)?.toInt() ?? 0;
        _invoiceReceiptCount =
            (invoiceCountsData['invoice_receipt'] as num?)?.toInt() ?? 0;
        _creditNoteCount =
            (invoiceCountsData['credit_note'] as num?)?.toInt() ?? 0;
        _businessName = (systemData['businessName'] ?? '').toString();
        _businessNumber = (systemData['businessNumber'] ?? '').toString();
        _appVersion = (systemData['minRequiredVersion'] ?? '').toString();
        _maintenanceMode = systemData['maintenanceMode'] == true;
        _topProfessions = professionSnap.docs
            .map(
              (doc) => {
                'name': doc.id,
                'searchCount':
                    (doc.data()['searchCount'] as num?)?.toInt() ?? 0,
              },
            )
            .toList();
        _recentBroadcasts = recentBroadcasts.take(4).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load analytics: $e')));
    }
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.25),
          ),
        ],
      ),
    );
  }

  Widget _compactStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.25),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _systemInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _strings(context);
    final workerShare = _totalUsers == 0
        ? 0
        : ((_totalWorkers / _totalUsers) * 100).round();
    final customerShare = _totalUsers == 0
        ? 0
        : ((_totalCustomers / _totalUsers) * 100).round();
    final reviewsPerWorker = _totalWorkers == 0
        ? 0
        : (_totalReviews / _totalWorkers);
    final projectsPerWorker = _totalWorkers == 0
        ? 0
        : (_totalProjects / _totalWorkers);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(s['title']!),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: s['refresh'],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['title']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s['subtitle']!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _maintenanceMode
                                ? s['maintenance_on']!
                                : s['maintenance_off']!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['overview']!),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      _metricCard(
                        icon: Icons.people_alt_rounded,
                        label: s['total_users']!,
                        value: _totalUsers.toString(),
                        color: const Color(0xFF1D4ED8),
                      ),
                      _metricCard(
                        icon: Icons.engineering_rounded,
                        label: s['workers']!,
                        value: _totalWorkers.toString(),
                        color: const Color(0xFF0F766E),
                      ),
                      _metricCard(
                        icon: Icons.person_outline_rounded,
                        label: s['customers']!,
                        value: _totalCustomers.toString(),
                        color: const Color(0xFF9333EA),
                      ),
                      _metricCard(
                        icon: Icons.rate_review_outlined,
                        label: s['reviews']!,
                        value: _totalReviews.toString(),
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['operations']!),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      _metricCard(
                        icon: Icons.report_problem_outlined,
                        label: s['reports']!,
                        value: _totalReports.toString(),
                        color: const Color(0xFFDC2626),
                      ),
                      _metricCard(
                        icon: Icons.verified_outlined,
                        label: s['pending_verifications']!,
                        value: _pendingVerifications.toString(),
                        color: const Color(0xFFEA580C),
                      ),
                      _metricCard(
                        icon: Icons.work_history_outlined,
                        label: s['projects']!,
                        value: _totalProjects.toString(),
                        color: const Color(0xFF2563EB),
                      ),
                      _metricCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: s['chat_rooms']!,
                        value: _totalChatRooms.toString(),
                        color: const Color(0xFF0891B2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _metricCard(
                    icon: Icons.campaign_outlined,
                    label: s['active_broadcasts']!,
                    value: _activeBroadcasts.toString(),
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('Documents'),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      _metricCard(
                        icon: Icons.receipt_long_outlined,
                        label: s['invoice_count']!,
                        value: _invoiceCount.toString(),
                        color: const Color(0xFF2563EB),
                      ),
                      _metricCard(
                        icon: Icons.payments_outlined,
                        label: s['receipt_count']!,
                        value: _receiptCount.toString(),
                        color: const Color(0xFF0F766E),
                      ),
                      _metricCard(
                        icon: Icons.description_outlined,
                        label: s['invoice_receipt_count']!,
                        value: _invoiceReceiptCount.toString(),
                        color: const Color(0xFF7C3AED),
                      ),
                      _metricCard(
                        icon: Icons.assignment_return_outlined,
                        label: s['credit_note_count']!,
                        value: _creditNoteCount.toString(),
                        color: const Color(0xFFEA580C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['health']!),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    children: [
                      _compactStat(
                        label: s['worker_share']!,
                        value: '$workerShare%',
                        color: const Color(0xFF0F766E),
                      ),
                      _compactStat(
                        label: s['customer_share']!,
                        value: '$customerShare%',
                        color: const Color(0xFF9333EA),
                      ),
                      _compactStat(
                        label: s['reviews_per_worker']!,
                        value: reviewsPerWorker.toStringAsFixed(1),
                        color: const Color(0xFFF59E0B),
                      ),
                      _compactStat(
                        label: s['projects_per_worker']!,
                        value: projectsPerWorker.toStringAsFixed(1),
                        color: const Color(0xFF2563EB),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['top_professions']!),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _topProfessions.isEmpty
                        ? Text(
                            s['no_professions']!,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          )
                        : Column(
                            children: _topProfessions.map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (item['name'] ?? '').toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${item['searchCount']} ${s['searches']}',
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['recent_broadcasts']!),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _recentBroadcasts.isEmpty
                        ? Text(
                            s['no_broadcasts']!,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          )
                        : Column(
                            children: _recentBroadcasts.map((item) {
                              final startsAt = item['startsAt'] as Timestamp?;
                              final isActive = _isAnnouncementActive(item);
                              final isScheduled =
                                  startsAt != null &&
                                  DateTime.now().isBefore(startsAt.toDate());
                              final status = isActive
                                  ? s['active_now']!
                                  : isScheduled
                                  ? s['scheduled']!
                                  : s['expired']!;
                              final statusColor = isActive
                                  ? const Color(0xFF0F766E)
                                  : isScheduled
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF64748B);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (item['title'] ?? '-').toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (item['message'] ?? '').toString(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _statusChip(status, statusColor),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle(s['business']!),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _systemInfoRow(s['business_name']!, _businessName),
                        _systemInfoRow(s['business_number']!, _businessNumber),
                        _systemInfoRow(s['app_version']!, _appVersion),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
