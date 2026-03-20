import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/services/notification_service.dart';

class RequestDetailsPage extends StatefulWidget {
  final String notificationId;
  final Map<String, dynamic> data;

  const RequestDetailsPage({super.key, required this.notificationId, required this.data});

  @override
  State<RequestDetailsPage> createState() => _RequestDetailsPageState();
}

class _RequestDetailsPageState extends State<RequestDetailsPage> {
  late TimeOfDay _availableFrom;
  late TimeOfDay _availableTo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final reqFrom = widget.data['requestedFrom'];
    final reqTo = widget.data['requestedTo'];
    
    if (reqFrom != null) {
      try {
        final parts = reqFrom.split(':');
        _availableFrom = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        _availableFrom = const TimeOfDay(hour: 8, minute: 0);
      }
    } else {
      _availableFrom = const TimeOfDay(hour: 8, minute: 0);
    }

    if (reqTo != null) {
      try {
        final parts = reqTo.split(':');
        _availableTo = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        _availableTo = const TimeOfDay(hour: 16, minute: 0);
      }
    } else {
      _availableTo = const TimeOfDay(hour: 16, minute: 0);
    }
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'פרטי בקשת עבודה',
          'client': 'לקוח:',
          'location': 'מיקום:',
          'date': 'תאריך:',
          'requested_hours': 'שעות מבוקשות:',
          'job_description': 'תיאור העבודה:',
          'my_arrival': 'מתי אוכל להגיע?',
          'from': 'מ-',
          'to': 'עד',
          'accept': 'אישור והוספה ליומן',
          'decline': 'דחיית בקשה',
          'success': 'הבקשה אושרה בהצלחה',
          'declined': 'הבקשה נדחתה',
          'view_map': 'צפה במיקום במפה',
          'error_missing_id': 'שגיאה: חסר מזהה לקוח',
        };
      case 'ar':
        return {
          'title': 'تفاصيل طلب العمل',
          'client': 'العميل:',
          'location': 'الموقع:',
          'date': 'التاريخ:',
          'requested_hours': 'الساعات المطلوبة:',
          'job_description': 'وصف العمل:',
          'my_arrival': 'متى يمكنني الوصول؟',
          'from': 'من',
          'to': 'إلى',
          'accept': 'قبول وإضافة للجدول',
          'decline': 'رفض الطلب',
          'success': 'تم قبول الطلب بنجاح',
          'declined': 'تم رفض الطلب',
          'view_map': 'عرض الموقع على الخريطة',
          'error_missing_id': 'خطأ: معرف العميل مفقود',
        };
      default:
        return {
          'title': 'Work Request Details',
          'client': 'Client:',
          'location': 'Location:',
          'date': 'Date:',
          'requested_hours': 'Requested Hours:',
          'job_description': 'Job Description:',
          'my_arrival': 'When can I arrive?',
          'from': 'From',
          'to': 'To',
          'accept': 'Accept & Add to Schedule',
          'decline': 'Decline Request',
          'success': 'Request accepted successfully',
          'declined': 'Request declined',
          'view_map': 'View location on Map',
          'error_missing_id': 'Error: Missing Client ID',
        };
    }
  }

  Future<void> _openMap() async {
    final lat = widget.data['latitude'];
    final lng = widget.data['longitude'];
    if (lat != null && lng != null) {
      final Uri url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  Future<void> _processRequest(bool accept) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final clientId = widget.data['fromId'];
    final strings = _getLocalizedStrings(context);

    if (clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['error_missing_id']!)));
      return;
    }

    setState(() => _isLoading = true);

    final firestore = FirebaseFirestore.instance;
    final String date = widget.data['date'];

    try {
      // 1. Get Client's FCM Token for push notification
      final clientDoc = await firestore.collection('users').doc(clientId).get();
      final String? clientFcmToken = clientDoc.data()?['fcmToken'];

      final batch = firestore.batch();
      String? notifTitle;
      String? notifBody;

      if (accept) {
        final fStr = "${_availableFrom.hour.toString().padLeft(2, '0')}:${_availableFrom.minute.toString().padLeft(2, '0')}";
        final tStr = "${_availableTo.hour.toString().padLeft(2, '0')}:${_availableTo.minute.toString().padLeft(2, '0')}";

        // 2. Update Pro's Schedule
        batch.update(firestore.collection('users').doc(user.uid), {
          'availableDates': FieldValue.arrayUnion([date]),
          'partialWorkDays.$date': {'from': fStr, 'to': tStr},
        });

        notifTitle = strings['accept'];
        notifBody = "${user.displayName ?? 'The professional'} accepted your request for $date. Arrival: $fStr - $tStr";

        // 3. Notify Client in Firestore
        final clientNotifRef = firestore.collection('users').doc(clientId).collection('notifications').doc();
        batch.set(clientNotifRef, {
          'type': 'request_accepted',
          'fromId': user.uid,
          'fromName': user.displayName ?? 'Professional',
          'title': notifTitle,
          'body': notifBody,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        notifTitle = strings['declined'];
        notifBody = "${user.displayName ?? 'The professional'} cannot make it on $date";

        // Notify Client about Decline in Firestore
        final clientNotifRef = firestore.collection('users').doc(clientId).collection('notifications').doc();
        batch.set(clientNotifRef, {
          'type': 'request_declined',
          'fromId': user.uid,
          'fromName': user.displayName ?? 'Professional',
          'title': notifTitle,
          'body': notifBody,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // 4. Update current notification status in Pro's list
      batch.update(firestore.collection('users').doc(user.uid).collection('notifications').doc(widget.notificationId), {
        'status': accept ? 'accepted' : 'declined',
      });

      await batch.commit();

      // 5. Send FCM Push Notification to Client
      if (clientFcmToken != null) {
        await NotificationService.sendPushNotification(
          targetToken: clientFcmToken,
          title: notifTitle!,
          body: notifBody!,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accept ? strings['success']! : strings['declined']!)));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("FIRESTORE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(strings, data),
                  const SizedBox(height: 30),
                  Text(strings['my_arrival']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                  const SizedBox(height: 15),
                  _buildTimePickers(strings),
                  const SizedBox(height: 40),
                  _buildActionButtons(strings),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildInfoCard(Map<String, String> strings, Map<String, dynamic> data) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInfoRow(Icons.person, strings['client']!, data['fromName'] ?? 'Unknown'),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(child: _buildInfoRow(Icons.location_on, strings['location']!, data['fromLocation'] ?? 'Not specified')),
                if (data['latitude'] != null && data['longitude'] != null)
                  TextButton.icon(
                    onPressed: _openMap,
                    icon: const Icon(Icons.map, size: 18),
                    label: Text(strings['view_map']!, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const Divider(height: 20),
            _buildInfoRow(Icons.calendar_month, strings['date']!, data['date'] ?? ''),
            if (data['requestedFrom'] != null) ...[
              const Divider(height: 20),
              _buildInfoRow(Icons.access_time, strings['requested_hours']!, "${data['requestedFrom']} - ${data['requestedTo']}"),
            ],
            const Divider(height: 20),
            _buildInfoRow(Icons.description, strings['job_description']!, data['jobDescription'] ?? 'No description provided'),
          ],
        ),
      ),
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
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
          child: _buildTimeBox(strings['from']!, _availableFrom, (time) => setState(() => _availableFrom = time)),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildTimeBox(strings['to']!, _availableTo, (time) => setState(() => _availableTo = time)),
        ),
      ],
    );
  }

  Widget _buildTimeBox(String label, TimeOfDay time, Function(TimeOfDay) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time);
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 5),
            Text(time.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, String> strings) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: () => _processRequest(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(strings['accept']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: OutlinedButton(
            onPressed: () => _processRequest(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(strings['decline']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
