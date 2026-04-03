import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:untitled1/widgets/cached_video_player.dart';
import 'package:untitled1/pages/fullscreen_media_viewer.dart';

class PostDetailsPage extends StatefulWidget {
  final String workerId;
  final Map<String, dynamic> project;
  final String workerName;
  final String workerProfileImage;

  const PostDetailsPage({
    super.key,
    required this.workerId,
    required this.project,
    required this.workerName,
    required this.workerProfileImage,
  });

  @override
  State<PostDetailsPage> createState() => _PostDetailsPageState();
}

class _PostDetailsPageState extends State<PostDetailsPage> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _showHeartAnimation = false;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
    _likesCount = widget.project['likesCount'] ?? 0;
  }

  void _checkIfLiked() async {
    if (_currentUser == null) return;
    final likeDoc = await _firestore
        .collection('users')
        .doc(widget.workerId)
        .collection('projects')
        .doc(widget.project['id'])
        .collection('likes')
        .doc(_currentUser.uid)
        .get();

    if (mounted) {
      setState(() {
        _isLiked = likeDoc.exists;
      });
    }
  }

  Future<void> _toggleLike() async {
    if (_currentUser == null) return;

    final projectRef = _firestore
        .collection('users')
        .doc(widget.workerId)
        .collection('projects')
        .doc(widget.project['id']);

    final likeRef = projectRef.collection('likes').doc(_currentUser.uid);

    if (_isLiked) {
      setState(() {
        _isLiked = false;
        _likesCount--;
      });
      await likeRef.delete();
      await projectRef.update({'likesCount': FieldValue.increment(-1)});
    } else {
      setState(() {
        _isLiked = true;
        _likesCount++;
        _showHeartAnimation = true;
      });
      await likeRef.set({'timestamp': FieldValue.serverTimestamp()});
      await projectRef.update({'likesCount': FieldValue.increment(1)});

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => _showHeartAnimation = false);
      });
    }
  }

  Future<void> _addComment() async {
    if (_currentUser == null || _commentController.text.trim().isEmpty) return;

    final commentText = _commentController.text.trim();
    _commentController.clear();

    final userDoc = await _firestore
        .collection('users')
        .doc(_currentUser.uid)
        .get();
    final userName = userDoc.data()?['name'] ?? 'User';
    final userImage = userDoc.data()?['profileImageUrl'] ?? '';

    await _firestore
        .collection('users')
        .doc(widget.workerId)
        .collection('projects')
        .doc(widget.project['id'])
        .collection('comments')
        .add({
          'userId': _currentUser.uid,
          'userName': userName,
          'userImage': userImage,
          'text': commentText,
          'timestamp': FieldValue.serverTimestamp(),
        });

    await _firestore
        .collection('users')
        .doc(widget.workerId)
        .collection('projects')
        .doc(widget.project['id'])
        .update({'commentsCount': FieldValue.increment(1)});
  }

  bool _isPathVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mp4') ||
        lowerUrl.contains('.mov') ||
        lowerUrl.contains('.avi') ||
        lowerUrl.contains('.mkv');
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> media =
        widget.project['imageUrls'] ??
        [widget.project['imageUrl'] ?? widget.project['image'] ?? ""];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Post Details",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Header
                  ListTile(
                    leading: CircleAvatar(
                      backgroundImage: widget.workerProfileImage.isNotEmpty
                          ? CachedNetworkImageProvider(
                              widget.workerProfileImage,
                            )
                          : null,
                      child: widget.workerProfileImage.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(
                      widget.workerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text("Worker"),
                    trailing: const Icon(Icons.more_vert),
                  ),

                  // Media Section
                  GestureDetector(
                    onDoubleTap: _toggleLike,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 400,
                          width: double.infinity,
                          child: PageView.builder(
                            itemCount: media.length,
                            itemBuilder: (context, index) {
                              final url = media[index];
                              final isVideo = _isPathVideo(url);
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullscreenMediaViewer(
                                        urls: media.cast<String>(),
                                        initialIndex: index,
                                      ),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag: url,
                                  child: isVideo
                                      ? CachedVideoPlayer(url: url, play: true)
                                      : CachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                                color: Colors.grey[200],
                                                child: const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          errorWidget: (context, url, error) =>
                                              const Icon(Icons.error),
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showHeartAnimation)
                          const Icon(
                            Icons.favorite,
                            color: Colors.white,
                            size: 100,
                          ),
                      ],
                    ),
                  ),

                  // Actions (Like, Comment, Share)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.black,
                          ),
                          onPressed: _toggleLike,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () {}, // Focus text field
                        ),
                        IconButton(
                          icon: const Icon(Icons.send_outlined),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),

                  // Likes Count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "$_likesCount likes",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Description
                  if (widget.project['description'] != null &&
                      widget.project['description'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black),
                          children: [
                            TextSpan(
                              text: "${widget.workerName} ",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(text: widget.project['description']),
                          ],
                        ),
                      ),
                    ),

                  const Divider(),

                  // Comments List
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(widget.workerId)
                        .collection('projects')
                        .doc(widget.project['id'])
                        .collection('comments')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final comments = snapshot.data!.docs;

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment =
                              comments[index].data() as Map<String, dynamic>;
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundImage:
                                  (comment['userImage'] ?? '').isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      comment['userImage'],
                                    )
                                  : null,
                              child: (comment['userImage'] ?? '').isEmpty
                                  ? const Icon(Icons.person, size: 15)
                                  : null,
                            ),
                            title: Text(
                              comment['userName'] ?? 'User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              comment['text'] ?? '',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              comment['timestamp'] != null
                                  ? DateFormat.yMMMd().format(
                                      (comment['timestamp'] as Timestamp)
                                          .toDate(),
                                    )
                                  : '',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Add Comment TextField
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: _currentUser?.photoURL != null
                      ? CachedNetworkImageProvider(_currentUser!.photoURL!)
                      : null,
                  child: _currentUser?.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: "Add a comment...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _addComment,
                  child: const Text(
                    "Post",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
