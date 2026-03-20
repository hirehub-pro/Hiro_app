import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:untitled1/language_provider.dart';

class SendRequestPage extends StatefulWidget {
  final String workerId;
  final String workerName;
  final DateTime selectedDay;
  final bool isExtraHours;
  final String? initialFrom;
  final String? initialTo;

  const SendRequestPage({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.selectedDay,
    this.isExtraHours = false,
    this.initialFrom,
    this.initialTo,
  });

  @override
  State<SendRequestPage> createState() => _SendRequestPageState();
}

class _SendRequestPageState extends State<SendRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();
  
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  Position? _currentPosition;
  bool _isLoading = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    if (widget.isExtraHours) {
      if (widget.initialFrom != null) {
        final parts = widget.initialFrom!.split(':');
        _fromTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } else {
        _fromTime = const TimeOfDay(hour: 8, minute: 0);
      }
      
      if (widget.initialTo != null) {
        final parts = widget.initialTo!.split(':');
        _toTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } else {
        _toTime = const TimeOfDay(hour: 16, minute: 0);
      }
    } else {
       _fromTime = const TimeOfDay(hour: 8, minute: 0);
       _toTime = const TimeOfDay(hour: 16, minute: 0);
    }
    _fetchLocation();
  }

  Future<void> _fetchLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLocating = false);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = pos;
        _isLocating = false;
      });
    } catch (e) {
      debugPrint("Error fetching location: $e");
      setState(() => _isLocating = false);
    }
  }

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((file) => File(file.path)));
      });
    }
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'שליחת בקשת עבודה',
          'worker': 'בעל מקצוע:',
          'date': 'תאריך:',
          'desc_label': 'תיאור העבודה',
          'desc_hint': 'תאר את העבודה שאתה צריך...',
          'images': 'תמונות (אופציונלי)',
          'location': 'מיקום GPS',
          'loc_found': 'המיקום נמצא',
          'loc_not_found': 'מחפש מיקום...',
          'from': 'מ-',
          'to': 'עד',
          'send': 'שלח בקשה',
          'req': 'שדה חובה',
          'sending': 'שולח...',
          'success': 'הבקשה נשלחה בהצלחה',
          'error': 'שליחת הבקשה נכשלה',
          'not_pro_warning': 'זהו עובד שאינו בסטטוס PRO. ייתכן שזמן התגובה יהיה איטי יותר.',
          'chat_request_msg': 'שלחתי לך בקשת עבודה לתאריך: ',
        };
      case 'ar':
        return {
          'title': 'إرسال طلب عمل',
          'worker': 'المحترف:',
          'date': 'التاريخ:',
          'desc_label': 'وصف العمل',
          'desc_hint': 'صف العمل الذي تحتاجه...',
          'images': 'الصور (اختياري)',
          'location': 'موقع GPS',
          'loc_found': 'تم العثور على الموقع',
          'loc_not_found': 'جاري البحث عن الموقع...',
          'from': 'من',
          'to': 'إلى',
          'send': 'إرسال الطلب',
          'req': 'مطلوب',
          'sending': 'جاري الإرسال...',
          'success': 'تم إرسال الطلب بنجاح',
          'error': 'فشل إرسال الطلب',
          'not_pro_warning': 'هذا العامل ليس في حالة PRO. قد يكون وقت الاستجابة أبطأ.',
          'chat_request_msg': 'لقד أرسلت لك طلب عمل بتاريخ: ',
        };
      default:
        return {
          'title': 'Send Work Request',
          'worker': 'Professional:',
          'date': 'Date:',
          'desc_label': 'Job Description',
          'desc_hint': 'Describe the job you need...',
          'images': 'Images (Optional)',
          'location': 'GPS Location',
          'loc_found': 'Location found',
          'loc_not_found': 'Locating...',
          'from': 'From',
          'to': 'To',
          'send': 'Send Request',
          'req': 'Required',
          'sending': 'Sending...',
          'success': 'Request sent successfully',
          'error': 'Failed to send request',
          'not_pro_warning': 'This worker is not in PRO status. Response time might be slower.',
          'chat_request_msg': 'I sent you a work request for: ',
        };
    }
  }

  /// Sends a push notification via FCM directly from the app (Workaround for Cloud Functions)
  /// Note: In production, this should be done via Firebase Cloud Functions for security.
  Future<void> _sendFCMNotification(String targetToken, String title, String body) async {
    // You will need to set up a Service Account or use the legacy FCM API with a Server Key.
    // For the modern FCM v1 API, you usually need a bearer token from a server.
    // I am including the structure here so you can see where the logic goes.
    try {
      // THIS IS A PLACEHOLDER. You should replace this with a call to your backend or Cloud Function.
      // Example of a Direct Post (Requires Server Key - Legacy):
      /*
      await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_SERVER_KEY',
        },
        body: jsonEncode({
          'to': targetToken,
          'notification': {'title': title, 'body': body},
          'data': {'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
        }),
      );
      */
      debugPrint("FCM trigger would happen here for token: $targetToken");
    } catch (e) {
      debugPrint("FCM error: $e");
    }
  }

  String _getChatRoomId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return ids.join('_');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final strings = _getLocalizedStrings(context);
    final dStr = "${widget.selectedDay.year}-${widget.selectedDay.month}-${widget.selectedDay.day}";

    try {
      // 1. Upload Images
      List<String> imageUrls = [];
      for (var i = 0; i < _images.length; i++) {
        final ref = FirebaseStorage.instance.ref().child('request_images/${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
        await ref.putFile(_images[i]);
        imageUrls.add(await ref.getDownloadURL());
      }

      // 2. Get User Info (Client)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final userName = userData?['name'] ?? 'Client';
      final userTown = userData?['town'];

      // 3. Get Worker's FCM Token
      final workerDoc = await FirebaseFirestore.instance.collection('users').doc(widget.workerId).get();
      final workerData = workerDoc.data();
      final String? workerFcmToken = workerData?['fcmToken'];
      final bool isWorkerPro = workerData?['isPro'] ?? false;

      final fStr = _fromTime != null ? "${_fromTime!.hour.toString().padLeft(2, '0')}:${_fromTime!.minute.toString().padLeft(2, '0')}" : null;
      final tStr = _toTime != null ? "${_toTime!.hour.toString().padLeft(2, '0')}:${_toTime!.minute.toString().padLeft(2, '0')}" : null;

      final String notifTitle = widget.isExtraHours ? 'Extra Hours Request' : 'Work Request';
      final String notifBody = !widget.isExtraHours 
            ? "$userName ($userTown) requested you to work on $dStr."
            : "$userName ($userTown) requested you to work on $dStr from $fStr to $tStr.";

      // 4. Create Notification in Firestore (for the in-app list)
      await FirebaseFirestore.instance.collection('users').doc(widget.workerId).collection('notifications').add({
        'type': 'work_request',
        'fromId': user.uid,
        'fromName': userName,
        'fromLocation': userTown,
        'jobDescription': _descriptionController.text.trim(),
        'images': imageUrls,
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
        'date': dStr,
        'requestedFrom': fStr,
        'requestedTo': tStr,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'title': notifTitle,
        'body': notifBody,
      });

      // 5. Add message to chat room
      final chatRoomId = _getChatRoomId(user.uid, widget.workerId);
      final chatMsg = "${strings['chat_request_msg']}$dStr\n${_descriptionController.text.trim()}";
      
      await FirebaseFirestore.instance.collection('chat_rooms').doc(chatRoomId).collection('messages').add({
        'senderId': user.uid,
        'receiverId': widget.workerId,
        'message': chatMsg,
        'timestamp': FieldValue.serverTimestamp(),
        'isSystem': true, // Optional: flag to style differently
      });

      await FirebaseFirestore.instance.collection('chat_rooms').doc(chatRoomId).set({
        'lastMessage': chatMsg,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'users': [user.uid, widget.workerId],
        'userNames': {
          user.uid: userName,
          widget.workerId: widget.workerName,
        }
      }, SetOptions(merge: true));

      // 6. Send FCM Push Notification
      if (workerFcmToken != null) {
        await _sendFCMNotification(workerFcmToken, notifTitle, notifBody);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['success']!)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Submit error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['error']!)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
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
        body: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(widget.workerId).get(),
          builder: (context, snapshot) {
            bool isPro = true;
            if (snapshot.hasData) {
              isPro = (snapshot.data!.data() as Map<String, dynamic>?)?['isPro'] ?? false;
            }

            return _isLoading 
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(strings['sending']!),
                  ],
                ))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isPro) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber[200]!)),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                                const SizedBox(width: 12),
                                Expanded(child: Text(strings['not_pro_warning']!, style: const TextStyle(fontSize: 13, color: Colors.brown))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        _buildInfoSection(strings),
                        const SizedBox(height: 24),
                        
                        Text(strings['desc_label']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: strings['desc_hint'],
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          validator: (v) => v!.isEmpty ? strings['req'] : null,
                        ),
                        const SizedBox(height: 24),

                        _buildTimeSection(strings),
                        const SizedBox(height: 24),

                        Text(strings['images']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        _buildImagePicker(),
                        const SizedBox(height: 24),

                        _buildLocationCard(strings),
                        const SizedBox(height: 40),

                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text(strings['send']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          }
        ),
      ),
    );
  }

  Widget _buildInfoSection(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF1976D2)),
              const SizedBox(width: 12),
              Text(strings['worker']!, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              Text(widget.workerName, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_month, color: Color(0xFF1976D2)),
              const SizedBox(width: 12),
              Text(strings['date']!, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              Text("${widget.selectedDay.day}/${widget.selectedDay.month}/${widget.selectedDay.year}", style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSection(Map<String, String> strings) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings['from']!, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: _fromTime!);
                  if (picked != null) setState(() => _fromTime = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [const Icon(Icons.access_time, size: 18), const SizedBox(width: 8), Text(_fromTime!.format(context))]),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings['to']!, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: _toTime!);
                  if (picked != null) setState(() => _toTime = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [const Icon(Icons.access_time, size: 18), const SizedBox(width: 8), Text(_toTime!.format(context))]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length + 1,
        itemBuilder: (context, index) {
          if (index == _images.length) {
            return InkWell(
              onTap: _pickImages,
              child: Container(
                width: 100,
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                child: const Icon(Icons.add_a_photo, color: Colors.grey, size: 32),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_images[index], width: 100, height: 100, fit: BoxFit.cover),
                ),
                Positioned(
                  right: 4, top: 4,
                  child: InkWell(
                    onTap: () => setState(() => _images.removeAt(index)),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocationCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.location_on, color: _currentPosition != null ? Colors.green : Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings['location']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(_currentPosition != null ? strings['loc_found']! : strings['loc_not_found']!, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
          if (_isLocating)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLocation),
        ],
      ),
    );
  }
}
