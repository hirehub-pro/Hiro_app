import 'dart:io';
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
  late Stream<QuerySnapshot> _messageStream;

  // Selection Mode State
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

  bool _isWorker = false;
  String? _currentUserName;
  String? _currentUserPhone;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
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
          if (_isWorker)
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
                    final isMe = message['senderId'] == _auth.currentUser!.uid;
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
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isMe,
    String messageId,
  ) {
    final bool isSelected = _selectedMessageIds.contains(messageId);
    final String type = message['type'] ?? 'text';
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
          _openFile(message['url'] ?? "", message['fileName']);
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
                  message['message'] ?? "",
                  style: TextStyle(color: isMe ? Colors.white : Colors.black87),
                )
              else if (type == 'image')
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: message['url'] ?? "",
                    placeholder: (context, url) => const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                )
              else if (type == 'video')
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedVideoPlayer(
                    url: message['url'] ?? "",
                    play: false, // Don't autoplay in chat list
                  ),
                )
              else if (type == 'file')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_rounded,
                      color: isMe ? Colors.white70 : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message['fileName'] ?? "File",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                )
              else if (type == 'audio')
                _buildAudioPlayer(message['url'] ?? ""),
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

  Widget _buildAudioPlayer(String url) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mic, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        const Text("Voice Message", style: TextStyle(color: Colors.white)),
        IconButton(
          icon: const Icon(Icons.play_arrow, color: Colors.white),
          onPressed: () async {
            if (url.isNotEmpty) await _audioPlayer.play(ap.UrlSource(url));
          },
        ),
      ],
    );
  }

  Widget _buildInputArea(bool isRtl) {
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
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: isRtl ? "כתוב הודעה..." : "Type a message...",
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: _startRecording,
              onLongPressUp: _stopRecording,
              child: CircleAvatar(
                backgroundColor: const Color(0xFF1976D2),
                child: IconButton(
                  icon: Icon(
                    _isRecording ? Icons.mic : Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () {
                    if (_messageController.text.trim().isNotEmpty) {
                      _sendMessage(text: _messageController.text);
                    }
                  },
                ),
              ),
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
      _sendMessage(type: type, url: url, fileName: fileName);
    } catch (e) {
      debugPrint("Upload error: $e");
    }
  }

  void _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      final path =
          '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(const RecordConfig(), path: path);
      setState(() => _isRecording = true);
    }
  }

  void _stopRecording() async {
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);
    if (path != null) {
      _uploadAndSend(File(path), 'audio', 'Voice Message');
    }
  }

  void _openFile(String url, String? fileName) async {
    if (url.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(url));
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${fileName ?? "temp"}');
      await file.writeAsBytes(response.bodyBytes);
      await OpenFilex.open(file.path);
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
