import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:untitled1/pages/fullscreen_media_viewer.dart';
import 'package:untitled1/widgets/cached_video_player.dart';

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
  final FocusNode _commentFocusNode = FocusNode();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final PageController _mediaPageController = PageController();

  bool _isLiked = false;
  int _likesCount = 0;
  bool _showHeartAnimation = false;
  bool _isSubmittingComment = false;
  int _currentMediaIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
    _likesCount = widget.project['likesCount'] ?? 0;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _mediaPageController.dispose();
    super.dispose();
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

    if (!mounted) return;
    setState(() {
      _isLiked = likeDoc.exists;
    });
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

      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _showHeartAnimation = false);
        }
      });
    }
  }

  Future<void> _addComment() async {
    if (_currentUser == null || _commentController.text.trim().isEmpty) return;
    if (_isSubmittingComment) return;

    final commentText = _commentController.text.trim();
    _commentController.clear();
    setState(() => _isSubmittingComment = true);

    try {
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
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  bool _isPathVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mp4') ||
        lowerUrl.contains('.mov') ||
        lowerUrl.contains('.avi') ||
        lowerUrl.contains('.mkv');
  }

  DateTime? _projectDate() {
    final raw = widget.project['timestamp'] ?? widget.project['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  String _formatProjectDate(DateTime? date) {
    if (date == null) return 'Recent project';
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _formatCommentDate(dynamic value) {
    if (value is! Timestamp) return '';
    return DateFormat('MMM d').format(value.toDate());
  }

  void _focusCommentField() {
    _commentFocusNode.requestFocus();
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required String value,
    Color color = const Color(0xFF0F172A),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection(List<QueryDocumentSnapshot> comments) {
    if (comments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 10),
            Text(
              'No comments yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Start the conversation about this project.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final comment = comments[index].data() as Map<String, dynamic>;
        final userImage = (comment['userImage'] ?? '').toString();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: userImage.isNotEmpty
                    ? CachedNetworkImageProvider(userImage)
                    : null,
                child: userImage.isEmpty
                    ? const Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comment['userName'] ?? 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        Text(
                          _formatCommentDate(comment['timestamp']),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment['text'] ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF334155),
                        height: 1.45,
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

  @override
  Widget build(BuildContext context) {
    final media =
        ((widget.project['imageUrls'] as List?) ??
                [widget.project['imageUrl'] ?? widget.project['image'] ?? ''])
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList();
    final description = (widget.project['description'] ?? '').toString().trim();
    final projectDate = _projectDate();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: const Color(0xFFF7F9FC),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Project Details',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x220F172A),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white24,
                                backgroundImage:
                                    widget.workerProfileImage.isNotEmpty
                                    ? CachedNetworkImageProvider(
                                        widget.workerProfileImage,
                                      )
                                    : null,
                                child: widget.workerProfileImage.isEmpty
                                    ? const Icon(
                                        Icons.person_rounded,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.workerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatProjectDate(projectDate),
                                      style: const TextStyle(
                                        color: Color(0xFFBFDBFE),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.work_outline_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Portfolio',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (media.isNotEmpty)
                          GestureDetector(
                            onDoubleTap: _toggleLike,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      height: 360,
                                      width: double.infinity,
                                      child: PageView.builder(
                                        controller: _mediaPageController,
                                        itemCount: media.length,
                                        onPageChanged: (index) {
                                          setState(
                                            () => _currentMediaIndex = index,
                                          );
                                        },
                                        itemBuilder: (context, index) {
                                          final url = media[index];
                                          final isVideo = _isPathVideo(url);
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      FullscreenMediaViewer(
                                                        urls: media,
                                                        initialIndex: index,
                                                      ),
                                                ),
                                              );
                                            },
                                            child: Hero(
                                              tag: url,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  isVideo
                                                      ? CachedVideoPlayer(
                                                          url: url,
                                                          play: false,
                                                          fit: BoxFit.cover,
                                                          showControls: false,
                                                          allowFullscreen:
                                                              false,
                                                        )
                                                      : CachedNetworkImage(
                                                          imageUrl: url,
                                                          fit: BoxFit.cover,
                                                          placeholder:
                                                              (
                                                                context,
                                                                imageUrl,
                                                              ) => Container(
                                                                color:
                                                                    const Color(
                                                                      0xFFDBEAFE,
                                                                    ),
                                                                child: const Center(
                                                                  child:
                                                                      CircularProgressIndicator(),
                                                                ),
                                                              ),
                                                          errorWidget:
                                                              (
                                                                context,
                                                                imageUrl,
                                                                error,
                                                              ) => Container(
                                                                color:
                                                                    const Color(
                                                                      0xFFE2E8F0,
                                                                    ),
                                                                child: const Icon(
                                                                  Icons
                                                                      .broken_image_outlined,
                                                                  size: 40,
                                                                  color: Color(
                                                                    0xFF64748B,
                                                                  ),
                                                                ),
                                                              ),
                                                        ),
                                                  const DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: [
                                                          Color(0x14000000),
                                                          Color(0x00000000),
                                                          Color(0x60000000),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (isVideo)
                                                    const Center(
                                                      child: DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Color(
                                                                0x660F172A,
                                                              ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                14,
                                                              ),
                                                          child: Icon(
                                                            Icons
                                                                .play_arrow_rounded,
                                                            size: 36,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      top: 14,
                                      right: 14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0x880F172A),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '${_currentMediaIndex + 1}/${media.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 14,
                                      left: 14,
                                      child: Row(
                                        children: List.generate(media.length, (
                                          index,
                                        ) {
                                          final isActive =
                                              index == _currentMediaIndex;
                                          return AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            margin: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            width: isActive ? 22 : 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? Colors.white
                                                  : Colors.white54,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                    if (_showHeartAnimation)
                                      const Icon(
                                        Icons.favorite_rounded,
                                        color: Colors.white,
                                        size: 110,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildMetricChip(
                        icon: _isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: 'Likes',
                        value: '$_likesCount',
                        color: _isLiked
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF0F172A),
                      ),
                      _buildMetricChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Comments',
                        value: '${widget.project['commentsCount'] ?? 0}',
                        color: const Color(0xFF2563EB),
                      ),
                      _buildMetricChip(
                        icon: Icons.schedule_rounded,
                        label: 'Published',
                        value: _formatProjectDate(projectDate),
                        color: const Color(0xFF0F766E),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_mosaic_rounded,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Project Story',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          description.isEmpty
                              ? 'This project does not have a written description yet.'
                              : description,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.65,
                            color: description.isEmpty
                                ? const Color(0xFF64748B)
                                : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _focusCommentField,
                                icon: const Icon(
                                  Icons.mode_comment_outlined,
                                  size: 18,
                                ),
                                label: const Text('Comment'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF1D4ED8),
                                  side: const BorderSide(
                                    color: Color(0xFFBFDBFE),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _toggleLike,
                                icon: Icon(
                                  _isLiked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _isLiked ? 'Liked' : 'Like project',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isLiked
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('users')
                          .doc(widget.workerId)
                          .collection('projects')
                          .doc(widget.project['id'])
                          .collection('comments')
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final comments = snapshot.data!.docs;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Comments',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${comments.length}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildCommentsSection(comments),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 18,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFE2E8F0),
                    backgroundImage: _currentUser?.photoURL != null
                        ? CachedNetworkImageProvider(_currentUser!.photoURL!)
                        : null,
                    child: _currentUser?.photoURL == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF64748B),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Add a thoughtful comment...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1D4ED8), Color(0xFF0F766E)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IconButton(
                      onPressed: _isSubmittingComment ? null : _addComment,
                      icon: _isSubmittingComment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                            ),
                    ),
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
