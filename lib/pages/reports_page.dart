import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/widgets/cached_video_player.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  String _statusFilter = 'all';
  static const int _maxReportAttachments = 5;

  static const List<String> _statuses = ['all', 'open', 'resolved', 'block'];
  static const List<String> _readySubjects = [
    'General',
    'Bug Report',
    'Payment Issue',
    'Login Problem',
    'Feature Request',
    'Account Support',
    'Performance Issue',
    'Content Problem',
  ];

  String _titleCaseStatus(String status) {
    final normalized = status.replaceAll('_', ' ');
    if (normalized.isEmpty) return 'Unknown';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  ({Color bg, Color fg, IconData icon}) _statusMeta(String status) {
    switch (status) {
      case 'blocked':
        return (
          bg: Colors.orange.withValues(alpha: 0.14),
          fg: Colors.orange.shade900,
          icon: Icons.block_outlined,
        );
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
      case 'rejected':
        return (
          bg: Colors.red.withValues(alpha: 0.12),
          fg: Colors.red.shade800,
          icon: Icons.cancel_outlined,
        );
      case 'open':
      default:
        return (
          bg: Colors.orange.withValues(alpha: 0.12),
          fg: Colors.orange.shade800,
          icon: Icons.pending_outlined,
        );
    }
  }

  bool _isBlockReport(Map<String, dynamic> data) {
    final reportType = (data['reportType'] ?? '').toString();
    if (reportType == 'user_block') return true;
    final blockedUid = (data['blockedUid'] ?? '').toString();
    final blockedByUid = (data['blockedByUid'] ?? '').toString();
    return blockedUid.isNotEmpty || blockedByUid.isNotEmpty;
  }

  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String confirmLabel,
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _unblockUser(String reportId, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final blockedUid = (data['blockedUid'] ?? data['reportedId'] ?? '')
        .toString();
    if (blockedUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing blocked user data.')),
      );
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Unblock User',
      content: 'Remove this user from your blocked list?',
      confirmLabel: 'Unblock',
    );
    if (!confirmed) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('blocked_users')
          .doc(blockedUid)
          .delete();

      final reportRef = _firestore.collection('reports').doc(reportId);
      final reportSnapshot = await reportRef.get();
      final wasResolved =
          (reportSnapshot.data()?['status'] ?? data['status'] ?? 'open')
              .toString() ==
          'resolved';
      await reportRef.delete();

      if (!wasResolved) {
        await _firestore.collection('metadata').doc('system').set({
          'reportsCount': FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User removed from your blocked list.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to unblock this user.')),
      );
    }
  }

  Future<void> _openCreateReportDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final reasonController = TextEditingController();
    final detailsController = TextEditingController();
    String selectedSubject = _readySubjects.first;
    final attachments = <_DraftReportAttachment>[];

    Future<void> pickImage(StateSetter setDialogState) async {
      if (attachments.length >= _maxReportAttachments) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can attach up to 5 files only.')),
        );
        return;
      }
      final pickedFiles = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (pickedFiles.isEmpty) return;

      final remainingSlots = _maxReportAttachments - attachments.length;
      final filesToAdd = pickedFiles.take(remainingSlots).toList();
      setDialogState(() {
        attachments.addAll(
          filesToAdd.map((f) => _DraftReportAttachment(type: 'image', file: f)),
        );
      });

      if (pickedFiles.length > remainingSlots && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only 5 total attachments are allowed.'),
          ),
        );
      }
    }

    Future<void> pickVideo(StateSetter setDialogState) async {
      if (attachments.length >= _maxReportAttachments) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can attach up to 5 files only.')),
        );
        return;
      }
      final picked = await _picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      setDialogState(() {
        attachments.add(_DraftReportAttachment(type: 'video', file: picked));
      });
    }

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.assignment_add,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Create Report',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tell us what happened so we can investigate quickly.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSubject,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Subject',
                        prefixIcon: const Icon(Icons.category_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF7FBFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: _readySubjects
                          .map(
                            (subject) => DropdownMenuItem<String>(
                              value: subject,
                              child: Text(
                                subject,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedSubject = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLength: 80,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Short title for the issue',
                        prefixIcon: const Icon(Icons.short_text_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF7FBFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: detailsController,
                      minLines: 5,
                      maxLines: 7,
                      maxLength: 600,
                      decoration: InputDecoration(
                        labelText: 'Details',
                        hintText:
                            'Describe the issue and steps to reproduce...',
                        alignLabelWithHint: true,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 92),
                          child: Icon(Icons.notes_outlined),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF7FBFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.attach_file_outlined,
                                size: 20,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Attachments',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  '${attachments.length}/$_maxReportAttachments',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Images or videos help the team understand the issue faster.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => pickImage(setDialogState),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Add Image'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => pickVideo(setDialogState),
                                icon: const Icon(Icons.video_library_outlined),
                                label: const Text('Add Video'),
                              ),
                            ],
                          ),
                          if (attachments.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 104,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: attachments.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final item = attachments[index];
                                  return Stack(
                                    children: [
                                      Container(
                                        width: 136,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: item.type == 'image'
                                            ? Image.file(
                                                File(item.file.path),
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: const Color(0xFF111827),
                                                padding: const EdgeInsets.all(
                                                  10,
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.videocam_rounded,
                                                      color: Colors.white70,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      item.file.name,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                      Positioned(
                                        right: 6,
                                        top: 6,
                                        child: Material(
                                          color: Colors.black54,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () {
                                              setDialogState(() {
                                                attachments.removeAt(index);
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.send_outlined),
                label: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );

    if (submit != true) return;

    final subject = selectedSubject.trim();
    final reason = reasonController.text.trim();
    final details = detailsController.text.trim();
    final progress = ValueNotifier<double>(attachments.isEmpty ? 0.8 : 0.0);

    try {
      var progressDialogShown = false;
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: const Text('Sending report'),
                content: ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, _) {
                    final clamped = value.clamp(0.0, 1.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: clamped),
                        const SizedBox(height: 10),
                        Text('${(clamped * 100).toStringAsFixed(0)}%'),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
        progressDialogShown = true;
      }

      List<Map<String, String>> uploadedAttachments = [];
      if (attachments.isNotEmpty) {
        uploadedAttachments = await _uploadReportAttachments(
          reporterId: user.uid,
          attachments: attachments,
          onProgress: (value) {
            progress.value = value * 0.85;
          },
        );
      }

      progress.value = 0.9;
      await _firestore.collection('reports').add({
        'reporterId': user.uid,
        'reportedId': 'app',
        'reportType': 'user_report',
        'source': 'reports_page',
        'subject': subject.isEmpty ? 'General' : subject,
        'reason': reason.isEmpty ? 'General issue' : reason,
        'details': details,
        'attachments': uploadedAttachments,
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
      });

      progress.value = 0.98;
      await _firestore.collection('metadata').doc('system').set({
        'reportsCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      progress.value = 1.0;

      if (!mounted) return;
      if (progressDialogShown &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (_) {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to submit report.')));
    } finally {
      progress.dispose();
    }
  }

  Future<List<Map<String, String>>> _uploadReportAttachments({
    required String reporterId,
    required List<_DraftReportAttachment> attachments,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = <Map<String, String>>[];
    for (var i = 0; i < attachments.length; i++) {
      final item = attachments[i];
      final ext = item.file.name.contains('.')
          ? item.file.name.split('.').last
          : (item.type == 'image' ? 'jpg' : 'mp4');
      final path =
          'reports/$reporterId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final ref = _storage.ref().child(path);
      final task = ref.putFile(
        File(item.file.path),
        SettableMetadata(
          contentType: item.type == 'image' ? 'image/jpeg' : 'video/mp4',
        ),
      );
      final subscription = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        final current = snapshot.bytesTransferred;
        final fileProgress = total > 0 ? current / total : 0.0;
        final overall = (i + fileProgress) / attachments.length;
        onProgress?.call(overall);
      });
      await task;
      await subscription.cancel();
      onProgress?.call((i + 1) / attachments.length);
      final url = await ref.getDownloadURL();
      uploaded.add({'type': item.type, 'url': url, 'fileName': item.file.name});
    }
    return uploaded;
  }

  Query<Map<String, dynamic>> _reportsQuery(String uid) {
    var query = _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: uid);
    if (_statusFilter != 'all' &&
        _statusFilter != 'block' &&
        _statusFilter != 'open') {
      query = query.where('status', isEqualTo: _statusFilter);
    }
    return query;
  }

  String _formatDate(DateTime createdAt) {
    final month = createdAt.month.toString().padLeft(2, '0');
    final day = createdAt.day.toString().padLeft(2, '0');
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '${createdAt.year}-$month-$day $hour:$minute';
  }

  Widget _statusBadge(String status, {String? label}) {
    final statusMeta = _statusMeta(status);
    final displayLabel = label ?? _titleCaseStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusMeta.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusMeta.icon, size: 14, color: statusMeta.fg),
          const SizedBox(width: 4),
          Text(
            displayLabel,
            style: TextStyle(
              color: statusMeta.fg,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  ({Color tint, Color border, Color text, IconData icon, String label})
  _cardMeta(Map<String, dynamic> data) {
    if (_isBlockReport(data)) {
      return (
        tint: const Color(0xFFFFF7ED),
        border: const Color(0xFFFDBA74),
        text: const Color(0xFF9A3412),
        icon: Icons.shield_outlined,
        label: 'Blocked User',
      );
    }
    return (
      tint: const Color(0xFFF8FAFC),
      border: const Color(0xFFE2E8F0),
      text: const Color(0xFF334155),
      icon: Icons.description_outlined,
      label: 'Report',
    );
  }

  Widget _pill({
    required String text,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userProfileLink({required String userId, required bool blocked}) {
    final label = blocked ? 'Blocked user' : 'Reported user';
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final resolvedName = (data?['name'] ?? '').toString().trim();
        final displayName = resolvedName.isNotEmpty ? resolvedName : userId;

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => Profile(userId: userId)),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 10),
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
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignedOutState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 0.6,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_outline, size: 46, color: Colors.blueGrey),
                  SizedBox(height: 12),
                  Text(
                    'Sign in required',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please sign in to create reports and track their status updates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: _statuses.map((status) {
          final selected = _statusFilter == status;
          final statusMeta = _statusMeta(status);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: status == 'all'
                  ? const Icon(Icons.apps, size: 16)
                  : Icon(statusMeta.icon, size: 16),
              label: Text(_titleCaseStatus(status)),
              selected: selected,
              onSelected: (_) => setState(() => _statusFilter = status),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopSummary() {
    final activeFilter = switch (_statusFilter) {
      'all' => 'Showing all reports',
      'block' => 'Showing blocked-user and safety items',
      _ => 'Filtered by ${_titleCaseStatus(_statusFilter)}',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.indigo.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Reports',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activeFilter,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final message = switch (_statusFilter) {
      'all' => 'No reports yet. Start by creating your first report.',
      'block' => 'No blocked-user or safety items found.',
      _ => 'No ${_titleCaseStatus(_statusFilter).toLowerCase()} reports found.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.report_problem_outlined,
                size: 44,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCreateReportDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Report'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> data, String id) {
    final reason = (data['reason'] ?? '').toString();
    final details = (data['details'] ?? '').toString();
    final status = (data['status'] ?? 'open').toString();
    final isBlockCard = _isBlockReport(data);
    final canUnblock = isBlockCard && status != 'resolved';
    final displayStatus = canUnblock ? 'blocked' : status;
    final cardMeta = _cardMeta(data);
    final subject = (data['subject'] ?? data['priority'] ?? 'General')
        .toString()
        .trim();
    final relatedUserId =
        ((data['blockedUid'] ?? '').toString().isNotEmpty
                ? data['blockedUid']
                : data['reportedId'])
            .toString();
    final attachments = ((data['attachments'] ?? []) as List)
        .whereType<Map>()
        .map(
          (e) => {
            'type': (e['type'] ?? '').toString(),
            'url': (e['url'] ?? '').toString(),
            'fileName': (e['fileName'] ?? '').toString(),
          },
        )
        .where((e) => e['url']!.isNotEmpty)
        .toList();
    final ts = data['timestamp'] as Timestamp?;
    final createdAt = ts?.toDate();
    final dateText = createdAt == null
        ? 'Pending time sync'
        : _formatDate(createdAt);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cardMeta.border),
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
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cardMeta.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cardMeta.icon, color: cardMeta.text),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason.isEmpty ? 'General issue' : reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateText,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusBadge(
                      displayStatus,
                      label: canUnblock ? 'Blocked' : null,
                    ),
                    if (canUnblock) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _unblockUser(id, data),
                        icon: const Icon(Icons.lock_open_outlined, size: 16),
                        label: const Text('Unblock'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.orange.shade800,
                          side: BorderSide(color: Colors.orange.shade200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  text: cardMeta.label,
                  background: cardMeta.tint,
                  foreground: cardMeta.text,
                  icon: cardMeta.icon,
                ),
                _pill(
                  text: subject.isEmpty ? 'General' : subject,
                  background: Colors.indigo.withValues(alpha: 0.1),
                  foreground: Colors.indigo.shade800,
                ),
              ],
            ),
            if (relatedUserId.isNotEmpty && relatedUserId != 'app') ...[
              const SizedBox(height: 14),
              _userProfileLink(userId: relatedUserId, blocked: isBlockCard),
            ],
            if (canUnblock) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.visibility_off_outlined,
                      size: 18,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This user is hidden from your feed. Unblock them to allow their content to appear again.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                details,
                maxLines: canUnblock ? 4 : 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF334155), height: 1.45),
              ),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.attach_file_outlined,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Attachments',
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${attachments.length}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: attachments.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = attachments[index];
                    final isImage = item['type'] == 'image';
                    final url = item['url'] ?? '';
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 180,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isImage
                            ? Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                              )
                            : CachedVideoPlayer(url: url, play: false),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Report ID: $id',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: id));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report ID copied'),
                        duration: Duration(milliseconds: 1200),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 15),
                  label: const Text('Copy ID'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      floatingActionButton: user == null || user.isAnonymous
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCreateReportDialog,
              icon: const Icon(Icons.edit_note),
              label: const Text('New Report'),
            ),
      body: user == null || user.isAnonymous
          ? _buildSignedOutState()
          : Column(
              children: [
                _buildTopSummary(),
                _buildFilterBar(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _reportsQuery(user.uid).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 48,
                                  color: Colors.redAccent,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Could not load reports. Please try again shortly.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs.toList()
                        ..retainWhere((doc) {
                          if (_statusFilter == 'block') {
                            return _isBlockReport(doc.data());
                          }
                          if (_statusFilter == 'open') {
                            final data = doc.data();
                            return (data['status'] ?? 'open').toString() ==
                                    'open' &&
                                !_isBlockReport(data);
                          }
                          return true;
                        })
                        ..sort((a, b) {
                          final ta = a.data()['timestamp'] as Timestamp?;
                          final tb = b.data()['timestamp'] as Timestamp?;
                          if (ta == null && tb == null) return 0;
                          if (ta == null) return 1;
                          if (tb == null) return -1;
                          return tb.compareTo(ta);
                        });

                      if (docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return _buildReportCard(doc.data(), doc.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _DraftReportAttachment {
  final String type;
  final XFile file;

  const _DraftReportAttachment({required this.type, required this.file});
}
