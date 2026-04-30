part of 'formu.dart';

class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onBlockUser;
  final Map<String, dynamic> localizedStrings;
  final VoidCallback onGuestDialog;

  const PostDetailPage({
    super.key,
    required this.post,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onBlockUser,
    required this.localizedStrings,
    required this.onGuestDialog,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _bidPriceController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _comments = [];
  StreamSubscription? _commentsSubscription;
  final Map<String, Map<String, dynamic>> _workerPreviewCache = {};
  String? _currentUserRole;
  bool _currentUserHasActiveWorkerSubscription = false;
  String? _loadedBidDraftId;
  bool _isSubmittingComment = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
    _listenToComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _bidPriceController.dispose();
    _commentsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      if (!mounted) return;
      setState(() {
        _currentUserRole = userData?['role']?.toString();
        _currentUserHasActiveWorkerSubscription =
            SubscriptionAccessService.hasActiveWorkerSubscriptionFromData(
              userData,
            );
      });
    } catch (_) {}
  }

  Future<void> _ensureWorkerPreview(String uid) async {
    if (uid.isEmpty || _workerPreviewCache.containsKey(uid)) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data() ?? <String, dynamic>{};
      setState(() {
        _workerPreviewCache[uid] = {
          'name': (data['name'] ?? '').toString(),
          'profileImageUrl': (data['profileImageUrl'] ?? '').toString(),
          'avgRating': (data['avgRating'] as num?)?.toDouble() ?? 0.0,
          'reviewCount': (data['reviewCount'] as num?)?.toInt() ?? 0,
        };
      });
    } catch (_) {}
  }

  void _syncExistingBidDraft() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final existingBid = _comments.cast<Map<String, dynamic>?>().firstWhere(
      (comment) =>
          comment != null &&
          comment['authorUid']?.toString() == user.uid &&
          (comment['isBid'] == true || (comment['bidPrice'] != null)),
      orElse: () => null,
    );

    if (existingBid == null) return;
    final bidId = existingBid['id']?.toString();
    if (bidId == null || bidId == _loadedBidDraftId) return;

    _loadedBidDraftId = bidId;
    _bidPriceController.text = existingBid['bidPrice']?.toString() ?? '';
    _commentController.text = existingBid['text']?.toString() ?? '';
  }

  void _listenToComments() {
    _commentsSubscription = _firestore
        .collection('blog_posts')
        .doc(widget.post['id'])
        .collection('blog_comments')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
          List<Map<String, dynamic>> loadedComments = [];
          for (var doc in snapshot.docs) {
            final comment = doc.data();
            comment['id'] = doc.id;
            loadedComments.add(comment);
            final authorUid = comment['authorUid']?.toString() ?? '';
            final isBid =
                comment['isBid'] == true || (comment['bidPrice'] != null);
            if (authorUid.isNotEmpty && isBid) {
              _ensureWorkerPreview(authorUid);
            }
          }
          if (mounted) {
            setState(() => _comments = loadedComments);
            _syncExistingBidDraft();
          }
        });
  }

  Future<void> _addComment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      widget.onGuestDialog();
      return;
    }
    final isJobRequest =
        widget.post['isJobRequest'] == true ||
        _isJobRequestCategoryValue((widget.post['category'] ?? '').toString());
    final isAuthor = widget.post['authorUid'] == user.uid;
    final text = _commentController.text.trim();
    final canCommentOnJobRequest =
        !isJobRequest ||
        (!isAuthor &&
            _currentUserRole == 'worker' &&
            _currentUserHasActiveWorkerSubscription);

    if (!canCommentOnJobRequest) return;

    final bidPrice = _bidPriceController.text.trim();
    final isWorkerBid =
        isJobRequest &&
        !isAuthor &&
        _currentUserRole == 'worker' &&
        _currentUserHasActiveWorkerSubscription;
    final existingBid = isWorkerBid
        ? _comments.cast<Map<String, dynamic>?>().firstWhere(
            (comment) =>
                comment != null &&
                comment['authorUid']?.toString() == user.uid &&
                (comment['isBid'] == true || (comment['bidPrice'] != null)),
            orElse: () => null,
          )
        : null;

    if (text.isEmpty && (!isWorkerBid || bidPrice.isEmpty)) return;

    setState(() => _isSubmittingComment = true);
    final commentData = {
      'text': text,
      'authorName': user.displayName ?? widget.localizedStrings['anonymous'],
      'authorUid': user.uid,
      'authorRole': _currentUserRole,
      'bidPrice': isWorkerBid ? bidPrice : null,
      'isBid': isWorkerBid && bidPrice.isNotEmpty,
      'timestamp': FieldValue.serverTimestamp(),
    };
    try {
      final commentsRef = _firestore
          .collection('blog_posts')
          .doc(widget.post['id'])
          .collection('blog_comments');

      if (existingBid != null && existingBid['id'] != null) {
        await commentsRef.doc(existingBid['id']).set({
          ...commentData,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await commentsRef.add(commentData);
      }
      _commentController.clear();
      _bidPriceController.clear();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _selectWorkerOffer(Map<String, dynamic> comment) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.localizedStrings['confirm_choose_worker_title']),
        content: Text(widget.localizedStrings['confirm_choose_worker_body']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.localizedStrings['cancel']),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
            ),
            child: Text(widget.localizedStrings['choose_worker']),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore.collection('blog_posts').doc(widget.post['id']).set({
        'selectedBidId': comment['id'],
        'selectedWorkerUid': comment['authorUid'],
        'selectedWorkerName': comment['authorName'],
        'selectedBidPrice': comment['bidPrice'],
        'selectedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        widget.post['selectedBidId'] = comment['id'];
        widget.post['selectedWorkerUid'] = comment['authorUid'];
        widget.post['selectedWorkerName'] = comment['authorName'];
        widget.post['selectedBidPrice'] = comment['bidPrice'];
      });
    } catch (_) {}
  }

  DateTime? _postDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _localizedCategoryLabel(String raw) {
    return _localizedCategoryValueForMap(raw, widget.localizedStrings);
  }

  String _localizedProfessionLabel(String raw, String localeCode) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return '';
    final canonical = ProfessionLocalization.toCanonical(normalized);
    return ProfessionLocalization.toLocalized(canonical, localeCode);
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _uiSoftSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _uiBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: _uiMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _uiMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _uiTitle,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPostLocation() async {
    final lat = widget.post['locationLat'];
    final lng = widget.post['locationLng'];
    if (lat == null || lng == null) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${(lat as num).toDouble()},${(lng as num).toDouble()}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showPostActionsSheet({
    required bool isAuthor,
    required bool isAdmin,
  }) async {
    final textTheme = Theme.of(context).textTheme;

    Widget actionTile({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
      bool isDestructive = false,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isDestructive
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDestructive
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<Widget> actions;
    if (isAdmin) {
      actions = [
        actionTile(
          icon: Icons.delete_outline_rounded,
          title: widget.localizedStrings['delete'] ?? 'Delete',
          onTap: widget.onDelete,
          isDestructive: true,
        ),
        actionTile(
          icon: Icons.flag_outlined,
          title: widget.localizedStrings['report'] ?? 'Report',
          onTap: widget.onReport,
          isDestructive: true,
        ),
      ];
    } else if (isAuthor) {
      actions = [
        actionTile(
          icon: Icons.edit_outlined,
          title: widget.localizedStrings['edit'] ?? 'Edit',
          onTap: widget.onEdit,
        ),
        actionTile(
          icon: Icons.delete_outline_rounded,
          title: widget.localizedStrings['delete'] ?? 'Delete',
          onTap: widget.onDelete,
          isDestructive: true,
        ),
      ];
    } else {
      actions = [
        actionTile(
          icon: Icons.block_outlined,
          title: widget.localizedStrings['block_user'] ?? 'Block user',
          onTap: widget.onBlockUser,
          isDestructive: true,
        ),
        actionTile(
          icon: Icons.flag_outlined,
          title: widget.localizedStrings['report'] ?? 'Report',
          onTap: widget.onReport,
          isDestructive: true,
        ),
      ];
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.localizedStrings['post_actions'] ??
                                'Post actions',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final user = FirebaseAuth.instance.currentUser;
    final isJobRequest =
        widget.post['isJobRequest'] == true ||
        _isJobRequestCategoryValue((widget.post['category'] ?? '').toString());
    final isAuthor = user != null && widget.post['authorUid'] == user.uid;
    final isAdmin = _currentUserRole == 'admin';
    final canCommentOnJobRequest =
        isJobRequest &&
        !isAuthor &&
        _currentUserRole == 'worker' &&
        _currentUserHasActiveWorkerSubscription;
    final canComment = !isJobRequest || canCommentOnJobRequest;
    final canBid = canCommentOnJobRequest;
    final myExistingBid = user == null
        ? null
        : _comments.cast<Map<String, dynamic>?>().firstWhere(
            (comment) =>
                comment != null &&
                comment['authorUid']?.toString() == user.uid &&
                (comment['isBid'] == true || (comment['bidPrice'] != null)),
            orElse: () => null,
          );
    final selectedBidId = widget.post['selectedBidId']?.toString();
    final selectedWorkerName =
        widget.post['selectedWorkerName']?.toString().trim() ?? '';
    final selectedBidPrice =
        widget.post['selectedBidPrice']?.toString().trim() ?? '';
    final location = widget.post['location']?.toString().trim() ?? '';
    final professionRaw =
        (widget.post['professionLabel'] ?? widget.post['profession'] ?? '')
            .toString()
            .trim();
    final profession = _localizedProfessionLabel(professionRaw, localeCode);
    final category = _localizedCategoryLabel(
      (widget.post['category'] ?? '').toString(),
    );
    final requestDateFrom = _postDate(widget.post['requestDateFrom']);
    final requestDateTo = _postDate(widget.post['requestDateTo']);
    final requestTimeFrom =
        widget.post['requestTimeFrom']?.toString().trim() ?? '';
    final requestTimeTo = widget.post['requestTimeTo']?.toString().trim() ?? '';
    final createdAt = _postDate(widget.post['timestamp']);
    final authorName = widget.post['authorName']?.toString().trim() ?? '';
    final likedByData = widget.post['likedBy'];
    bool isLiked = false;
    if (user != null && likedByData != null) {
      if (likedByData is Map)
        isLiked = likedByData.containsKey(user.uid);
      else if (likedByData is List)
        isLiked = likedByData.contains(user.uid);
    }
    final List<String> mediaUrls = _mediaUrlsFromPost(widget.post);

    return Scaffold(
      backgroundColor: _uiSurfaceBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _uiTitle,
        actions: [
          IconButton(
            onPressed: () =>
                _showPostActionsSheet(isAuthor: isAuthor, isAdmin: isAdmin),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: widget.localizedStrings['post_actions'] ?? 'Post actions',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mediaUrls.isNotEmpty)
                    SizedBox(
                      height: 250,
                      child: PageView.builder(
                        itemCount: mediaUrls.length,
                        itemBuilder: (context, index) {
                          final mediaUrl = mediaUrls[index];
                          final isVideo = _isMediaVideoPath(mediaUrl);
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullscreenMediaViewer(
                                    urls: mediaUrls,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            child: isVideo
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedVideoPlayer(
                                        url: mediaUrl,
                                        play: false,
                                        fit: BoxFit.cover,
                                      ),
                                      const Center(
                                        child: Icon(
                                          Icons.play_circle_fill_rounded,
                                          size: 54,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  )
                                : CachedNetworkImage(
                                    imageUrl: mediaUrl,
                                    width: double.infinity,
                                    height: 250,
                                    fit: BoxFit.cover,
                                  ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF5FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  color: _uiPrimaryBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: widget.onLike,
                              child: Row(
                                children: [
                                  Icon(
                                    isLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(widget.post['likes'].toString()),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.post['title'] ?? '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _uiTitle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.post['content'] ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            color: _uiBody,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (authorName.isNotEmpty)
                          _buildInfoCard(
                            icon: Icons.person_outline_rounded,
                            label: widget.localizedStrings['author'],
                            value: authorName,
                          ),
                        if (createdAt != null)
                          _buildInfoCard(
                            icon: Icons.schedule_rounded,
                            label: widget.localizedStrings['posted'],
                            value: intl.DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(createdAt),
                          ),
                        if (profession.isNotEmpty)
                          _buildInfoCard(
                            icon: Icons.work_outline_rounded,
                            label: widget.localizedStrings['profession'],
                            value: profession,
                          ),
                        if (location.isNotEmpty)
                          _buildInfoCard(
                            icon: Icons.location_on_outlined,
                            label: widget.localizedStrings['location'],
                            value: location,
                            onTap:
                                (widget.post['locationLat'] != null &&
                                    widget.post['locationLng'] != null)
                                ? _openPostLocation
                                : null,
                          ),
                        if (requestDateFrom != null || requestDateTo != null)
                          _buildInfoCard(
                            icon: Icons.date_range_rounded,
                            label: widget.localizedStrings['date_from'],
                            value:
                                requestDateFrom != null && requestDateTo != null
                                ? "${intl.DateFormat('dd/MM/yyyy').format(requestDateFrom)} - ${intl.DateFormat('dd/MM/yyyy').format(requestDateTo)}"
                                : requestDateFrom != null
                                ? intl.DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(requestDateFrom)
                                : intl.DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(requestDateTo!),
                          ),
                        if (requestTimeFrom.isNotEmpty ||
                            requestTimeTo.isNotEmpty)
                          _buildInfoCard(
                            icon: Icons.access_time_rounded,
                            label: widget.localizedStrings['time_from'],
                            value:
                                requestTimeFrom.isNotEmpty &&
                                    requestTimeTo.isNotEmpty
                                ? "$requestTimeFrom - $requestTimeTo"
                                : (requestTimeFrom.isNotEmpty
                                      ? requestTimeFrom
                                      : requestTimeTo),
                          ),
                        if (isJobRequest) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF5FF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.localizedStrings['workers_can_offer'],
                                  style: const TextStyle(
                                    color: _uiBody,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                                if (selectedWorkerName.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.verified_rounded,
                                          color: Color(0xFF16A34A),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selectedBidPrice.isEmpty
                                                ? "${widget.localizedStrings['selected_worker']}: $selectedWorkerName"
                                                : "${widget.localizedStrings['selected_worker']}: $selectedWorkerName • $selectedBidPrice ₪",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (!canCommentOnJobRequest) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    widget
                                        .localizedStrings['job_request_comment_restriction'],
                                    style: const TextStyle(
                                      color: _uiBody,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Divider(color: _uiBorder),
                        ),
                        Text(
                          widget.localizedStrings['comments'],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _uiTitle,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._comments.map((comment) {
                          final isSelectedBid =
                              selectedBidId != null &&
                              selectedBidId == comment['id']?.toString();
                          final workerUid =
                              comment['authorUid']?.toString().trim() ?? '';
                          final workerPreview = _workerPreviewCache[workerUid];
                          final bidPrice =
                              comment['bidPrice']?.toString().trim() ?? '';
                          final hasBid = bidPrice.isNotEmpty;

                          return InkWell(
                            onTap: workerUid.isEmpty
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            Profile(userId: workerUid),
                                      ),
                                    );
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelectedBid
                                    ? const Color(0xFFEAF5FF)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: isSelectedBid
                                    ? Border.all(color: const Color(0xFFBFDBFE))
                                    : Border.all(color: _uiBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundImage:
                                            (workerPreview?['profileImageUrl'] ??
                                                    '')
                                                .toString()
                                                .isNotEmpty
                                            ? CachedNetworkImageProvider(
                                                workerPreview!['profileImageUrl'],
                                              )
                                            : null,
                                        child:
                                            (workerPreview?['profileImageUrl'] ??
                                                    '')
                                                .toString()
                                                .isEmpty
                                            ? const Icon(Icons.person, size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              comment['authorName'] ??
                                                  widget
                                                      .localizedStrings['anonymous'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (hasBid && workerPreview != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.star_rounded,
                                                      size: 16,
                                                      color: Color(0xFFF59E0B),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "${(workerPreview['avgRating'] as double).toStringAsFixed(1)}",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Color(
                                                          0xFF334155,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      "(${workerPreview['reviewCount']})",
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF64748B,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (hasBid)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            "$bidPrice ₪",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: _uiPrimaryBlue,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (hasBid) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.localizedStrings['offer_price'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                  if ((comment['text'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(comment['text'] ?? ''),
                                  ],
                                  if (isSelectedBid) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      widget.localizedStrings['selected_offer'],
                                      style: const TextStyle(
                                        color: _uiPrimaryBlue,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ] else if (isJobRequest &&
                                      isAuthor &&
                                      hasBid) ...[
                                    const SizedBox(height: 10),
                                    TextButton.icon(
                                      onPressed: () =>
                                          _selectWorkerOffer(comment),
                                      icon: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        widget
                                            .localizedStrings['choose_worker'],
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _uiPrimaryBlue,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canBid) ...[
                  if (myExistingBid != null) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.localizedStrings['edit_your_bid'],
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _bidPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.localizedStrings['bid_price_hint'],
                      labelText: widget.localizedStrings['bid_price'],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _uiBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: _uiBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: _uiPrimaryBlue,
                          width: 1.3,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        enabled: canComment,
                        decoration: InputDecoration(
                          hintText: canComment
                              ? widget.localizedStrings['add_comment']
                              : widget
                                    .localizedStrings['job_request_comment_restriction'],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: _uiBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: _uiBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: _uiPrimaryBlue,
                              width: 1.3,
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSubmittingComment || !canComment
                          ? null
                          : _addComment,
                      icon: Icon(
                        canBid ? Icons.local_offer_outlined : Icons.send,
                        color: _uiPrimaryBlue,
                      ),
                      tooltip: canBid
                          ? (myExistingBid != null
                                ? widget.localizedStrings['update_bid']
                                : widget.localizedStrings['send_bid'])
                          : (!canComment
                                ? widget
                                      .localizedStrings['job_request_comment_restriction']
                                : null),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
