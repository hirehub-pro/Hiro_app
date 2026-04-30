import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:untitled1/formu.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/pages/fullscreen_media_viewer.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/widgets/cached_video_player.dart';

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Map<String, String>> _userSearchCache = {};
  String _statusFilter = 'all';
  String _searchQuery = '';

  static const List<String> _filters = ['all', 'open', 'resolved', 'block'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _titleCase(String value) {
    final normalized = value.replaceAll('_', ' ');
    if (normalized.isEmpty) return '-';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _normalizeSearch(String value) {
    return value.trim().toLowerCase();
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  ({Color bg, Color fg, IconData icon}) _statusMeta(String status) {
    switch (status) {
      case 'resolved':
        return (
          bg: Colors.green.withValues(alpha: 0.12),
          fg: Colors.green.shade800,
          icon: Icons.check_circle_outline,
        );
      case 'in_progress':
        return (
          bg: Colors.blue.withValues(alpha: 0.12),
          fg: Colors.blue.shade800,
          icon: Icons.sync,
        );
      default:
        return (
          bg: Colors.orange.withValues(alpha: 0.12),
          fg: Colors.orange.shade800,
          icon: Icons.pending_outlined,
        );
    }
  }

  bool _isResolved(Map<String, dynamic> data) {
    return (data['status'] ?? 'open').toString() == 'resolved';
  }

  bool _isBlockReport(Map<String, dynamic> data) {
    final reportType = (data['reportType'] ?? '').toString();
    if (reportType == 'user_block') return true;
    final blockedUid = (data['blockedUid'] ?? '').toString();
    final blockedByUid = (data['blockedByUid'] ?? '').toString();
    return blockedUid.isNotEmpty || blockedByUid.isNotEmpty;
  }

  Future<Map<String, Map<String, String>>> _loadUserSearchData(
    Iterable<String> userIds,
  ) async {
    final ids = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != 'app')
        .toSet();
    final missing = ids
        .where((id) => !_userSearchCache.containsKey(id))
        .toList();

    if (missing.isNotEmpty) {
      final docs = await Future.wait(
        missing.map((id) => _firestore.collection('users').doc(id).get()),
      );
      for (final doc in docs) {
        final data = doc.data() ?? <String, dynamic>{};
        _userSearchCache[doc.id] = {
          'id': doc.id,
          'name': (data['name'] ?? '').toString(),
          'phone': (data['phone'] ?? '').toString(),
        };
      }
    }

    return _userSearchCache;
  }

  String _userDisplayLabel(
    String userId,
    Map<String, Map<String, String>> users,
  ) {
    if (userId.isEmpty) return '-';
    final user = users[userId] ?? const <String, String>{};
    final name = (user['name'] ?? '').trim();
    return name.isNotEmpty ? name : userId;
  }

  bool _matchesSearch(
    String reportId,
    Map<String, dynamic> data,
    Map<String, Map<String, String>> users,
  ) {
    final query = _normalizeSearch(_searchQuery);
    if (query.isEmpty) return true;

    final digitsQuery = _digitsOnly(_searchQuery);
    final reporterId = (data['reporterId'] ?? '').toString();
    final reportedId = (data['reportedId'] ?? '').toString();
    final reporter = users[reporterId] ?? const <String, String>{};
    final reported = users[reportedId] ?? const <String, String>{};

    final textFields = <String>[
      reportId,
      reporterId,
      reportedId,
      reporter['name'] ?? '',
      reporter['phone'] ?? '',
      reported['name'] ?? '',
      reported['phone'] ?? '',
    ];

    final textMatch = textFields.any(
      (field) => _normalizeSearch(field).contains(query),
    );
    if (textMatch) return true;

    if (digitsQuery.isEmpty) return false;
    final digitFields = <String>[
      _digitsOnly(reportId),
      _digitsOnly(reporterId),
      _digitsOnly(reportedId),
      _digitsOnly(reporter['phone'] ?? ''),
      _digitsOnly(reported['phone'] ?? ''),
    ];
    return digitFields.any((field) => field.contains(digitsQuery));
  }

  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _markResolved(String reportId) async {
    final confirmed = await _confirmAction(
      title: 'Resolve Report',
      content: 'Mark this report as resolved?',
      confirmLabel: 'Mark Resolved',
    );
    if (!confirmed) return;

    try {
      final reportDoc = await _firestore
          .collection('reports')
          .doc(reportId)
          .get();
      final reportData = reportDoc.data() ?? <String, dynamic>{};
      final reporterId = (reportData['reporterId'] ?? '').toString();
      final subject = (reportData['subject'] ?? reportData['reason'] ?? 'דיווח')
          .toString()
          .trim();
      final wasResolved = _isResolved(reportData);

      await _firestore.collection('reports').doc(reportId).set({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
      }, SetOptions(merge: true));

      if (!wasResolved) {
        await _firestore.collection('metadata').doc('system').set({
          'reportsCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }

      await _sendResolvedMessageToReporter(
        reportId: reportId,
        reporterId: reporterId,
        subject: subject,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report marked as resolved.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update report status.')),
      );
    }
  }

  String _getChatRoomId(String user1, String user2) {
    final ids = [user1, user2]..sort();
    return ids.join('_');
  }

  Future<void> _sendResolvedMessageToReporter({
    required String reportId,
    required String reporterId,
    required String subject,
  }) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid;
    if (adminId == null || reporterId.isEmpty || reporterId == 'app') return;

    final chatRoomId = _getChatRoomId(adminId, reporterId);

    final existingResolved = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('type', isEqualTo: 'report_resolved')
        .where('reportId', isEqualTo: reportId)
        .limit(1)
        .get();

    if (existingResolved.docs.isNotEmpty) return;

    await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .add({
          'senderId': adminId,
          'receiverId': reporterId,
          'message':
              'הדיווח שלך סומן כטופל: ${subject.isEmpty ? 'דיווח' : subject}',
          'type': 'report_resolved',
          'reportId': reportId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    await _firestore.collection('chat_rooms').doc(chatRoomId).set({
      'lastMessage': '✅ הדיווח טופל',
      'lastTimestamp': FieldValue.serverTimestamp(),
      'users': [adminId, reporterId],
    }, SetOptions(merge: true));

    await _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'unreadCount.$reporterId': FieldValue.increment(1),
    });
  }

  Future<void> _deleteReport(String reportId) async {
    final confirmed = await _confirmAction(
      title: 'Delete Report',
      content: 'This action cannot be undone. Delete this report?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final reportDoc = await _firestore
          .collection('reports')
          .doc(reportId)
          .get();
      final wasResolved = _isResolved(
        reportDoc.data() ?? const <String, dynamic>{},
      );
      await _firestore.collection('reports').doc(reportId).delete();
      if (!wasResolved) {
        await _firestore.collection('metadata').doc('system').set({
          'reportsCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report deleted.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete report.')));
    }
  }

  String _displayTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    final d = ts.toDate();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$month-$day $hour:$minute';
  }

  Widget _statusBadge(String status, {String? label}) {
    final meta = _statusMeta(status);
    final displayLabel = label ?? _titleCase(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: meta.fg),
          const SizedBox(width: 4),
          Text(
            displayLabel,
            style: TextStyle(color: meta.fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(int total, int open, int resolved, int block) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Total: $total  |  Open: $open  |  Resolved: $resolved  |  Block: $block',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: _filters.map((filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_titleCase(filter)),
              selected: _statusFilter == filter,
              onSelected: (_) => setState(() => _statusFilter = filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search by report ID, reporter, reported, phone, or name',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close),
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.blue.shade400),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final msg = switch (_statusFilter) {
      'all' => 'No reports found.',
      'block' => 'No block-queue items found.',
      _ => 'No ${_titleCase(_statusFilter).toLowerCase()} reports.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 10),
            Text(msg, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    return ((data['attachments'] ?? []) as List)
        .whereType<Map>()
        .map(
          (e) => {
            'type': (e['type'] ?? '').toString(),
            'url': (e['url'] ?? '').toString(),
          },
        )
        .where((e) => e['url']!.isNotEmpty)
        .toList();
  }

  Widget _buildAttachmentsPreview(List<Map<String, String>> attachments) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = attachments[index];
          final isImage = item['type'] == 'image';
          final url = item['url'] ?? '';
          return InkWell(
            onTap: () => _openMediaViewer(attachments, index),
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 170,
                color: Colors.black12,
                child: isImage
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Icon(Icons.broken_image)),
                      )
                    : CachedVideoPlayer(url: url, play: false),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openMediaViewer(List<Map<String, String>> attachments, int index) {
    final urls = attachments
        .map((item) => (item['url'] ?? '').toString())
        .where((url) => url.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenMediaViewer(urls: urls, initialIndex: index),
      ),
    );
  }

  Future<void> _openReportDetails(
    String reportId,
    Map<String, dynamic> data,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminReportDetailsPage(reportId: reportId, data: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Reports')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('reports')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load reports right now.'),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data!.docs;
          final openCount = allDocs.where((d) {
            final data = d.data();
            return !_isResolved(data) && !_isBlockReport(data);
          }).length;
          final resolvedCount = allDocs
              .where((d) => _isResolved(d.data()))
              .length;
          final blockCount = allDocs
              .where((d) => _isBlockReport(d.data()))
              .length;

          final idsToLoad = <String>{
            for (final doc in allDocs)
              (doc.data()['reporterId'] ?? '').toString(),
            for (final doc in allDocs)
              (doc.data()['reportedId'] ?? '').toString(),
          };

          return FutureBuilder<Map<String, Map<String, String>>>(
            future: _loadUserSearchData(idsToLoad),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting &&
                  !userSnapshot.hasData) {
                return Column(
                  children: [
                    _buildSummary(
                      allDocs.length,
                      openCount,
                      resolvedCount,
                      blockCount,
                    ),
                    _buildSearchBar(),
                    _buildFilters(),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }

              final users = userSnapshot.data ?? _userSearchCache;
              final docs = allDocs.where((d) {
                final data = d.data();
                final matchesFilter = switch (_statusFilter) {
                  'all' => true,
                  'block' => _isBlockReport(data),
                  'open' =>
                    (data['status'] ?? 'open').toString() == 'open' &&
                        !_isBlockReport(data),
                  _ => (data['status'] ?? 'open').toString() == _statusFilter,
                };
                if (!matchesFilter) return false;
                return _matchesSearch(d.id, data, users);
              }).toList();

              if (docs.isEmpty) {
                return Column(
                  children: [
                    _buildSummary(
                      allDocs.length,
                      openCount,
                      resolvedCount,
                      blockCount,
                    ),
                    _buildSearchBar(),
                    _buildFilters(),
                    Expanded(child: _buildEmptyState()),
                  ],
                );
              }

              return Column(
                children: [
                  _buildSummary(
                    allDocs.length,
                    openCount,
                    resolvedCount,
                    blockCount,
                  ),
                  _buildSearchBar(),
                  _buildFilters(),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();

                        final reportId = doc.id;
                        final reporterId = (data['reporterId'] ?? '')
                            .toString();
                        final reportedId = (data['reportedId'] ?? '')
                            .toString();
                        final reporterLabel = _userDisplayLabel(
                          reporterId,
                          users,
                        );
                        final reportedLabel = _userDisplayLabel(
                          reportedId,
                          users,
                        );
                        final subject = (data['subject'] ?? '').toString();
                        final reason = (data['reason'] ?? '').toString();
                        final details = (data['details'] ?? '').toString();
                        final reportType = (data['reportType'] ?? '')
                            .toString();
                        final source = (data['source'] ?? '').toString();
                        final status = (data['status'] ?? 'open').toString();
                        final displayStatus =
                            _isBlockReport(data) && status != 'resolved'
                            ? 'in_progress'
                            : status;
                        final displayStatusLabel =
                            _isBlockReport(data) && status != 'resolved'
                            ? 'Blocked'
                            : null;
                        final timestamp = data['timestamp'] as Timestamp?;
                        final attachments = _extractAttachments(data);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0.6,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openReportDetails(reportId, data),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          subject.isNotEmpty
                                              ? subject
                                              : (reason.isEmpty
                                                    ? 'General issue'
                                                    : reason),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      _statusBadge(
                                        displayStatus,
                                        label: displayStatusLabel,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reporter: ${reporterId.isEmpty ? '-' : reporterLabel}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    'Reported: ${reportedId.isEmpty ? '-' : reportedLabel}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          'Created: ${_displayTimestamp(timestamp)}',
                                        ),
                                      ),
                                      if (source.isNotEmpty)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text('Source: $source'),
                                        ),
                                      if (reportType.isNotEmpty)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text('Type: $reportType'),
                                        ),
                                    ],
                                  ),
                                  if (details.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      details,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (attachments.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _buildAttachmentsPreview(attachments),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _openReportDetails(reportId, data),
                                        icon: const Icon(Icons.open_in_new),
                                        label: const Text('Open'),
                                      ),
                                      if (status != 'resolved')
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _markResolved(reportId),
                                          icon: const Icon(
                                            Icons.check_circle_outline,
                                          ),
                                          label: const Text('Resolve'),
                                        ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _deleteReport(reportId),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'Delete',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
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
          );
        },
      ),
    );
  }
}

class AdminReportDetailsPage extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const AdminReportDetailsPage({
    super.key,
    required this.reportId,
    required this.data,
  });

  @override
  State<AdminReportDetailsPage> createState() => _AdminReportDetailsPageState();
}

class _AdminReportDetailsPageState extends State<AdminReportDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Map<String, dynamic> _data;
  final Map<String, Map<String, String>> _userDetailsCache = {};

  Map<String, dynamic> get _postDetailStrings => {
    'anonymous': 'Anonymous',
    'confirm_choose_worker_title': 'Choose this worker?',
    'confirm_choose_worker_body':
        'This will mark the worker as the selected offer for this job request.',
    'cancel': 'Cancel',
    'choose_worker': 'Choose Worker',
    'author': 'Author',
    'posted': 'Posted',
    'profession': 'Profession',
    'location': 'Location',
    'date_from': 'Date',
    'time_from': 'Time',
    'workers_can_offer':
        'Workers can place bids here, and you can choose the one you want.',
    'selected_worker': 'Selected Worker',
    'job_request_comment_restriction':
        'Only workers with an active subscription can comment on job requests.',
    'comments': 'Comments / Offers',
    'login': 'Login',
    'guest_msg': 'You need to sign in to do this.',
    'add_comment': 'Add a comment or offer...',
    'bid_price': 'Bid Price',
    'bid_price_hint': 'For example 350',
    'send_bid': 'Send Bid',
    'update_bid': 'Update Bid',
    'edit_your_bid': 'You can update your existing bid.',
  };

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
  }

  String _displayTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    final d = ts.toDate();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$month-$day $hour:$minute';
  }

  String _titleCase(String value) {
    final normalized = value.replaceAll('_', ' ');
    if (normalized.isEmpty) return '-';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  ({Color bg, Color fg, IconData icon}) _statusMeta(String status) {
    switch (status) {
      case 'resolved':
        return (
          bg: Colors.green.withValues(alpha: 0.12),
          fg: Colors.green.shade800,
          icon: Icons.check_circle_outline,
        );
      case 'in_progress':
        return (
          bg: Colors.blue.withValues(alpha: 0.12),
          fg: Colors.blue.shade800,
          icon: Icons.sync,
        );
      default:
        return (
          bg: Colors.orange.withValues(alpha: 0.12),
          fg: Colors.orange.shade800,
          icon: Icons.pending_outlined,
        );
    }
  }

  bool _isResolved(Map<String, dynamic> data) {
    return (data['status'] ?? 'open').toString() == 'resolved';
  }

  Future<Map<String, String>> _loadUserInfo(String userId) async {
    if (userId.isEmpty || userId == 'app') return const <String, String>{};
    final cached = _userDetailsCache[userId];
    if (cached != null) return cached;

    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data() ?? <String, dynamic>{};
    final resolved = {
      'name': (data['name'] ?? '').toString(),
      'phone': (data['phone'] ?? '').toString(),
    };
    _userDetailsCache[userId] = resolved;
    return resolved;
  }

  Future<void> _openReportedPost() async {
    final postId = (_data['postId'] ?? '').toString().trim();
    if (postId.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await _firestore.collection('blog_posts').doc(postId).get();
      if (!doc.exists) {
        messenger.showSnackBar(
          const SnackBar(content: Text('This post is no longer available.')),
        );
        return;
      }

      final post = Map<String, dynamic>.from(doc.data() ?? <String, dynamic>{});
      post['id'] = doc.id;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailPage(
            post: post,
            onLike: () {},
            onEdit: () {},
            onDelete: () {},
            onReport: () {},
            onBlockUser: () {},
            localizedStrings: _postDetailStrings,
            onGuestDialog: () {},
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to open the reported post.')),
      );
    }
  }

  Widget _statusBadge(String status) {
    final meta = _statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: meta.fg),
          const SizedBox(width: 4),
          Text(
            _titleCase(status),
            style: TextStyle(color: meta.fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _markResolved() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmAction(
      title: 'Resolve Report',
      content: 'Mark this report as resolved?',
      confirmLabel: 'Mark Resolved',
    );
    if (!confirmed) return;

    try {
      final now = Timestamp.now();
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final reporterId = (_data['reporterId'] ?? '').toString();
      final subject = (_data['subject'] ?? _data['reason'] ?? 'דיווח')
          .toString()
          .trim();
      final reportDoc = await _firestore
          .collection('reports')
          .doc(widget.reportId)
          .get();
      final wasResolved = _isResolved(reportDoc.data() ?? _data);
      await _firestore.collection('reports').doc(widget.reportId).set({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': adminId,
      }, SetOptions(merge: true));

      if (!wasResolved) {
        await _firestore.collection('metadata').doc('system').set({
          'reportsCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }

      await _sendResolvedMessageToReporter(
        reportId: widget.reportId,
        reporterId: reporterId,
        subject: subject,
      );

      if (!mounted) return;
      setState(() {
        _data['status'] = 'resolved';
        _data['resolvedAt'] = now;
        _data['resolvedBy'] = adminId;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Report marked as resolved.')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to update report status.')),
      );
    }
  }

  Future<void> _deleteReport() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmAction(
      title: 'Delete Report',
      content: 'This action cannot be undone. Delete this report?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    try {
      final reportDoc = await _firestore
          .collection('reports')
          .doc(widget.reportId)
          .get();
      final wasResolved = _isResolved(reportDoc.data() ?? _data);
      await _firestore.collection('reports').doc(widget.reportId).delete();
      if (!wasResolved) {
        await _firestore.collection('metadata').doc('system').set({
          'reportsCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Report deleted.')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to delete report.')),
      );
    }
  }

  String _getChatRoomId(String user1, String user2) {
    final ids = [user1, user2]..sort();
    return ids.join('_');
  }

  Future<void> _sendResolvedMessageToReporter({
    required String reportId,
    required String reporterId,
    required String subject,
  }) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid;
    if (adminId == null || reporterId.isEmpty || reporterId == 'app') return;

    final chatRoomId = _getChatRoomId(adminId, reporterId);

    final existingResolved = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('type', isEqualTo: 'report_resolved')
        .where('reportId', isEqualTo: reportId)
        .limit(1)
        .get();

    if (existingResolved.docs.isNotEmpty) return;

    await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .add({
          'senderId': adminId,
          'receiverId': reporterId,
          'message':
              'הדיווח שלך סומן כטופל: ${subject.isEmpty ? 'דיווח' : subject}',
          'type': 'report_resolved',
          'reportId': reportId,
          'timestamp': FieldValue.serverTimestamp(),
        });

    await _firestore.collection('chat_rooms').doc(chatRoomId).set({
      'lastMessage': '✅ הדיווח טופל',
      'lastTimestamp': FieldValue.serverTimestamp(),
      'users': [adminId, reporterId],
    }, SetOptions(merge: true));

    await _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'unreadCount.$reporterId': FieldValue.increment(1),
    });
  }

  Future<void> _answerReporter(String reporterId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || reporterId.isEmpty || reporterId == 'app') {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final chatRoomId = _getChatRoomId(currentUserId, reporterId);
    final subject = (_data['subject'] ?? _data['reason'] ?? 'Report')
        .toString()
        .trim();

    try {
      final existingReference = await _firestore
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .where('type', isEqualTo: 'report_reference')
          .where('reportId', isEqualTo: widget.reportId)
          .limit(1)
          .get();

      if (existingReference.docs.isEmpty) {
        await _firestore
            .collection('chat_rooms')
            .doc(chatRoomId)
            .collection('messages')
            .add({
              'senderId': currentUserId,
              'receiverId': reporterId,
              'message': 'Admin replied to your report: $subject',
              'type': 'report_reference',
              'reportId': widget.reportId,
              'timestamp': FieldValue.serverTimestamp(),
            });

        await _firestore.collection('chat_rooms').doc(chatRoomId).set({
          'lastMessage': '📌 Report update',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'users': [currentUserId, reporterId],
        }, SetOptions(merge: true));

        await _firestore.collection('chat_rooms').doc(chatRoomId).update({
          'unreadCount.$reporterId': FieldValue.increment(1),
        });
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            receiverId: reporterId,
            receiverName: reporterId,
            reportContextId: widget.reportId,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to open chat with report link.')),
      );
    }
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    IconData? icon,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.blue.shade700, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF475569)),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileLinkField(String label, String userId) {
    final isClickable = userId.isNotEmpty && userId != 'app';
    return FutureBuilder<Map<String, String>>(
      future: _loadUserInfo(userId),
      builder: (context, snapshot) {
        final info = snapshot.data ?? const <String, String>{};
        final name = (info['name'] ?? '').trim();
        final displayLabel = userId.isEmpty
            ? '-'
            : (name.isNotEmpty ? name : userId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: isClickable
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Profile(userId: userId),
                            ),
                          );
                        }
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      displayLabel,
                      style: TextStyle(
                        color: isClickable
                            ? Colors.blue.shade700
                            : Colors.black87,
                        decoration: isClickable
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationColor: isClickable
                            ? Colors.blue.shade700
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionLinkField({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final isClickable = onTap != null && value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: isClickable ? onTap : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  value.isEmpty ? '-' : value,
                  style: TextStyle(
                    color: isClickable ? Colors.blue.shade700 : Colors.black87,
                    decoration: isClickable
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: isClickable
                        ? Colors.blue.shade700
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _extractAttachments(Map<String, dynamic> data) {
    return ((data['attachments'] ?? []) as List)
        .whereType<Map>()
        .map(
          (e) => {
            'type': (e['type'] ?? '').toString(),
            'url': (e['url'] ?? '').toString(),
          },
        )
        .where((e) => e['url']!.isNotEmpty)
        .toList();
  }

  Widget _buildAttachmentsPreview(List<Map<String, String>> attachments) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = attachments[index];
          final isImage = item['type'] == 'image';
          final url = item['url'] ?? '';
          return InkWell(
            onTap: () => _openMediaViewer(attachments, index),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 240,
                color: Colors.black12,
                child: isImage
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(child: Icon(Icons.broken_image)),
                      )
                    : CachedVideoPlayer(url: url, play: false),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openMediaViewer(List<Map<String, String>> attachments, int index) {
    final urls = attachments
        .map((item) => (item['url'] ?? '').toString())
        .where((url) => url.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenMediaViewer(urls: urls, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subject = (_data['subject'] ?? '').toString();
    final reason = (_data['reason'] ?? '').toString();
    final details = (_data['details'] ?? '').toString();
    final status = (_data['status'] ?? 'open').toString();
    final source = (_data['source'] ?? '').toString();
    final reportType = (_data['reportType'] ?? '').toString();
    final adminSection = (_data['adminSection'] ?? '').toString();
    final reporterId = (_data['reporterId'] ?? '').toString();
    final reportedId = (_data['reportedId'] ?? '').toString();
    final postId = (_data['postId'] ?? '').toString();
    final postTitle = (_data['postTitle'] ?? '').toString();
    final resolvedBy = (_data['resolvedBy'] ?? '').toString();
    final unblockedBy = (_data['unblockedBy'] ?? '').toString();
    final timestamp = _data['timestamp'] as Timestamp?;
    final resolvedAt = _data['resolvedAt'] as Timestamp?;
    final unblockedAt = _data['unblockedAt'] as Timestamp?;
    final attachments = _extractAttachments(_data);
    final title = subject.isNotEmpty
        ? subject
        : (reason.isEmpty ? 'General issue' : reason);

    return Scaffold(
      appBar: AppBar(title: const Text('Report Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionCard(
              title: title,
              icon: Icons.assignment_outlined,
              subtitle:
                  'Review the report, inspect the people involved, and resolve it when you have enough context.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _statusBadge(status),
                      const Spacer(),
                      _metaChip(
                        _displayTimestamp(timestamp),
                        icon: Icons.schedule_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (source.isNotEmpty)
                        _metaChip('Source: $source', icon: Icons.link_outlined),
                      if (adminSection.isNotEmpty)
                        _metaChip(
                          'Queue: ${_titleCase(adminSection)}',
                          icon: Icons.inbox_outlined,
                        ),
                      if (reportType.isNotEmpty)
                        _metaChip(
                          'Type: $reportType',
                          icon: Icons.category_outlined,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'People & Audit',
              icon: Icons.people_outline,
              subtitle:
                  'Open the people involved, verify identity, and review status history.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Report ID', widget.reportId),
                  _profileLinkField('Reporter', reporterId),
                  _profileLinkField('Reported', reportedId),
                  if (postId.isNotEmpty)
                    _actionLinkField(
                      label: 'Post',
                      value: postTitle.isEmpty ? postId : postTitle,
                      onTap: _openReportedPost,
                    ),
                  if (reason.isNotEmpty && subject.isNotEmpty)
                    _field('Reason', reason),
                  _field('Resolved At', _displayTimestamp(resolvedAt)),
                  _field('Resolved By', resolvedBy),
                  _field('Unblocked At', _displayTimestamp(unblockedAt)),
                  _field('Unblocked By', unblockedBy),
                ],
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionCard(
                title: 'Details',
                icon: Icons.notes_outlined,
                subtitle: 'Full reporter description and context.',
                child: Text(
                  details,
                  style: const TextStyle(height: 1.5, color: Color(0xFF334155)),
                ),
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionCard(
                title: 'Attachments',
                icon: Icons.attach_file_outlined,
                subtitle:
                    'Open evidence in full screen to review screenshots or videos.',
                child: _buildAttachmentsPreview(attachments),
              ),
            ],
            const SizedBox(height: 12),
            _sectionCard(
              title: 'Actions',
              icon: Icons.flash_on_outlined,
              subtitle:
                  'Respond, copy context, open the profile, or resolve the case.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (reporterId.isNotEmpty && reporterId != 'app')
                    FilledButton.icon(
                      onPressed: () => _answerReporter(reporterId),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Answer Reporter'),
                    ),
                  FilledButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: widget.reportId),
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Report ID copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy Report ID'),
                  ),
                  if (postId.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _openReportedPost,
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Open Post'),
                    ),
                  if (reportedId.isNotEmpty && reportedId != 'app')
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Profile(userId: reportedId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Open Profile'),
                    ),
                  if (status != 'resolved')
                    OutlinedButton.icon(
                      onPressed: _markResolved,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Mark Resolved'),
                    ),
                  TextButton.icon(
                    onPressed: _deleteReport,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'Raw Data',
              icon: Icons.data_object_outlined,
              subtitle: 'Full stored payload for debugging and audit review.',
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'Show raw fields',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                children: _data.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _field(entry.key, entry.value?.toString() ?? ''),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
