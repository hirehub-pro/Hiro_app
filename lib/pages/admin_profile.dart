import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/admin_panel.dart';
import 'package:untitled1/pages/settings.dart';
import 'package:untitled1/pages/admin_analytics_page.dart';

class AdminProfile extends StatefulWidget {
  const AdminProfile({super.key});

  @override
  State<AdminProfile> createState() => _AdminProfileState();
}

class _AdminProfileState extends State<AdminProfile>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _userName = "";
  String _email = "";
  String _profileImageUrl = "";
  bool _isLoading = true;
  bool _isMaintenanceMode = false;
  String _appVersion = "1.0.0";
  String _businessName = "";
  String _businessNumber = "";
  String _softwareRegistrationNumber = "";
  String _softwareMakerVatNumber = "";
  double _vatPercent = 17.0;
  double _allocationNumberMinAmountBeforeVat = 5000.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAdminData();
    _checkSystemSettings();
  }

  Future<void> _checkSystemSettings() async {
    try {
      final doc = await _firestore.collection('metadata').doc('system').get();
      if (doc.exists && mounted) {
        setState(() {
          _isMaintenanceMode = doc.data()?['maintenanceMode'] ?? false;
          _appVersion = doc.data()?['minRequiredVersion'] ?? "1.0.0";
          _businessName = (doc.data()?['businessName'] ?? '').toString();
          _businessNumber = (doc.data()?['businessNumber'] ?? '').toString();
          _softwareRegistrationNumber =
              (doc.data()?['softwareRegistrationNumber'] ?? '').toString();
          _softwareMakerVatNumber =
              (doc.data()?['softwareMakerVatNumber'] ?? '').toString();
          _vatPercent = _parseVatPercent(doc.data()?['vatPercent']);
          _allocationNumberMinAmountBeforeVat = _parsePositiveAmount(
            doc.data()?['allocationNumberMinAmountBeforeVat'],
            fallback: 5000.0,
          );
        });
      } else if (mounted) {
        setState(() {
          _businessName = '';
          _businessNumber = '';
          _softwareRegistrationNumber = '';
          _softwareMakerVatNumber = '';
          _vatPercent = 17.0;
          _allocationNumberMinAmountBeforeVat = 5000.0;
        });
      }
    } catch (e) {
      debugPrint("Settings check error: $e");
    }
  }

  double _parseVatPercent(dynamic value) {
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (parsed == null || parsed <= 0 || parsed > 100) {
      return 17.0;
    }
    return parsed;
  }

  double _parsePositiveAmount(dynamic value, {required double fallback}) {
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => _parseAmountText(value),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  double? _parseAmountText(String value) {
    var normalized = value.trim().replaceAll('₪', '').replaceAll(' ', '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll(',', '');
    } else if (RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(normalized)) {
      normalized = normalized.replaceAll(',', '');
    } else {
      normalized = normalized.replaceAll(',', '.');
    }
    return double.tryParse(normalized);
  }

  String _formatAmount(double value) {
    final rounded = value.toStringAsFixed(2);
    final trimmed = rounded.contains('.')
        ? rounded.replaceFirst(RegExp(r'\.?0+$'), '')
        : rounded;
    return trimmed.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  String _formatVatPercent(double value) {
    final rounded = value.toStringAsFixed(2);
    return rounded.contains('.')
        ? rounded.replaceFirst(RegExp(r'\.?0+$'), '')
        : rounded;
  }

  Future<void> _fetchAdminData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _userName = data['name'] ?? "Admin";
          _email = data['email'] ?? user.email ?? "";
          _profileImageUrl = data['profileImageUrl'] ?? "";
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Admin fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
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
          'analytics_title': 'לוח בקרה עסקי',
          'total_earnings': 'הכנסות משוערות',
          'total_jobs': 'עבודות',
          'price': 'מחיר',
          'service': 'שירות',
          'timing': 'עמידה בזמנים',
          'no_reviews': 'אין נתונים',
        };
      default:
        return {
          'analytics_title': 'Business Dashboard',
          'total_earnings': 'Estimated Earnings',
          'total_jobs': 'Jobs',
          'price': 'Price',
          'service': 'Service',
          'timing': 'Timing',
          'no_reviews': 'No data',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              expandedHeight: 380,
              pinned: true,
              backgroundColor: Colors.red[900],
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ).then((_) => _fetchAdminData()),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_profileImageUrl.isNotEmpty)
                      Image.network(_profileImageUrl, fit: BoxFit.cover)
                    else
                      Container(
                        color: Colors.red[900],
                        child: Icon(
                          Icons.admin_panel_settings,
                          size: 100,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.2),
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 80,
                      left: 24,
                      right: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.verified_user,
                                color: Colors.blueAccent,
                                size: 24,
                              ),
                            ],
                          ),
                          Text(
                            _email,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildQuickStats(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.red[900],
                  indicatorWeight: 3,
                  labelColor: Colors.red[900],
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  tabs: [
                    Tab(text: locale == 'he' ? "סקירה" : "Overview"),
                    Tab(text: locale == 'he' ? "ניהול" : "Management"),
                    Tab(text: locale == 'he' ? "פעילות" : "Activity"),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              const AdminPanel(showAppBar: false),
              _buildActivityTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('metadata').doc('system').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        var usersCount = _metricFromMetadata(
          data,
          directKeys: const ['usersCount', 'totalUsers'],
          nestedKeys: const ['users'],
        );
        if (usersCount == 0) {
          final totalWorkers = (data['totalWorkers'] as num?)?.toInt() ?? 0;
          final totalCustomers = (data['totalCustomers'] as num?)?.toInt() ?? 0;
          if (totalWorkers > 0 || totalCustomers > 0) {
            usersCount = totalWorkers + totalCustomers;
          }
        }
        final workersCount = _metricFromMetadata(
          data,
          directKeys: const ['workersCount', 'workerCount', 'totalWorkers'],
          nestedKeys: const ['workers'],
        );
        final reportsCount = _metricFromMetadata(
          data,
          directKeys: const ['reportsCount', 'reportCount', 'totalReports'],
          nestedKeys: const ['reports'],
        );

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeaderStat("Users", usersCount),
              _buildHeaderStat("Workers", workersCount),
              _buildHeaderStat("Reports", reportsCount),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderStat(String label, int count) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(locale == 'he' ? "מצב המערכת" : "System Status"),
          const SizedBox(height: 12),
          _buildStatusCard(),
          const SizedBox(height: 24),
          _buildSectionTitle(
            locale == 'he' ? "פעולות מהירות" : "Quick Actions",
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildQuickActionCard(
                Icons.add_alert_rounded,
                "Broadcast",
                Colors.blue,
                _showBroadcastDialog,
              ),
              _buildQuickActionCard(
                Icons.security_rounded,
                "Security",
                Colors.orange,
                _showSecurityOptions,
              ),
              _buildQuickActionCard(
                Icons.analytics_rounded,
                "Analytics",
                Colors.green,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminAnalyticsPage(),
                    ),
                  );
                },
              ),
              _buildQuickActionCard(
                Icons.business_rounded,
                "Business Info",
                Colors.teal,
                _showBusinessInfoDialog,
              ),
              _buildQuickActionCard(
                Icons.settings_suggest_rounded,
                "System Config",
                Colors.purple,
                _showSystemConfig,
              ),
              _buildQuickActionCard(
                Icons.receipt_long_rounded,
                "A000 Info",
                Colors.indigo,
                _showA000InfoDialog,
              ),
              _buildQuickActionCard(
                Icons.percent_rounded,
                "VAT ${_formatVatPercent(_vatPercent)}%",
                Colors.deepOrange,
                _showVatConfigDialog,
              ),
              _buildQuickActionCard(
                Icons.receipt_rounded,
                "Allocation ₪${_formatAmount(_allocationNumberMinAmountBeforeVat)}",
                Colors.brown,
                _showAllocationNumberConfigDialog,
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildRecentAnnouncements(),
          const SizedBox(height: 32),
          _buildDatabaseStats(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRecentAnnouncements() {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          locale == 'he' ? "הכרזות אחרונות" : "Recent Announcements",
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('system_announcements')
              .orderBy('timestamp', descending: true)
              .limit(3)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Text(
                locale == 'he'
                    ? "אין הכרזות לשלוח"
                    : "No announcements sent yet",
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              );
            }
            return Column(
              children: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      data['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      data['message'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.red,
                      ),
                      onPressed: () =>
                          _deleteAnnouncement(doc.id, data['title']),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDatabaseStats() {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('metadata').doc('system').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final workersCount = _metricFromMetadata(
          data,
          directKeys: const ['workersCount', 'workerCount'],
          nestedKeys: const ['workers'],
        );
        final projectsCount = _metricFromMetadata(
          data,
          directKeys: const ['projectsCount', 'projectCount'],
          nestedKeys: const ['projects'],
        );
        final reviewsCount = _metricFromMetadata(
          data,
          directKeys: const ['reviewsCount', 'reviewCount'],
          nestedKeys: const ['reviews'],
        );

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(
                locale == 'he' ? "מדדי ביצועים" : "Database Performance",
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      "Workers",
                      workersCount,
                      Icons.engineering,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      "Projects",
                      projectsCount,
                      Icons.work_history,
                    ),
                  ),
                  Expanded(
                    child: _buildMetricTile(
                      "Reviews",
                      reviewsCount,
                      Icons.star,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  int _metricFromMetadata(
    Map<String, dynamic> data, {
    required List<String> directKeys,
    required List<String> nestedKeys,
  }) {
    for (final key in directKeys) {
      final value = data[key];
      if (value is num) return value.toInt();
    }

    final stats = data['databaseStats'];
    if (stats is Map<String, dynamic>) {
      for (final key in nestedKeys) {
        final value = stats[key];
        if (value is num) return value.toInt();
      }
    }

    return 0;
  }

  Widget _buildMetricTile(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.red[900], size: 20),
        const SizedBox(height: 8),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  void _showBroadcastDialog() {
    final titleController = TextEditingController();
    final msgController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('System Broadcast'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: msgController,
              decoration: const InputDecoration(labelText: 'Message'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty &&
                  msgController.text.isNotEmpty) {
                final messenger = ScaffoldMessenger.of(context);
                await _firestore.collection('system_announcements').add({
                  'title': titleController.text,
                  'message': msgController.text,
                  'timestamp': FieldValue.serverTimestamp(),
                  'createdBy': _userName,
                });
                await _logActivity("Sent Broadcast: ${titleController.text}");
                if (context.mounted) {
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text("Broadcast sent successfully"),
                    ),
                  );
                }
              }
            },
            child: const Text('Send to All'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAnnouncement(String id, String? title) async {
    await _firestore.collection('system_announcements').doc(id).delete();
    await _logActivity("Deleted Announcement: $title");
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Announcement deleted")));
    }
  }

  void _showSecurityOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Security & Access Controls",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text("Maintenance Mode"),
                subtitle: const Text("Restrict access to all non-admin users"),
                value: _isMaintenanceMode,
                onChanged: (val) async {
                  await _firestore.collection('metadata').doc('system').set({
                    'maintenanceMode': val,
                  }, SetOptions(merge: true));
                  await _logActivity(
                    "${val ? 'Enabled' : 'Disabled'} Maintenance Mode",
                  );
                  setState(() => _isMaintenanceMode = val);
                  setModalState(() {});
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.lock_reset, color: Colors.red),
                title: const Text("Force Logout All Sessions"),
                onTap: () => _confirmForceLogout(context),
              ),
              ListTile(
                leading: const Icon(
                  Icons.cleaning_services,
                  color: Colors.blue,
                ),
                title: const Text("Clear System Cache"),
                subtitle: const Text(
                  "Reset global app counters and temporary data",
                ),
                onTap: () async {
                  await _logActivity("Initiated System Cache Cleanup");
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("System cache cleanup initiated"),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmForceLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Force Logout All Users?"),
        content: const Text(
          "This will immediately sign out all users from their current sessions. They will need to log in again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Force Logout"),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context); // Close the security sheet
      await _firestore.collection('metadata').doc('system').set({
        'forceLogoutAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _logActivity("Forced Global Logout");
      messenger.showSnackBar(
        const SnackBar(content: Text("Global logout triggered")),
      );
    }
  }

  void _showSystemConfig() {
    final versionController = TextEditingController(text: _appVersion);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Global Configuration",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: versionController,
                decoration: const InputDecoration(
                  labelText: 'Minimum Required App Version',
                  hintText: 'e.g., 1.2.0',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Note: Users with versions lower than this will be forced to update.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await _firestore.collection('metadata').doc('system').set({
                      'minRequiredVersion': versionController.text,
                    }, SetOptions(merge: true));
                    await _logActivity(
                      "Set Min App Version to ${versionController.text}",
                    );
                    setState(() => _appVersion = versionController.text);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Save Configuration"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBusinessInfoDialog() {
    final businessNameController = TextEditingController(text: _businessName);
    final businessNumberController = TextEditingController(
      text: _businessNumber,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Business Export Info",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: businessNameController,
                decoration: const InputDecoration(
                  labelText: 'Business Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: businessNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Business Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await _firestore.collection('metadata').doc('system').set({
                      'businessName': businessNameController.text.trim(),
                      'businessNumber': businessNumberController.text.trim(),
                    }, SetOptions(merge: true));
                    await _logActivity(
                      "Updated Business Export Info: ${businessNameController.text.trim()}",
                    );
                    setState(() {
                      _businessName = businessNameController.text.trim();
                      _businessNumber = businessNumberController.text.trim();
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Save Business Info"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showA000InfoDialog() {
    final softwareRegistrationController = TextEditingController(
      text: _softwareRegistrationNumber,
    );
    final softwareMakerVatController = TextEditingController(
      text: _softwareMakerVatNumber,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "A000 Export Info",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: softwareRegistrationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Software Registration Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: softwareMakerVatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Software Maker VAT Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await _firestore.collection('metadata').doc('system').set({
                      'softwareRegistrationNumber':
                          softwareRegistrationController.text.trim(),
                      'softwareMakerVatNumber': softwareMakerVatController.text
                          .trim(),
                    }, SetOptions(merge: true));
                    await _logActivity('Updated A000 export identifiers');
                    setState(() {
                      _softwareRegistrationNumber =
                          softwareRegistrationController.text.trim();
                      _softwareMakerVatNumber = softwareMakerVatController.text
                          .trim();
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Save A000 Info"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVatConfigDialog() {
    final vatController = TextEditingController(
      text: _formatVatPercent(_vatPercent),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "VAT Configuration",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: vatController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'VAT Percent',
                  hintText: 'e.g., 17',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "This value will be used for invoice and tax document VAT calculations.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final raw = vatController.text.trim().replaceAll(',', '.');
                    final parsed = double.tryParse(raw);
                    if (parsed == null || parsed <= 0 || parsed > 100) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Enter a valid VAT percent between 0 and 100",
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    await _firestore.collection('metadata').doc('system').set({
                      'vatPercent': parsed,
                    }, SetOptions(merge: true));
                    await _logActivity(
                      "Updated VAT Percent to ${_formatVatPercent(parsed)}%",
                    );
                    setState(() => _vatPercent = parsed);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "VAT updated to ${_formatVatPercent(parsed)}%",
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text("Save VAT"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllocationNumberConfigDialog() {
    final thresholdController = TextEditingController(
      text: _formatAmount(
        _allocationNumberMinAmountBeforeVat,
      ).replaceAll(',', ''),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Allocation Number Threshold",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: thresholdController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Minimum amount before VAT',
                  hintText: 'e.g., 5000',
                  prefixText: '₪ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Invoices above this amount before VAT should request מספר הקצאה from the Israel Tax Authority.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[900],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final parsed = _parseAmountText(thresholdController.text);
                    if (parsed == null || parsed <= 0) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Enter a valid amount greater than 0",
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    await _firestore.collection('metadata').doc('system').set({
                      'allocationNumberMinAmountBeforeVat': parsed,
                    }, SetOptions(merge: true));
                    await _logActivity(
                      "Updated Allocation Number threshold to ₪${_formatAmount(parsed)} before VAT",
                    );
                    setState(
                      () => _allocationNumberMinAmountBeforeVat = parsed,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Allocation threshold updated to ₪${_formatAmount(parsed)}",
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text("Save Threshold"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logActivity(String action) async {
    await _firestore
        .collection('users')
        .doc('${FirebaseAuth.instance.currentUser?.uid}')
        .collection('admin_activity')
        .add({
          'action': action,
          'timestamp': FieldValue.serverTimestamp(),
          'adminId': FirebaseAuth.instance.currentUser?.uid,
          'adminName': _userName,
        });
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isMaintenanceMode ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isMaintenanceMode ? Colors.orange[100]! : Colors.green[100]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isMaintenanceMode
                ? Icons.warning_amber_rounded
                : Icons.check_circle,
            color: _isMaintenanceMode ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMaintenanceMode
                      ? "System in Maintenance"
                      : "All Systems Operational",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isMaintenanceMode
                        ? Colors.orange[900]
                        : Colors.green[900],
                  ),
                ),
                Text(
                  _isMaintenanceMode
                      ? "Normal users are currently blocked from accessing the app"
                      : "Database, Auth and Storage are running smoothly",
                  style: TextStyle(
                    fontSize: 12,
                    color: _isMaintenanceMode
                        ? Colors.orange[700]
                        : Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildActivityTab() {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle(
                locale == 'he' ? "לוג פעילות" : "Activity Log",
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                label: Text(
                  locale == 'he' ? "נקה הכל" : "Clear All",
                  style: const TextStyle(color: Colors.red),
                ),
                onPressed: _confirmClearActivity,
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('users')
                .doc('${FirebaseAuth.instance.currentUser?.uid}')
                .collection('admin_activity')
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 64,
                        color: Colors.grey[200],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        locale == 'he'
                            ? "אין פעילות אדמין לאחרונה"
                            : "No recent admin activity",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                );
              }

              final activities = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final data = activities[index].data() as Map<String, dynamic>;
                  final timestamp = data['timestamp'] as Timestamp?;
                  final action = data['action']?.toString().toLowerCase() ?? '';

                  IconData icon = Icons.bolt;
                  Color iconColor = Colors.red;

                  if (action.contains('delete')) {
                    icon = Icons.delete_forever;
                    iconColor = Colors.orange;
                  } else if (action.contains('approve')) {
                    icon = Icons.verified;
                    iconColor = Colors.green;
                  } else if (action.contains('broadcast')) {
                    icon = Icons.campaign;
                    iconColor = Colors.blue;
                  } else if (action.contains('maintenance')) {
                    icon = Icons.settings_applications;
                    iconColor = Colors.orange;
                  } else if (action.contains('config') ||
                      action.contains('version')) {
                    icon = Icons.settings_suggest;
                    iconColor = Colors.purple;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[100]!),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      title: Text(
                        data['action'] ?? 'Unknown Action',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        "${data['adminName'] ?? 'System'} • ${timestamp != null ? _formatDate(timestamp.toDate()) : 'No time'}",
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearActivity() async {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locale == 'he' ? "נקה לוג פעילות?" : "Clear Activity Log?"),
        content: Text(
          locale == 'he'
              ? "האם אתה בטוח שברצונך למחוק את כל היסטוריית הפעילות? פעולה זו אינה ניתנת לביטול."
              : "Are you sure you want to delete all activity history? This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(locale == 'he' ? "ביטול" : "Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(locale == 'he' ? "נקה הכל" : "Clear All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('users')
          .doc('${FirebaseAuth.instance.currentUser?.uid}')
          .collection('admin_activity')
          .get();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await _logActivity("Cleared Activity Log");
    }
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
