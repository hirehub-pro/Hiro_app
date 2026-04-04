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

import '../widgets/cached_video_player.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  const ChatPage({
    super.key,
    required this.receiverId,
    required this.receiverName,
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
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  final Map<String, String> _localMediaPaths = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingUrls = {};
  final Set<String> _failedDownloads = {};
  final Map<String, Future<String?>> _localResolveFutures = {};
  late Stream<QuerySnapshot> _messageStream;

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

  bool _isWorker = false;
  bool _canCreateInvoices = false;
  String? _currentUserName;
  String? _currentUserPhone;
  String? _currentUserEmail;
  late final Future<SubscriptionAccessState> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = SubscriptionAccessService.getCurrentUserState();
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
    _audioPlayer.dispose();
    super.dispose();
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

    return FutureBuilder<SubscriptionAccessState>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data?.isUnsubscribedWorker == true) {
          return SubscriptionAccessService.buildLockedScaffold(
            title: isRtl ? 'צ׳אט' : 'Chat',
            message: isRtl
                ? 'צ׳אט זמין רק לבעלי מנוי Pro פעיל.'
                : 'Chat is available only with an active Pro subscription.',
          );
        }

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
                  tooltip: isRtl ? "הפק חשבונית" : "Create Invoice",
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
                          isRtl ? "אין הודעות עדיין" : "No messages yet",
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      );
                    }

                    final messages = snapshot.data!.docs;
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message =
                            messages[index].data() as Map<String, dynamic>;
                        final isMe =
                            message['senderId'] == _auth.currentUser!.uid;
                        return _buildMessageBubble(
                          message,
                          isMe,
                          messages[index].id,
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
      },
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
                _buildAudioPlayer(url, isMe: isMe, fileName: fileName),
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

  Widget _buildAudioPlayer(String url, {required bool isMe, String? fileName}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic, color: isMe ? Colors.white : Colors.black54, size: 20),
        const SizedBox(width: 8),
        Text(
          "Voice Message",
          style: TextStyle(color: isMe ? Colors.white : Colors.black87),
        ),
        FutureBuilder<String?>(
          future: _resolveLocalAttachmentCached(
            url: url,
            type: 'audio',
            fileName: fileName,
            autoDownload: true,
          ),
          builder: (context, snapshot) {
            final localPath = snapshot.data;
            final isDownloading = _downloadingUrls.contains(url);
            return IconButton(
              icon: isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _downloadProgress[url],
                        color: isMe ? Colors.white : const Color(0xFF1976D2),
                      ),
                    )
                  : Icon(
                      Icons.play_arrow,
                      color: isMe ? Colors.white : const Color(0xFF1976D2),
                    ),
              onPressed: isDownloading
                  ? null
                  : () async {
                      if (localPath != null) {
                        await _audioPlayer.play(ap.DeviceFileSource(localPath));
                        return;
                      }
                      if (url.isNotEmpty) {
                        await _audioPlayer.play(ap.UrlSource(url));
                      }
                    },
            );
          },
        ),
      ],
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
                    fileName ?? "File",
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
                Icons.insert_drive_file_rounded,
                "File",
                Colors.blue,
                _pickFile,
              ),
              _buildAttachmentOption(
                Icons.camera_alt_rounded,
                "Camera",
                Colors.green,
                () => _pickMedia(ImageSource.camera, 'image'),
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

  Future<void> _uploadAndSend(File file, String type, String fileName) async {
    try {
      final ref = _storage
          .ref()
          .child('chats')
          .child(DateTime.now().millisecondsSinceEpoch.toString());
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();

      // Keep a local copy so sent attachments are instantly available like chat apps.
      await _cacheSentFileLocally(
        remoteUrl: url,
        sourceFile: file,
        type: type,
        fileName: fileName,
      );

      _sendMessage(type: type, url: url, fileName: fileName);
    } catch (e) {
      debugPrint("Upload error: $e");
    }
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
      _uploadAndSend(file, 'audio', 'Voice Message');
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
          const SnackBar(content: Text('Failed to download file.')),
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

class _ImageFullscreenViewer extends StatelessWidget {
  final String imageUrl;
  final String? localPath;

  const _ImageFullscreenViewer({required this.imageUrl, this.localPath});

  @override
  Widget build(BuildContext context) {
    final hasLocal = localPath != null && localPath!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: hasLocal
              ? Image.file(File(localPath!), fit: BoxFit.contain)
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, _, __) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white70,
                    size: 60,
                  ),
                ),
        ),
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
      body: Center(child: CachedVideoPlayer(url: videoUrl, play: true)),
    );
  }
}
