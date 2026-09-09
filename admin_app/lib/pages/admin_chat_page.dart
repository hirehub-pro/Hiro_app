import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  String get _senderId => FirebaseAuth.instance.currentUser!.uid;
  String get _roomId {
    final ids = [_senderId, widget.receiverId]..sort();
    return '${ids[0]}_${ids[1]}';
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
      final room = _db.collection('chat_rooms').doc(_roomId);
      // Message rules require the parent room to exist first.
      await room.set({
        'users': [_senderId, widget.receiverId],
      }, SetOptions(merge: true));
      await room.collection('messages').add({
        'senderId': _senderId,
        'receiverId': widget.receiverId,
        'text': text,
        'message': text,
        'type': 'text',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await room.set({
        'lastMessage': text,
        'lastTimestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
              stream: _db
                  .collection('chat_rooms')
                  .doc(_roomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
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
