import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/request_details.dart';
import 'package:rxdart/rxdart.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

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

    if (user == null || user.isAnonymous) {
      return _buildScaffold(context, strings, isRtl, user);
    }

    return _buildScaffold(context, strings, isRtl, user);
  }

  Widget _buildScaffold(
    BuildContext context,
    Map<String, String> strings,
    bool isRtl,
    User? user,
  ) {
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            strings['title']!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          actions: [
            if (user != null && !user.isAnonymous)
              TextButton(
                onPressed: () async {
                  final snapshots = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('notifications')
                      .get();

                  if (snapshots.docs.isEmpty) return;

                  final batch = FirebaseFirestore.instance.batch();
                  for (var doc in snapshots.docs) {
                    batch.delete(doc.reference);
                  }
                  await batch.commit();
                },
                child: Text(
                  strings['clear']!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body: (user == null || user.isAnonymous)
            ? _buildEmptyState(strings)
            : StreamBuilder<List<Map<String, dynamic>>>(
                stream: CombineLatestStream.combine2(
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('notifications')
                      .snapshots(),
                  FirebaseFirestore.instance
                      .collection('system_announcements')
                      .snapshots(),
                  (QuerySnapshot personal, QuerySnapshot system) {
                    List<Map<String, dynamic>> all = [];
                    for (var doc in personal.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      data['id'] = doc.id;
                      data['isBroadcast'] = false;
                      all.add(data);
                    }
                    for (var doc in system.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      data['id'] = doc.id;
                      data['isBroadcast'] = true;
                      data['type'] = 'broadcast';
                      data['body'] =
                          data['message']; // Map 'message' to 'body' for consistency
                      all.add(data);
                    }
                    all.sort((a, b) {
                      final Timestamp? tA = a['timestamp'] as Timestamp?;
                      final Timestamp? tB = b['timestamp'] as Timestamp?;
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
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState(strings);
                  }

                  final notifications = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final data = notifications[index];
                      return _buildNotificationCard(
                        context,
                        data['id'],
                        data,
                        strings,
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState(Map<String, String> strings) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            strings['empty']!,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    Map<String, String> strings,
  ) {
    final bool isActionableRequest =
        data['type'] == 'work_request' || data['type'] == 'quote_request';
    final bool isBroadcast = data['isBroadcast'] == true;
    final String status = data['status'] ?? 'none';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: isBroadcast ? Colors.blue.shade50 : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isActionableRequest && status == 'pending'
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RequestDetailsPage(notificationId: docId, data: data),
                ),
              )
            : null,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isBroadcast ? Colors.blue : const Color(0xFF1976D2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBroadcast
                      ? Icons.campaign
                      : (isActionableRequest
                            ? Icons.calendar_today
                            : Icons.notifications_active),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(
                data['title'] ??
                    (isBroadcast ? strings['broadcast']! : 'Notification'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(data['body'] ?? data['message'] ?? ''),
                  if (data['timestamp'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(data['timestamp']),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ],
              ),
              trailing: isActionableRequest && status == 'pending'
                  ? const Icon(Icons.chevron_right, color: Colors.grey)
                  : null,
            ),
            if (isActionableRequest && status != 'pending')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: status == 'accepted'
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            status == 'accepted'
                                ? strings['accepted']!
                                : strings['declined']!,
                            style: TextStyle(
                              color: status == 'accepted'
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return "${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    }
    return '';
  }
}
