import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:intl/intl.dart' as intl;
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/pages/my_request_details_page.dart';
import 'package:untitled1/pages/request_details.dart';

import '../widgets/cached_video_player.dart';
import '../widgets/zoomable_image_viewer.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? reportContextId;

  const ChatPage({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.reportContextId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ScrollController _scrollController = ScrollController();

  final AudioRecorder _audioRecorder = AudioRecorder();
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration>? _audioDurationSubscription;
  StreamSubscription<ap.PlayerState>? _audioStateSubscription;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _activeAudioUrl;
  Duration _activeAudioPosition = Duration.zero;
  Duration _activeAudioDuration = Duration.zero;
  ap.PlayerState _audioPlayerState = ap.PlayerState.stopped;
  final Map<String, String> _localMediaPaths = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingUrls = {};
  final Set<String> _failedDownloads = {};
  final Map<String, Future<String?>> _localResolveFutures = {};
  final List<_PendingMediaUpload> _pendingMediaUploads = [];
  late Stream<QuerySnapshot> _messageStream;

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

  bool _isWorker = false;
  bool _canCreateInvoices = false;
  String? _currentUserName;
  String? _currentUserPhone;
  String? _currentUserEmail;

  String _t({
    required String en,
    String? he,
    String? ar,
    String? am,
    String? ru,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return he ?? en;
      case 'ar':
        return ar ?? en;
      case 'am':
        return am ?? en;
      case 'ru':
        return ru ?? en;
      default:
        return en;
    }
  }

  @override
  void initState() {
    super.initState();
    _wireAudioPlayer();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _checkUserType();
    final currentUserId = _auth.currentUser!.uid;
    final chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);
    _messageStream = _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _resetUnreadCount(chatRoomId, currentUserId);
    _setActiveChat(currentUserId);
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _ChatPageLifecycleObserver(
        onResumed: () {
          final userId = _auth.currentUser?.uid;
          if (userId != null) {
            _setActiveChat(userId);
          }
        },
        onBackgrounded: () {
          final userId = _auth.currentUser?.uid;
          if (userId != null) {
            _clearActiveChat(userId);
          }
        },
      );

  void _resetUnreadCount(String chatRoomId, String userId) {
    _firestore.collection('chat_rooms').doc(chatRoomId).set({
      'unreadCount': {userId: 0},
    }, SetOptions(merge: true));
  }

  Future<DocumentSnapshot?> _getUserDoc(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists ? doc : null;
  }

  void _checkUserType() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final doc = await _getUserDoc(user.uid);
        if (doc != null && doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _isWorker = data['role'] == 'worker';
            _canCreateInvoices =
                _isWorker &&
                SubscriptionAccessService.hasActiveWorkerSubscriptionFromData(
                  data,
                );
            _currentUserName = data['name'] ?? user.displayName;
            _currentUserPhone = data['phone'];
            _currentUserEmail = data['email'] ?? user.email;
          });
        }
      } catch (e) {
        debugPrint("Error checking user type: $e");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      _clearActiveChat(userId);
    }
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _wireAudioPlayer() {
    _audioPositionSubscription = _audioPlayer.onPositionChanged.listen((
      position,
    ) {
      if (!mounted) return;
      if (_activeAudioDuration > Duration.zero &&
          position >=
              _activeAudioDuration - const Duration(milliseconds: 250)) {
        _resetActiveAudioToStart();
        return;
      }
      setState(() => _activeAudioPosition = position);
    });

    _audioDurationSubscription = _audioPlayer.onDurationChanged.listen((
      duration,
    ) {
      if (!mounted) return;
      setState(() => _activeAudioDuration = duration);
    });

    _audioStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == ap.PlayerState.completed) {
        _resetActiveAudioToStart();
        return;
      }
      setState(() {
        _audioPlayerState = state;
        if (state == ap.PlayerState.stopped) {
          _activeAudioPosition = Duration.zero;
        }
      });
    });
  }

  Future<void> _resetActiveAudioToStart() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint("Audio reset error: $e");
    }

    if (!mounted) return;
    setState(() {
      _activeAudioPosition = Duration.zero;
      _audioPlayerState = ap.PlayerState.stopped;
    });
  }

  Future<void> _setActiveChat(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'activeChatWith': widget.receiverId,
        'activeChatUpdatedAt': FieldValue.serverTimestamp(),
        'isInChatPage': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error setting active chat: $e");
    }
  }

  Future<void> _clearActiveChat(String userId) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final snap = await userRef.get();
      final data = snap.data() ?? {};
      if (data['activeChatWith'] == widget.receiverId) {
        await userRef.set({
          'activeChatWith': FieldValue.delete(),
          'activeChatUpdatedAt': FieldValue.serverTimestamp(),
          'isInChatPage': false,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error clearing active chat: $e");
    }
  }

  Future<void> _notifyReceiverIfNotInChat({
    required String senderId,
    required String preview,
  }) async {
    try {
      final receiverDoc = await _firestore
          .collection('users')
          .doc(widget.receiverId)
          .get();
      final receiverData = receiverDoc.data() ?? {};
      final bool receiverInThisChat =
          receiverData['isInChatPage'] == true &&
          receiverData['activeChatWith'] == senderId;

      if (receiverInThisChat) {
        return;
      }

      await _firestore
          .collection('users')
          .doc(widget.receiverId)
          .collection('notifications')
          .add({
            'type': 'chat_message',
            'title': _currentUserName ?? 'New message',
            'body': preview,
            'fromId': senderId,
            'fromName': _currentUserName ?? 'User',
            'chatPartnerId': senderId,
            'chatPartnerName': _currentUserName ?? 'User',
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Error creating receiver notification: $e");
    }
  }

  Future<void> _notifyReportAnsweredIfNeeded({
    required String senderId,
    required String receiverId,
  }) async {
    final reportId = widget.reportContextId?.trim() ?? '';
    if (reportId.isEmpty) return;

    try {
      final existing = await _firestore
          .collection('users')
          .doc(receiverId)
          .collection('notifications')
          .where('type', isEqualTo: 'report_answered')
          .where('reportId', isEqualTo: reportId)
          .where('fromId', isEqualTo: senderId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) return;

      await _firestore
          .collection('users')
          .doc(receiverId)
          .collection('notifications')
          .add({
            'type': 'report_answered',
            'title': 'עדכון על הדיווח שלך',
            'body': 'ענינו על הדיווח שלך. לחץ כדי לראות את הפרטים.',
            'reportId': reportId,
            'fromId': senderId,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Error creating report_answered notification: $e");
    }
  }

  String _getChatRoomId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return ids.join('_');
  }

  void _sendMessage({
    String? text,
    String type = 'text',
    String? url,
    String? fileName,
    int? durationSeconds,
  }) async {
    if (type == 'text' && (text == null || text.trim().isEmpty)) return;

    final String currentUserId = _auth.currentUser!.uid;
    final String chatRoomId = _getChatRoomId(currentUserId, widget.receiverId);

    final messageData = {
      'senderId': currentUserId,
      'receiverId': widget.receiverId,
      'message': text ?? '',
      'type': type,
      'url': url,
      'fileName': fileName,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .add(messageData);

      String lastMsgDisplay = "";
      switch (type) {
        case 'image':
          lastMsgDisplay = "📷 Photo";
          break;
        case 'video':
          lastMsgDisplay = "🎥 Video";
          break;
        case 'file':
          lastMsgDisplay = "📄 File: $fileName";
          break;
        case 'audio':
          lastMsgDisplay = "🎤 Voice message";
          break;
        default:
          lastMsgDisplay = text ?? "";
      }

      await _firestore.collection('chat_rooms').doc(chatRoomId).set({
        'lastMessage': lastMsgDisplay,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'users': [currentUserId, widget.receiverId],
        'user_names': {
          currentUserId: _currentUserName ?? "User",
          widget.receiverId: widget.receiverName,
        },
      }, SetOptions(merge: true));

      await _firestore.collection('chat_rooms').doc(chatRoomId).update({
        'unreadCount.${widget.receiverId}': FieldValue.increment(1),
      });

      await _notifyReceiverIfNotInChat(
        senderId: currentUserId,
        preview: lastMsgDisplay,
      );
      await _notifyReportAnsweredIfNeeded(
        senderId: currentUserId,
        receiverId: widget.receiverId,
      );

      _messageController.clear();
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint("Error sending message: $e");
    }
  }

  void _openReceiverProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Profile(userId: widget.receiverId)),
    );
  }

  Widget _buildChatHeaderTitle(bool isRtl) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(widget.receiverId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final displayName = (data['name'] ?? widget.receiverName).toString();
        final imageUrl = (data['profileImageUrl'] ?? '').toString();

        return InkWell(
          onTap: _openReceiverProfile,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFE2E8F0),
                  backgroundImage: imageUrl.isNotEmpty
                      ? CachedNetworkImageProvider(imageUrl)
                      : null,
                  child: imageUrl.isEmpty
                      ? const Icon(
                          Icons.person,
                          size: 18,
                          color: Color(0xFF64748B),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isRtl
                      ? Icons.arrow_back_ios_new_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he' ||
        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: _buildChatHeaderTitle(isRtl),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1976D2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_canCreateInvoices)
            IconButton(
              tooltip: _t(
                en: "Create Invoice",
                he: "הפק חשבונית",
                ar: "إنشاء فاتورة",
                am: "ደረሰኝ ፍጠር",
                ru: "Создать счет",
              ),
              icon: const Icon(Icons.receipt_long_rounded, size: 22),
              onPressed: () async {
                final receiverDoc = await _getUserDoc(widget.receiverId);
                String? phone;
                String? address;
                if (receiverDoc != null && receiverDoc.exists) {
                  final data = receiverDoc.data() as Map<String, dynamic>;
                  phone = data['phone'];
                  address = data['address'] ?? data['town'];
                }

                if (!mounted) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InvoiceBuilderPage(
                      workerName: _currentUserName ?? "Worker",
                      workerPhone: _currentUserPhone,
                      workerEmail: _currentUserEmail,
                      receiverId: widget.receiverId,
                      receiverName: widget.receiverName,
                      receiverPhone: phone,
                      receiverAddress: address,
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.call_rounded, size: 22),
            onPressed: () async {
              final userDoc = await _getUserDoc(widget.receiverId);
              if (userDoc != null && userDoc.exists) {
                final data = userDoc.data() as Map<String, dynamic>;
                final phone = data['phone'];
                if (phone != null) {
                  final Uri url = Uri.parse("tel:$phone");
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messageStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      _t(
                        en: "No messages yet",
                        he: "אין הודעות עדיין",
                        ar: "لا توجد رسائل بعد",
                        am: "እስካሁን መልዕክቶች የሉም",
                        ru: "Пока нет сообщений",
                      ),
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                final pendingUploads = _pendingMediaUploads
                    .where((upload) => upload.receiverId == widget.receiverId)
                    .toList();
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: pendingUploads.length + messages.length,
                  itemBuilder: (context, index) {
                    if (index < pendingUploads.length) {
                      return _buildPendingUploadBubble(pendingUploads[index]);
                    }
                    final message =
                        messages[index - pendingUploads.length].data()
                            as Map<String, dynamic>;
                    final isMe = message['senderId'] == _auth.currentUser!.uid;
                    return _buildMessageBubble(
                      message,
                      isMe,
                      messages[index - pendingUploads.length].id,
                    );
                  },
                );
              },
            ),
          ),
          if (_isSelectionMode)
            _buildSelectionActionBar()
          else
            _buildInputArea(isRtl),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isMe,
    String messageId,
  ) {
    final bool isSelected = _selectedMessageIds.contains(messageId);
    final String type = _resolveMessageType(message);
    final String url = _resolveMessageUrl(message);
    final String? fileName = message['fileName']?.toString();
    final timestamp = message['timestamp'] as Timestamp?;
    final timeStr = timestamp != null
        ? intl.DateFormat('HH:mm').format(timestamp.toDate())
        : "";

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          _selectedMessageIds.add(messageId);
        });
      },
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedMessageIds.remove(messageId);
              if (_selectedMessageIds.isEmpty) _isSelectionMode = false;
            } else {
              _selectedMessageIds.add(messageId);
            }
          });
        } else if (type == 'file') {
          _openFile(url, fileName);
        } else if (type == 'image') {
          _openImageFullscreen(url, fileName: fileName);
        } else if (type == 'video') {
          _openVideoFullscreen(url, fileName: fileName);
        } else if (type == 'report_reference') {
          _openReportFromMessage(message);
        } else if (type == 'report_resolved') {
          _openReportFromMessage(message);
        } else if (type == 'request_link') {
          _openRequestFromMessage(message);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.2)
                : (isMe ? const Color(0xFF1976D2) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (type == 'text')
                Text(
                  _resolveMessageText(message),
                  style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                )
              else if (type == 'report_reference')
                _buildReportReferenceBubble(message, isMe)
              else if (type == 'report_resolved')
                _buildReportResolvedBubble(message, isMe)
              else if (type == 'request_link')
                _buildRequestLinkBubble(message, isMe)
              else if (type == 'image')
                _buildImageAttachment(url, fileName)
              else if (type == 'video')
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedVideoPlayer(
                    url: url,
                    play: false, // Don't autoplay in chat list
                  ),
                )
              else if (type == 'file')
                _buildFileAttachment(url, fileName, isMe)
              else if (type == 'audio')
                _buildAudioPlayer(
                  url,
                  isMe: isMe,
                  fileName: fileName,
                  durationSeconds: (message['durationSeconds'] as num?)
                      ?.toInt(),
                ),
              const SizedBox(height: 4),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingUploadBubble(_PendingMediaUpload upload) {
    final bool isImage = upload.type == 'image';
    final bool isVideo = upload.type == 'video';
    final bool isFailed = upload.isFailed;
    final progress = upload.progress.clamp(0.0, 1.0);
    final statusText = isFailed
        ? 'Upload failed'
        : progress >= 1
        ? 'Finishing...'
        : 'Uploading ${(progress * 100).round()}%';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Color(0xFF1976D2),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.zero,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.file(
                      File(upload.localPath),
                      height: 190,
                      width: 220,
                      fit: BoxFit.cover,
                    ),
                    _buildUploadOverlay(
                      progress: progress,
                      isFailed: isFailed,
                      onRetry: () => _retryPendingUpload(upload),
                    ),
                  ],
                ),
              )
            else if (isVideo)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 190,
                      width: 220,
                      color: Colors.black,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            color: Colors.white70,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            upload.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildUploadOverlay(
                      progress: progress,
                      isFailed: isFailed,
                      onRetry: () => _retryPendingUpload(upload),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isFailed
                      ? Icons.error_outline_rounded
                      : Icons.schedule_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOverlay({
    required double progress,
    required bool isFailed,
    required VoidCallback onRetry,
  }) {
    return Positioned.fill(
      child: Container(
        color: Colors.black45,
        child: Center(
          child: isFailed
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _resolveMessageType(Map<String, dynamic> message) {
    final rawType = (message['type'] ?? '').toString().trim();
    if (rawType.isNotEmpty) return rawType;

    final fileUrl = (message['fileUrl'] ?? '').toString().trim();
    if (fileUrl.isNotEmpty) return 'file';

    return 'text';
  }

  String _resolveMessageUrl(Map<String, dynamic> message) {
    final primary = (message['url'] ?? '').toString().trim();
    if (primary.isNotEmpty) return primary;
    return (message['fileUrl'] ?? '').toString().trim();
  }

  String _resolveMessageText(Map<String, dynamic> message) {
    final primary = (message['message'] ?? '').toString();
    if (primary.isNotEmpty) return primary;
    return (message['text'] ?? '').toString();
  }

  Future<void> _openReportFromMessage(Map<String, dynamic> message) async {
    final reportId = (message['reportId'] ?? '').toString().trim();
    if (reportId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Report reference is missing an ID.',
              he: 'להפניה לדיווח חסר מזהה.',
              ar: 'مرجع البلاغ يفتقد إلى معرّف.',
              am: 'የሪፖርት ማጣቀሻ መለያ የለውም።',
              ru: 'В ссылке на жалобу отсутствует ID.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatReportDetailsPage(reportId: reportId),
      ),
    );
  }

  Future<void> _openRequestFromMessage(Map<String, dynamic> message) async {
    final requestId = (message['requestId'] ?? '').toString().trim();
    if (requestId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Request reference is missing an ID.',
              he: 'להפניית הבקשה חסר מזהה.',
              ar: 'مرجع الطلب يفتقد إلى معرّف.',
              am: 'የጥያቄ ማጣቀሻ መለያ የለውም።',
              ru: 'В ссылке на запрос отсутствует ID.',
            ),
          ),
        ),
      );
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final requestOwnerId = (message['requestOwnerId'] ?? '').toString().trim();
    final isOwner =
        requestOwnerId.isNotEmpty && requestOwnerId == currentUser.uid;

    if (isOwner) {
      final requestDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('requests')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'Request details were not found.',
                he: 'פרטי הבקשה לא נמצאו.',
                ar: 'لم يتم العثور على تفاصيل الطلب.',
                am: 'የጥያቄው ዝርዝሮች አልተገኙም።',
                ru: 'Детали запроса не найдены.',
              ),
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MyRequestDetailsPage(
            requestRef: requestDoc.reference,
            initialData: requestDoc.data() ?? const <String, dynamic>{},
          ),
        ),
      );
      return;
    }

    final workerNotificationId = (message['workerNotificationId'] ?? '')
        .toString()
        .trim();
    DocumentSnapshot<Map<String, dynamic>>? notificationDoc;

    if (workerNotificationId.isNotEmpty) {
      final direct = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .doc(workerNotificationId)
          .get();
      if (direct.exists) {
        notificationDoc = direct;
      }
    }

    if (notificationDoc == null) {
      final query = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .where('requestId', isEqualTo: requestId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        notificationDoc = query.docs.first;
      }
    }

    if (notificationDoc == null || !notificationDoc.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Request details were not found.',
              he: 'פרטי הבקשה לא נמצאו.',
              ar: 'لم يتم العثور على تفاصيل الطلب.',
              am: 'የጥያቄው ዝርዝሮች አልተገኙም።',
              ru: 'Детали запроса не найдены.',
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailsPage(
          notificationId: notificationDoc!.id,
          data: notificationDoc.data() ?? const <String, dynamic>{},
        ),
      ),
    );
  }

  Widget _buildRequestLinkBubble(Map<String, dynamic> message, bool isMe) {
    final requestId = (message['requestId'] ?? '').toString().trim();
    final text = _resolveMessageText(message);

    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? Colors.white12 : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.white24 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: isMe ? Colors.white : const Color(0xFF1976D2),
              ),
              const SizedBox(width: 6),
              Text(
                _t(
                  en: 'Request Link',
                  he: 'קישור לבקשה',
                  ar: 'رابط الطلب',
                  am: 'የጥያቄ አገናኝ',
                  ru: 'Ссылка на запрос',
                ),
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ],
          if (requestId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_t(en: 'Request ID', he: 'מזהה בקשה', ar: 'معرّف الطلب', am: 'የጥያቄ መለያ', ru: 'ID запроса')}: $requestId',
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _openRequestFromMessage(message),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              _t(
                en: 'Open Request',
                he: 'פתח בקשה',
                ar: 'افتح الطلب',
                am: 'ጥያቄውን ክፈት',
                ru: 'Открыть запрос',
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: isMe ? Colors.white : const Color(0xFF1976D2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportReferenceBubble(Map<String, dynamic> message, bool isMe) {
    final reportId = (message['reportId'] ?? '').toString().trim();
    final text = _resolveMessageText(message);

    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? Colors.white12 : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.white24 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_outlined,
                size: 18,
                color: isMe ? Colors.white : const Color(0xFF1976D2),
              ),
              const SizedBox(width: 6),
              Text(
                _t(
                  en: 'Report Update',
                  he: 'עדכון דיווח',
                  ar: 'تحديث البلاغ',
                  am: 'የሪፖርት ዝማኔ',
                  ru: 'Обновление жалобы',
                ),
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ],
          if (reportId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_t(en: 'Report ID', he: 'מזהה דיווח', ar: 'معرّف البلاغ', am: 'የሪፖርት መለያ', ru: 'ID жалобы')}: $reportId',
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _openReportFromMessage(message),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              _t(
                en: 'View Report',
                he: 'צפה בדיווח',
                ar: 'عرض البلاغ',
                am: 'ሪፖርት አሳይ',
                ru: 'Открыть жалобу',
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: isMe ? Colors.white : const Color(0xFF1976D2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportResolvedBubble(Map<String, dynamic> message, bool isMe) {
    final reportId = (message['reportId'] ?? '').toString().trim();
    final text = _resolveMessageText(message);
    final content = text.isNotEmpty
        ? text
        : _t(
            en: 'Your report has been handled.',
            he: 'הדיווח שלך טופל.',
            ar: 'تمت معالجة بلاغك.',
            am: 'ሪፖርትዎ ተስተናግዷል።',
            ru: 'Ваша жалоба обработана.',
          );

    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe ? Colors.white12 : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? Colors.white24 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: isMe ? Colors.white : Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                _t(
                  en: 'Report handled',
                  he: 'הדיווח טופל',
                  ar: 'تمت معالجة البلاغ',
                  am: 'ሪፖርቱ ተስተናግዷል',
                  ru: 'Жалоба обработана',
                ),
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(color: isMe ? Colors.white : Colors.black87),
          ),
          if (reportId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_t(en: 'Report ID', he: 'מזהה דיווח', ar: 'معرّف البلاغ', am: 'የሪፖርት መለያ', ru: 'ID жалобы')}: $reportId',
              style: TextStyle(
                fontSize: 12,
                color: isMe ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _openReportFromMessage(message),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                _t(
                  en: 'View Report',
                  he: 'צפה בדיווח',
                  ar: 'عرض البلاغ',
                  am: 'ሪፖርት አሳይ',
                  ru: 'Открыть жалобу',
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: isMe ? Colors.white : const Color(0xFF1976D2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageAttachment(String url, String? fileName) {
    return FutureBuilder<String?>(
      future: _resolveLocalAttachmentCached(
        url: url,
        type: 'image',
        fileName: fileName,
        autoDownload: true,
      ),
      builder: (context, snapshot) {
        final localPath = snapshot.data;
        final isDownloading = _downloadingUrls.contains(url);
        final progress = _downloadProgress[url] ?? 0;
        final hasError = _failedDownloads.contains(url);

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (localPath != null)
                Image.file(
                  File(localPath),
                  height: 190,
                  width: 220,
                  fit: BoxFit.cover,
                )
              else
                CachedNetworkImage(
                  imageUrl: url,
                  width: 220,
                  height: 190,
                  fit: BoxFit.cover,
                  placeholder: (context, _) => const SizedBox(
                    height: 190,
                    width: 220,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, _, __) => const SizedBox(
                    height: 190,
                    width: 220,
                    child: Icon(Icons.error),
                  ),
                ),
              if (isDownloading)
                Container(
                  color: Colors.black38,
                  height: 190,
                  width: 220,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (hasError)
                Positioned.fill(
                  child: Container(
                    color: Colors.black38,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => _retryAttachmentDownload(
                          url: url,
                          type: 'image',
                          fileName: fileName,
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

  Future<void> _openImageFullscreen(String url, {String? fileName}) async {
    if (url.isEmpty) return;

    final localPath = await _resolveLocalAttachmentCached(
      url: url,
      type: 'image',
      fileName: fileName,
      autoDownload: true,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ImageFullscreenViewer(imageUrl: url, localPath: localPath),
      ),
    );
  }

  Future<void> _openVideoFullscreen(String url, {String? fileName}) async {
    if (url.isEmpty) return;

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _VideoFullscreenViewer(videoUrl: url, fileName: fileName),
      ),
    );
  }

  Widget _buildAudioPlayer(
    String url, {
    required bool isMe,
    String? fileName,
    int? durationSeconds,
  }) {
    return FutureBuilder<String?>(
      future: _resolveLocalAttachmentCached(
        url: url,
        type: 'audio',
        fileName: fileName,
        autoDownload: true,
      ),
      builder: (context, snapshot) {
        final localPath = snapshot.data;
        final isDownloading = _downloadingUrls.contains(url);
        final isActive = _activeAudioUrl == url;
        final isPlaying =
            isActive && _audioPlayerState == ap.PlayerState.playing;
        final position = isActive && _audioPlayerState != ap.PlayerState.stopped
            ? _activeAudioPosition
            : Duration.zero;
        final duration = isActive && _activeAudioDuration > Duration.zero
            ? _activeAudioDuration
            : Duration(seconds: durationSeconds ?? 0);
        final durationText = _formatAudioSeconds(duration);
        final positionText = _formatAudioSeconds(position);
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return Container(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isMe ? Colors.white12 : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe ? Colors.white24 : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Material(
                color: isMe ? Colors.white : const Color(0xFF1976D2),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isDownloading
                      ? null
                      : () => _toggleAudioPlayback(
                          url: url,
                          localPath: localPath,
                        ),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: isDownloading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: _downloadProgress[url],
                                color: isMe
                                    ? const Color(0xFF1976D2)
                                    : Colors.white,
                              ),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 24,
                              color: isMe
                                  ? const Color(0xFF1976D2)
                                  : Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.white12
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            durationText,
                            style: TextStyle(
                              color: isMe
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          isDownloading
                              ? "Downloading..."
                              : isPlaying
                              ? "Pause"
                              : "Play",
                          style: TextStyle(
                            fontSize: 11,
                            color: isMe ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          size: 16,
                          color: isMe ? Colors.white70 : Colors.black54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Voice Message",
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: isDownloading
                            ? _downloadProgress[url]
                            : progress,
                        minHeight: 4,
                        color: isMe ? Colors.white : const Color(0xFF1976D2),
                        backgroundColor: isMe
                            ? Colors.white24
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isDownloading
                          ? "Downloading..."
                          : "$positionText/$durationText",
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe ? Colors.white70 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileAttachment(String url, String? fileName, bool isMe) {
    return FutureBuilder<String?>(
      future: _resolveLocalAttachmentCached(
        url: url,
        type: 'file',
        fileName: fileName,
        autoDownload: true,
      ),
      builder: (context, snapshot) {
        final localPath = snapshot.data;
        final isDownloading = _downloadingUrls.contains(url);
        final hasError = _failedDownloads.contains(url);
        final progress = _downloadProgress[url] ?? 0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              color: isMe ? Colors.white70 : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName ??
                        _t(
                          en: "File",
                          he: "קובץ",
                          ar: "ملف",
                          am: "ፋይል",
                          ru: "Файл",
                        ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (isDownloading)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 3,
                        color: isMe ? Colors.white : const Color(0xFF1976D2),
                        backgroundColor: isMe
                            ? Colors.white24
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                ],
              ),
            ),
            if (hasError)
              IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  color: isMe ? Colors.white : const Color(0xFF1976D2),
                ),
                onPressed: () => _retryAttachmentDownload(
                  url: url,
                  type: 'file',
                  fileName: fileName,
                ),
              )
            else
              Icon(
                localPath != null
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
                size: 18,
                color: isMe ? Colors.white70 : Colors.grey,
              ),
          ],
        );
      },
    );
  }

  Widget _buildInputArea(bool isRtl) {
    final recordingLabel = isRtl
        ? "מקליט הודעה קולית..."
        : "Recording voice...";
    final recordingDuration = Duration(seconds: _recordingSeconds);
    final timerText =
        '${recordingDuration.inMinutes.toString().padLeft(2, '0')}:${(recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: Color(0xFF1976D2),
              ),
              onPressed: _showAttachmentOptions,
            ),
            Expanded(
              child: _isRecording
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mic,
                            color: Color(0xFFD32F2F),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$recordingLabel  $timerText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB71C1C),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: isRtl
                              ? "כתוב הודעה..."
                              : "Type a message...",
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (_isRecording) ...[
              CircleAvatar(
                backgroundColor: const Color(0xFFE57373),
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => _stopRecording(send: false),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF2E7D32),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: () => _stopRecording(send: true),
                ),
              ),
            ] else
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final hasInput = value.text.isNotEmpty;
                  return CircleAvatar(
                    backgroundColor: const Color(0xFF1976D2),
                    child: IconButton(
                      icon: Icon(
                        hasInput ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        if (hasInput) {
                          _sendMessage(text: value.text);
                        } else {
                          _startRecording();
                        }
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionActionBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _isSelectionMode = false;
              _selectedMessageIds.clear();
            }),
          ),
          Text("${_selectedMessageIds.length} selected"),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: _copyMessages,
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                onPressed: _deleteMessages,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAttachmentOption(
                Icons.image_rounded,
                "Image",
                Colors.purple,
                () => _pickMedia(ImageSource.gallery, 'image'),
              ),
              _buildAttachmentOption(
                Icons.videocam_rounded,
                "Video",
                Colors.orange,
                () => _pickMedia(ImageSource.gallery, 'video'),
              ),
              _buildAttachmentOption(
                Icons.photo_camera_back_rounded,
                "Camera Photo",
                Colors.green,
                () => _pickMedia(ImageSource.camera, 'image'),
              ),
              _buildAttachmentOption(
                Icons.video_camera_back_rounded,
                "Camera Video",
                Colors.redAccent,
                () => _pickMedia(ImageSource.camera, 'video'),
              ),
              _buildAttachmentOption(
                Icons.insert_drive_file_rounded,
                "File",
                Colors.blue,
                _pickFile,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    final picker = ImagePicker();
    final pickedFile = type == 'image'
        ? await picker.pickImage(source: source)
        : await picker.pickVideo(source: source);

    if (pickedFile != null) {
      _uploadAndSend(File(pickedFile.path), type, pickedFile.name);
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      _uploadAndSend(
        File(result.files.single.path!),
        'file',
        result.files.single.name,
      );
    }
  }

  Future<void> _uploadAndSend(
    File file,
    String type,
    String fileName, {
    int? durationSeconds,
  }) async {
    final shouldTrackInChat = type == 'image' || type == 'video';
    final pendingId = DateTime.now().microsecondsSinceEpoch.toString();

    if (shouldTrackInChat && mounted) {
      setState(() {
        _pendingMediaUploads.insert(
          0,
          _PendingMediaUpload(
            id: pendingId,
            receiverId: widget.receiverId,
            type: type,
            fileName: fileName,
            localPath: file.path,
            progress: 0,
          ),
        );
      });
    }

    try {
      final ref = _storage
          .ref()
          .child('chats')
          .child(DateTime.now().millisecondsSinceEpoch.toString());
      final uploadTask = ref.putFile(file);

      if (shouldTrackInChat) {
        uploadTask.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          final progress = total > 0 ? snapshot.bytesTransferred / total : 0.0;
          if (!mounted) return;
          setState(() {
            final index = _pendingMediaUploads.indexWhere(
              (upload) => upload.id == pendingId,
            );
            if (index == -1) return;
            _pendingMediaUploads[index] = _pendingMediaUploads[index].copyWith(
              progress: progress,
              isFailed: false,
            );
          });
        });
      }

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      // Keep a local copy so sent attachments are instantly available like chat apps.
      await _cacheSentFileLocally(
        remoteUrl: url,
        sourceFile: file,
        type: type,
        fileName: fileName,
      );

      _sendMessage(
        type: type,
        url: url,
        fileName: fileName,
        durationSeconds: durationSeconds,
      );
      if (shouldTrackInChat && mounted) {
        setState(() {
          _pendingMediaUploads.removeWhere((upload) => upload.id == pendingId);
        });
      }
    } catch (e) {
      if (shouldTrackInChat && mounted) {
        setState(() {
          final index = _pendingMediaUploads.indexWhere(
            (upload) => upload.id == pendingId,
          );
          if (index != -1) {
            _pendingMediaUploads[index] = _pendingMediaUploads[index].copyWith(
              isFailed: true,
            );
          }
        });
      }
      debugPrint("Upload error: $e");
    }
  }

  Future<void> _retryPendingUpload(_PendingMediaUpload upload) async {
    final file = File(upload.localPath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original file is no longer available.')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        final index = _pendingMediaUploads.indexWhere(
          (item) => item.id == upload.id,
        );
        if (index != -1) {
          _pendingMediaUploads.removeAt(index);
        }
      });
    }

    await _uploadAndSend(file, upload.type, upload.fileName);
  }

  Future<void> _cacheSentFileLocally({
    required String remoteUrl,
    required File sourceFile,
    required String type,
    String? fileName,
  }) async {
    try {
      final localPath = await _buildLocalAttachmentPath(
        url: remoteUrl,
        type: type,
        fileName: fileName,
      );
      final targetFile = File(localPath);
      if (!await targetFile.exists()) {
        await sourceFile.copy(localPath);
      }
      if (mounted) {
        setState(() {
          _localMediaPaths[remoteUrl] = localPath;
          _failedDownloads.remove(remoteUrl);
        });
      }
    } catch (e) {
      debugPrint('Local cache save error: $e');
    }
  }

  Future<String?> _resolveLocalAttachmentCached({
    required String url,
    required String type,
    String? fileName,
    bool autoDownload = false,
  }) {
    if (url.isEmpty) return Future.value(null);
    return _localResolveFutures.putIfAbsent(
      url,
      () => _resolveLocalAttachment(
        url: url,
        type: type,
        fileName: fileName,
        autoDownload: autoDownload,
      ),
    );
  }

  Future<String?> _resolveLocalAttachment({
    required String url,
    required String type,
    String? fileName,
    bool autoDownload = false,
  }) async {
    final cachedPath = _localMediaPaths[url];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }

    final localPath = await _buildLocalAttachmentPath(
      url: url,
      type: type,
      fileName: fileName,
    );
    final localFile = File(localPath);
    if (await localFile.exists()) {
      _localMediaPaths[url] = localPath;
      return localPath;
    }

    if (!autoDownload) return null;
    return _downloadAttachment(url, localPath);
  }

  Future<String?> _downloadAttachment(String url, String localPath) async {
    if (_downloadingUrls.contains(url)) return null;

    _downloadingUrls.add(url);
    _failedDownloads.remove(url);
    _downloadProgress[url] = 0;
    if (mounted) setState(() {});

    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final file = File(localPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _downloadProgress[url] = received / total;
          if (mounted) setState(() {});
        }
      }
      await sink.flush();
      await sink.close();

      _localMediaPaths[url] = localPath;
      _downloadProgress.remove(url);
      _downloadingUrls.remove(url);
      _failedDownloads.remove(url);
      if (mounted) setState(() {});
      return localPath;
    } catch (e) {
      _downloadProgress.remove(url);
      _downloadingUrls.remove(url);
      _failedDownloads.add(url);
      if (mounted) setState(() {});
      debugPrint('Attachment download error: $e');
      return null;
    }
  }

  Future<void> _retryAttachmentDownload({
    required String url,
    required String type,
    String? fileName,
  }) async {
    _failedDownloads.remove(url);
    _localResolveFutures.remove(url);
    if (mounted) setState(() {});
    await _resolveLocalAttachmentCached(
      url: url,
      type: type,
      fileName: fileName,
      autoDownload: true,
    );
  }

  Future<String> _buildLocalAttachmentPath({
    required String url,
    required String type,
    String? fileName,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/chat_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = _attachmentExtension(type: type, url: url, fileName: fileName);
    final hash = _stableHash(url);
    return '${dir.path}/$hash$ext';
  }

  String _stableHash(String input) {
    int hash = 2166136261;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  String _attachmentExtension({
    required String type,
    required String url,
    String? fileName,
  }) {
    String candidate = fileName ?? '';
    if (candidate.contains('.')) {
      final dot = candidate.lastIndexOf('.');
      if (dot != -1 && dot < candidate.length - 1) {
        return candidate.substring(dot);
      }
    }

    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    if (path.contains('.')) {
      final dot = path.lastIndexOf('.');
      if (dot != -1 && dot < path.length - 1) {
        return path.substring(dot);
      }
    }

    switch (type) {
      case 'image':
        return '.jpg';
      case 'video':
        return '.mp4';
      case 'audio':
        return '.m4a';
      default:
        return '.bin';
    }
  }

  Future<void> _toggleAudioPlayback({
    required String url,
    required String? localPath,
  }) async {
    try {
      final reachedEnd =
          _activeAudioDuration > Duration.zero &&
          _activeAudioPosition >=
              _activeAudioDuration - const Duration(milliseconds: 250);

      if (_activeAudioUrl == url &&
          _audioPlayerState == ap.PlayerState.playing) {
        if (mounted) {
          setState(() => _audioPlayerState = ap.PlayerState.paused);
        }
        await _audioPlayer.pause();
        return;
      }

      if (_activeAudioUrl == url &&
          _audioPlayerState == ap.PlayerState.paused &&
          !reachedEnd) {
        if (mounted) {
          setState(() => _audioPlayerState = ap.PlayerState.playing);
        }
        await _audioPlayer.resume();
        return;
      }

      await _audioPlayer.stop();
      _activeAudioUrl = url;
      _activeAudioPosition = Duration.zero;
      if (mounted) {
        setState(() => _audioPlayerState = ap.PlayerState.playing);
      }

      if (localPath != null) {
        await _audioPlayer.play(ap.DeviceFileSource(localPath));
        return;
      }

      if (url.isNotEmpty) {
        await _audioPlayer.play(ap.UrlSource(url));
      }
    } catch (e) {
      debugPrint("Audio playback error: $e");
    }
  }

  String _formatAudioSeconds(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return '0s';
    return '${seconds}s';
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<LanguageProvider>(
                      context,
                      listen: false,
                    ).locale.languageCode ==
                    'he'
                ? 'נדרשת הרשאת מיקרופון כדי להקליט הודעה קולית.'
                : 'Microphone permission is required to record voice messages.',
          ),
        ),
      );
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordingTimer?.cancel();
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _recordingSeconds++;
      });
    });

    if (mounted) {
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;

    final recordedSeconds = _recordingSeconds;
    final path = await _audioRecorder.stop();
    _recordingTimer?.cancel();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingSeconds = 0;
      });
    }

    if (path == null || !send) {
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      _uploadAndSend(
        file,
        'audio',
        'Voice Message',
        durationSeconds: recordedSeconds,
      );
    }
  }

  void _openFile(String url, String? fileName) async {
    if (url.isEmpty) return;
    try {
      final localPath = await _resolveLocalAttachmentCached(
        url: url,
        type: 'file',
        fileName: fileName,
        autoDownload: true,
      );
      if (localPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'Failed to download file.',
                he: 'הורדת הקובץ נכשלה.',
                ar: 'فشل تنزيل الملف.',
                am: 'ፋይሉን ማውረድ አልተሳካም።',
                ru: 'Не удалось скачать файл.',
              ),
            ),
          ),
        );
        return;
      }
      await OpenFilex.open(localPath);
    } catch (e) {
      debugPrint("Open file error: $e");
    }
  }

  void _copyMessages() {
    setState(() => _isSelectionMode = false);
  }

  void _deleteMessages() async {
    final chatRoomId = _getChatRoomId(
      _auth.currentUser!.uid,
      widget.receiverId,
    );
    for (var id in _selectedMessageIds) {
      await _firestore
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .doc(id)
          .delete();
    }
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }
}

class ChatReportDetailsPage extends StatelessWidget {
  final String reportId;

  const ChatReportDetailsPage({super.key, required this.reportId});

  String _t(
    BuildContext context, {
    required String en,
    String? he,
    String? ar,
    String? am,
    String? ru,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return he ?? en;
      case 'ar':
        return ar ?? en;
      case 'am':
        return am ?? en;
      case 'ru':
        return ru ?? en;
      default:
        return en;
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    return intl.DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
  }

  Future<String> _userNameFromId(String userId) async {
    if (userId.isEmpty) return '-';
    if (userId == 'app') return 'App';
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final name = (doc.data()?['name'] ?? '').toString().trim();
    return name.isEmpty ? userId : name;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t(
            context,
            en: 'Report Details',
            he: 'פרטי דיווח',
            ar: 'تفاصيل البلاغ',
            am: 'የሪፖርት ዝርዝሮች',
            ru: 'Детали жалобы',
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                _t(
                  context,
                  en: 'Could not load this report.',
                  he: 'לא ניתן לטעון את הדיווח.',
                  ar: 'تعذّر تحميل هذا البلاغ.',
                  am: 'ይህን ሪፖርት መጫን አልተቻለም።',
                  ru: 'Не удалось загрузить эту жалобу.',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return Center(
              child: Text(
                _t(
                  context,
                  en: 'This report no longer exists.',
                  he: 'הדיווח הזה כבר לא קיים.',
                  ar: 'هذا البلاغ لم يعد موجودًا.',
                  am: 'ይህ ሪፖርት ከእንግዲህ የለም።',
                  ru: 'Эта жалоба больше не существует.',
                ),
              ),
            );
          }

          final data = snapshot.data!.data() ?? <String, dynamic>{};
          final reporterId = (data['reporterId'] ?? '').toString();
          final reportedId = (data['reportedId'] ?? '').toString();
          final resolvedBy = (data['resolvedBy'] ?? '').toString();
          final isAllowed =
              currentUserId != null &&
              (currentUserId == reporterId ||
                  currentUserId == reportedId ||
                  currentUserId == resolvedBy);

          if (!isAllowed) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(
                    context,
                    en: 'You do not have access to this report.',
                    he: 'אין לך גישה לדיווח הזה.',
                    ar: 'ليس لديك صلاحية الوصول لهذا البلاغ.',
                    am: 'ይህን ሪፖርት ለማየት ፍቃድ የለዎትም።',
                    ru: 'У вас нет доступа к этой жалобе.',
                  ),
                ),
              ),
            );
          }

          final subject =
              (data['subject'] ??
                      data['reason'] ??
                      _t(
                        context,
                        en: 'General issue',
                        he: 'בעיה כללית',
                        ar: 'مشكلة عامة',
                        am: 'አጠቃላይ ችግር',
                        ru: 'Общая проблема',
                      ))
                  .toString();
          final reason = (data['reason'] ?? '').toString();
          final details = (data['details'] ?? '').toString();
          final status = (data['status'] ?? 'open').toString();
          final source = (data['source'] ?? '').toString();
          final reportType = (data['reportType'] ?? '').toString();
          final createdAt = data['timestamp'] as Timestamp?;
          final resolvedAt = data['resolvedAt'] as Timestamp?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                '${_t(context, en: 'Status', he: 'סטטוס', ar: 'الحالة', am: 'ሁኔታ', ru: 'Статус')}: $status',
                              ),
                            ),
                            Chip(
                              label: Text(
                                '${_t(context, en: 'Created', he: 'נוצר', ar: 'تم الإنشاء', am: 'የተፈጠረ', ru: 'Создано')}: ${_formatTimestamp(createdAt)}',
                              ),
                            ),
                            if (source.isNotEmpty)
                              Chip(
                                label: Text(
                                  '${_t(context, en: 'Source', he: 'מקור', ar: 'المصدر', am: 'ምንጭ', ru: 'Источник')}: $source',
                                ),
                              ),
                            if (reportType.isNotEmpty)
                              Chip(
                                label: Text(
                                  '${_t(context, en: 'Type', he: 'סוג', ar: 'النوع', am: 'አይነት', ru: 'Тип')}: $reportType',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_t(context, en: 'Report ID', he: 'מזהה דיווח', ar: 'معرّف البلاغ', am: 'የሪፖርት መለያ', ru: 'ID жалобы')}: $reportId',
                        ),
                        const SizedBox(height: 6),
                        FutureBuilder<String>(
                          future: _userNameFromId(reporterId),
                          builder: (context, snapshot) {
                            final reporterName = snapshot.data ?? '-';
                            return Text(
                              '${_t(context, en: 'Reporter', he: 'מדווח', ar: 'المبلّغ', am: 'ሪፖርተር', ru: 'Заявитель')}: $reporterName',
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        FutureBuilder<String>(
                          future: _userNameFromId(reportedId),
                          builder: (context, snapshot) {
                            final reportedName = snapshot.data ?? '-';
                            return Text(
                              '${_t(context, en: 'Reported User', he: 'משתמש מדווח', ar: 'المستخدم المُبلّغ عنه', am: 'የተሪፖርተ ተጠቃሚ', ru: 'Пользователь, на которого пожаловались')}: $reportedName',
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_t(context, en: 'Resolved By', he: 'טופל על ידי', ar: 'تمت المعالجة بواسطة', am: 'የተፈታ በ', ru: 'Решено пользователем')}: ${resolvedBy.isEmpty ? '-' : resolvedBy}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_t(context, en: 'Resolved At', he: 'טופל בתאריך', ar: 'تمت المعالجة في', am: 'የተፈታበት ጊዜ', ru: 'Решено в')}: ${_formatTimestamp(resolvedAt)}',
                        ),
                        if (reason.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${_t(context, en: 'Reason', he: 'סיבה', ar: 'السبب', am: 'ምክንያት', ru: 'Причина')}: $reason',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0.5,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              context,
                              en: 'Details',
                              he: 'פרטים',
                              ar: 'التفاصيل',
                              am: 'ዝርዝሮች',
                              ru: 'Подробности',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(details),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatPageLifecycleObserver extends WidgetsBindingObserver {
  _ChatPageLifecycleObserver({
    required this.onResumed,
    required this.onBackgrounded,
  });

  final VoidCallback onResumed;
  final VoidCallback onBackgrounded;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      onBackgrounded();
    }
  }
}

class _ImageFullscreenViewer extends StatefulWidget {
  final String imageUrl;
  final String? localPath;

  const _ImageFullscreenViewer({required this.imageUrl, this.localPath});

  @override
  State<_ImageFullscreenViewer> createState() => _ImageFullscreenViewerState();
}

class _ImageFullscreenViewerState extends State<_ImageFullscreenViewer> {
  bool _showChrome = true;

  @override
  Widget build(BuildContext context) {
    final hasLocal = widget.localPath != null && widget.localPath!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: ZoomableImageViewer(
              imageUrl: widget.imageUrl,
              localPath: hasLocal ? widget.localPath : null,
              enableSwipeDismiss: true,
              onTap: () => setState(() => _showChrome = !_showChrome),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            top: _showChrome ? 0 : -100,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoFullscreenViewer extends StatelessWidget {
  final String videoUrl;
  final String? fileName;

  const _VideoFullscreenViewer({required this.videoUrl, this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(fileName ?? 'Video'),
      ),
      body: Center(
        child: CachedVideoPlayer(
          url: videoUrl,
          play: true,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _PendingMediaUpload {
  final String id;
  final String receiverId;
  final String type;
  final String fileName;
  final String localPath;
  final double progress;
  final bool isFailed;

  const _PendingMediaUpload({
    required this.id,
    required this.receiverId,
    required this.type,
    required this.fileName,
    required this.localPath,
    required this.progress,
    this.isFailed = false,
  });

  _PendingMediaUpload copyWith({double? progress, bool? isFailed}) {
    return _PendingMediaUpload(
      id: id,
      receiverId: receiverId,
      type: type,
      fileName: fileName,
      localPath: localPath,
      progress: progress ?? this.progress,
      isFailed: isFailed ?? this.isFailed,
    );
  }
}
