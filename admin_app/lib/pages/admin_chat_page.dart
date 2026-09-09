import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hiro_admin/services/chat_write_service.dart';

class AdminChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? reportContextId;

  const AdminChatPage({
    super.key,
    required this.receiverId,
    required this.receiverName,
    this.reportContextId,
  });

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final _controller = TextEditingController();
  final _db = FirebaseFirestore.instance;
  bool _sending = false;
  bool _roomReady = false;
  Object? _roomError;

  String get _senderId => FirebaseAuth.instance.currentUser!.uid;
  String get _roomId {
    final ids = [_senderId, widget.receiverId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  void initState() {
    super.initState();
    ChatWriteService.ensureRoom(
          receiverId: widget.receiverId,
          receiverName: widget.receiverName,
        )
        .then((_) {
          if (mounted) setState(() => _roomReady = true);
        })
        .catchError((Object error) {
          if (mounted) setState(() => _roomError = error);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatWriteService.send(
        receiverId: widget.receiverId,
        type: 'text',
        message: text,
      );
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.receiverName)),
      body: Column(
        children: [
          if (widget.reportContextId != null)
            MaterialBanner(
              content: Text('Report: ${widget.reportContextId}'),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _roomReady
                  ? _db
                        .collection('chat_rooms')
                        .doc(_roomId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .limit(100)
                        .snapshots()
                  : null,
              builder: (context, snapshot) {
                if (_roomError != null) {
                  return Center(child: Text('Chat error: $_roomError'));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Chat error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final data = snapshot.data!.docs[index].data();
                    final mine = data['senderId'] == _senderId;
                    final text = (data['text'] ?? data['message'] ?? '')
                        .toString();
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        color: mine ? const Color(0xFFDBEAFE) : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Text(text),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
