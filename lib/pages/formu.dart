import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:untitled1/language_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/pages/sighn_in.dart';

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _postsSubscription;
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isMoreLoading = false;
  int _postLimit = 10;
  final Set<String> _hiddenPostIds = {};
  String _sortBy = 'newest'; // 'newest' or 'likes'
  int _selectedFilterIndex = 0; // 0 is "All"
  bool _isGuideExpanded = true; // Added state for collapsible guide

  @override
  void initState() {
    super.initState();
    _listenToPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _postsSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isMoreLoading && !_isLoading && _posts.length >= _postLimit) {
        _loadMorePosts();
      }
    }
  }

  void _loadMorePosts() {
    setState(() {
      _isMoreLoading = true;
      _postLimit += 10;
    });
    _listenToPosts();
  }

  void _listenToPosts() {
    _postsSubscription?.cancel();

    Query query = _firestore.collection('blog_posts');
    final strings = _getLocalizedStrings(context);
    final categories = strings['categories'] as List;

    if (_selectedFilterIndex != 0 && _selectedFilterIndex < categories.length) {
      query = query.where('category', isEqualTo: categories[_selectedFilterIndex]);
    }

    query = query.orderBy('isPinned', descending: true);

    if (_sortBy == 'newest') {
      query = query.orderBy('timestamp', descending: true);
    } else if (_sortBy == 'likes') {
      query = query.orderBy('likes', descending: true);
    }

    _postsSubscription = query.limit(_postLimit).snapshots().listen((snapshot) {
      List<Map<String, dynamic>> loadedPosts = [];
      for (var doc in snapshot.docs) {
        final post = doc.data() as Map<String, dynamic>;
        post['id'] = doc.id;
        loadedPosts.add(post);
      }

      if (mounted) {
        setState(() {
          _posts = loadedPosts;
          _isLoading = false;
          _isMoreLoading = false;
        });
      }
    }, onError: (error) {
      debugPrint("FETCH ERROR: $error");
      if (mounted) {
        setState(() {
          _posts = [];
          _isLoading = false;
          _isMoreLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(strings['error'] ?? "Error loading posts"),
        ));
      }
    });
  }

  Future<void> _onRefresh() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _posts = [];
        _postLimit = 10;
      });
    }
    _listenToPosts();
    return Future.delayed(const Duration(milliseconds: 500));
  }

  void _sortPosts() {
    setState(() {
      _isLoading = true;
      _posts = [];
      _postLimit = 10;
    });
    _listenToPosts();
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'קהילה ודרושים',
          'create_post': 'פרסם בקהילה',
          'edit_post': 'ערוך פוסט',
          'post_title': 'כותרת',
          'post_category': 'סוג הפוסט',
          'post_content': 'מה תרצה לשתף?',
          'publish': 'פרסם',
          'update': 'עדכן',
          'cancel': 'ביטול',
          'categories': ['הכל', 'שאלה', 'טיפ', 'דרוש בעל מקצוע', 'המלצה', 'אחר'],
          'upload_photo': 'הוסף תמונות',
          'no_posts': 'אין פוסטים עדיין',
          'delete': 'מחק',
          'share': 'שתף',
          'report': 'דווח',
          'hide': 'הסתר',
          'edit': 'ערוך',
          'comments': 'תגובות / הצעות',
          'add_comment': 'הוסף תגובה או הצעה...',
          'sort': 'מיין לפי',
          'newest': 'הכי חדש',
          'most_liked': 'הכי הרבה לייקים',
          'guest_msg': 'עליך להירשם כדי לבצע פעולה זו',
          'login': 'התחברות',
          'error': 'שגיאה: חסרה הרשאה או בעיית תקשורת',
          'empty_fields': 'נא למלא כותרת ותוכן',
          'location': 'מיקום (עיר/אזור)',
          'job_request': 'דרוש בעל מקצוע',
          'guide_title': 'איך זה עובד?',
          'guide_content': '• שתפו שאלות, טיפים, המלצות ומדריכים.\n• צריכים עבודה? פרסמו "דרוש בעל מקצוע" עם מיקום ותמונות.\n• בעלי מקצוע? עקבו אחר דרישות והציעו שירות בתגובות.\n• סננו לפי קטגוריה בעזרת הסרגל העליון או בלחיצה על תגית בפוסט.\n• מיין את הפוסטים לפי "הכי חדש" או "הכי הרבה לייקים".\n• עשו לייק, הגיבו ושתפו פוסטים שמעניינים אתכם.\n• לחצו על פוסט כדי לראות תגובות ופרטים נוספים.\n• באפשרותכם לערוך או למחוק פוסטים שפרסמתם.\n• ניתן להסתיר פוסטים מהפיד או לדווח על תוכן לא ראוי.\n• גללו למטה לטעינת פוסטים נוספים והשתמשו בכפתור הרענון לעדכון הפיד.',
        };
      default:
        return {
          'title': 'Community & Jobs',
          'create_post': 'Post to Community',
          'edit_post': 'Edit Post',
          'post_title': 'Title',
          'post_category': 'Category',
          'post_content': 'What\'s on your mind?',
          'publish': 'Publish',
          'update': 'Update',
          'cancel': 'Cancel',
          'categories': ['All', 'Question', 'Tip', 'Job Request', 'Recommendation', 'Other'],
          'upload_photo': 'Add Photos',
          'no_posts': 'No posts yet',
          'delete': 'Delete',
          'share': 'Share',
          'report': 'Report',
          'hide': 'Hide',
          'edit': 'Edit',
          'comments': 'Comments / Offers',
          'add_comment': 'Add a comment or offer...',
          'sort': 'Sort by',
          'newest': 'Newest',
          'most_liked': 'Most Liked',
          'guest_msg': 'You must sign up to perform this action',
          'login': 'Sign In',
          'error': 'Error: Permission denied or connection issue',
          'empty_fields': 'Please fill both title and content',
          'location': 'Location (City/Area)',
          'job_request': 'Job Request',
          'guide_title': 'How it works?',
          'guide_content': '• Share questions, tips, recommendations, and guides.\n• Need a pro? Post a "Job Request" with location and photos.\n• Professionals? Browse jobs and offer your services in the comments.\n• Filter by category using the top bar or by tapping a tag on a post.\n• Sort the feed by "Newest" or "Most Liked".\n• Like, comment, and share posts that interest you.\n• Tap a post to see full details and all comments.\n• Edit or delete your own posts at any time.\n• Hide posts from your feed or report inappropriate content.\n• Scroll down to load more posts and use the refresh button to update the feed.',
        };
    }
  }

  bool _isGuest() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  void _showGuestDialog(BuildContext context, Map<String, dynamic> strings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['guest_msg']),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(strings['cancel'])),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInPage()));
            },
            child: Text(strings['login']),
          ),
        ],
      ),
    );
  }

  void _showCreatePostSheet(BuildContext context, {Map<String, dynamic>? existingPost}) {
    final strings = _getLocalizedStrings(context);
    if (_isGuest()) {
      _showGuestDialog(context, strings);
      return;
    }

    final titleController = TextEditingController(text: existingPost?['title']);
    final contentController = TextEditingController(text: existingPost?['content']);
    final locationController = TextEditingController(text: existingPost?['location']);
    String selectedCategory = existingPost?['category'] ?? (strings['categories'] as List)[1];
    List<File> selectedImages = [];
    List<String> existingImageUrls = existingPost?['imageUrls'] != null
        ? List<String>.from(existingPost!['imageUrls'])
        : (existingPost?['imageUrl'] != null ? [existingPost!['imageUrl']] : []);
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(existingPost == null ? strings['create_post'] : strings['edit_post'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: InputDecoration(
                    labelText: strings['post_category'],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  items: (strings['categories'] as List).where((cat) => cat != 'All' && cat != 'הכל').map((cat) => DropdownMenuItem(value: cat.toString(), child: Text(cat.toString()))).toList(),
                  onChanged: (val) => setSheetState(() => selectedCategory = val!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: strings['post_title'],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedCategory == strings['job_request']) ...[
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      labelText: strings['location'],
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: contentController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: strings['post_content'],
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                if (selectedImages.isNotEmpty || existingImageUrls.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedImages.length + existingImageUrls.length,
                      itemBuilder: (context, index) {
                        bool isExisting = index < existingImageUrls.length;
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: isExisting
                                    ? NetworkImage(existingImageUrls[index]) as ImageProvider
                                    : FileImage(selectedImages[index - existingImageUrls.length]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: () => setSheetState(() {
                                  if (isExisting) {
                                    existingImageUrls.removeAt(index);
                                  } else {
                                    selectedImages.removeAt(index - existingImageUrls.length);
                                  }
                                }),
                                child: const CircleAvatar(backgroundColor: Colors.black54, radius: 12, child: Icon(Icons.close, size: 14, color: Colors.white)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFiles = await picker.pickMultiImage(imageQuality: 70);
                    if (pickedFiles.isNotEmpty) {
                      setSheetState(() => selectedImages.addAll(pickedFiles.map((x) => File(x.path))));
                    }
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(strings['upload_photo']),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isUploading ? null : () async {
                    if (titleController.text.trim().isEmpty || contentController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['empty_fields'])));
                      return;
                    }

                    setSheetState(() => isUploading = true);
                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) throw Exception("User not signed in");

                      String authorName = user.displayName ?? "User";
                      if (user.displayName == null || user.displayName!.isEmpty) {
                        try {
                          final userDoc = await _firestore.collection('users').doc(user.uid).get();
                          if (userDoc.exists) authorName = userDoc.data()?['name'] ?? "User";
                        } catch (_) {}
                      }

                      List<String> imageUrls = List.from(existingImageUrls);
                      for (var file in selectedImages) {
                        final storageRef = FirebaseStorage.instance.ref().child('blog_images/${user.uid}_${DateTime.now().millisecondsSinceEpoch}_${selectedImages.indexOf(file)}.jpg');
                        await storageRef.putFile(file);
                        String url = await storageRef.getDownloadURL();
                        imageUrls.add(url);
                      }

                      final postData = {
                        'title': titleController.text.trim(),
                        'content': contentController.text.trim(),
                        'category': selectedCategory,
                        'location': locationController.text.trim(),
                        'imageUrls': imageUrls,
                        'imageUrl': imageUrls.isNotEmpty ? imageUrls[0] : null,
                        'authorUid': user.uid,
                        'authorName': authorName,
                        'timestamp': existingPost?['timestamp'] ?? FieldValue.serverTimestamp(),
                        'likes': existingPost?['likes'] ?? 0,
                        'likedBy': existingPost?['likedBy'] ?? {},
                        'isJobRequest': selectedCategory == strings['job_request'],
                        'isPinned': existingPost?['isPinned'] ?? false,
                      };

                      if (existingPost == null) {
                        await _firestore.collection('blog_posts').add(postData);
                      } else {
                        await _firestore.collection('blog_posts').doc(existingPost['id']).update(postData);
                      }

                      if (mounted) Navigator.pop(context);
                      setState(() {
                        _selectedFilterIndex = 0;
                        _isLoading = true;
                        _posts = [];
                      });
                      _listenToPosts();
                    } catch (e) {
                      debugPrint("BLOG PUBLISH ERROR: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text("${strings['error']}. Make sure your rules allow writes."),
                          duration: const Duration(seconds: 5),
                        ));
                      }
                    } finally {
                      if (mounted) setSheetState(() => isUploading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isUploading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(existingPost == null ? strings['publish'] : strings['update'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deletePost(String postId) async {
    try {
      setState(() {
        _posts.removeWhere((post) => post['id'] == postId);
      });
      await _firestore.collection('blog_posts').doc(postId).delete();
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error deleting post")));
        _listenToPosts();
      }
    }
  }

  void _toggleLike(Map<String, dynamic> post) async {
    final strings = _getLocalizedStrings(context);
    if (_isGuest()) {
      _showGuestDialog(context, strings);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postId = post['id'];
    Map<String, dynamic> likedBy = Map<String, dynamic>.from(post['likedBy'] ?? {});
    int likes = post['likes'] ?? 0;

    if (likedBy.containsKey(user.uid)) {
      likedBy.remove(user.uid);
      likes = likes > 0 ? likes - 1 : 0;
    } else {
      likedBy[user.uid] = true;
      likes++;
    }

    try {
      await _firestore.collection('blog_posts').doc(postId).update({
        'likes': likes,
        'likedBy': likedBy,
      });
    } catch (e) {
      debugPrint("LIKE ERROR: $e");
    }
  }

  Widget _buildExplanationCard(Map<String, dynamic> strings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isGuideExpanded = !_isGuideExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(strings['guide_title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                  Icon(
                    _isGuideExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          if (_isGuideExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                strings['guide_content'],
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6, fontWeight: FontWeight.w400),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Map<String, dynamic> strings) {
    final categories = strings['categories'] as List;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = _selectedFilterIndex == index;

          IconData icon;
          switch (index) {
            case 0: icon = Icons.grid_view_rounded; break;
            case 1: icon = Icons.help_outline_rounded; break;
            case 2: icon = Icons.lightbulb_outline_rounded; break;
            case 3: icon = Icons.work_outline_rounded; break;
            case 4: icon = Icons.star_outline_rounded; break;
            default: icon = Icons.more_horiz_rounded;
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 10),
            child: FilterChip(
              showCheckmark: false,
              avatar: Icon(icon, size: 18, color: isSelected ? Colors.white : const Color(0xFF1976D2)),
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedFilterIndex = index;
                    _isLoading = true;
                    _posts = [];
                    _postLimit = 10;
                  });
                  _listenToPosts();
                }
              },
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF1976D2),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF475569),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF1976D2) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              elevation: isSelected ? 4 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final visiblePosts = _posts.where((p) => !_hiddenPostIds.contains(p['id'])).toList();

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          title: Text(strings['title'], style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 22)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF1976D2)),
              onPressed: _onRefresh,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: Color(0xFF1976D2)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (value) {
                setState(() {
                  _sortBy = value;
                  _sortPosts();
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'newest', child: Row(children: [const Icon(Icons.access_time, size: 20), const SizedBox(width: 10), Text(strings['newest'])])),
                PopupMenuItem(value: 'likes', child: Row(children: [const Icon(Icons.favorite_outline, size: 20), const SizedBox(width: 10), Text(strings['most_liked'])])),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: _buildFilterBar(strings),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreatePostSheet(context),
          backgroundColor: const Color(0xFF1976D2),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(strings['publish'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : visiblePosts.isEmpty
              ? ListView(
                  children: [
                    _buildExplanationCard(strings),
                    const SizedBox(height: 60),
                    Center(child: Text(strings['no_posts'], style: const TextStyle(color: Colors.grey))),
                  ],
                )
              : ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: visiblePosts.length + 1 + (_isMoreLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildExplanationCard(strings);
                    }
                    final postIndex = index - 1;
                    if (postIndex < visiblePosts.length) {
                      return _BlogCard(
                        post: visiblePosts[postIndex],
                        onLike: () => _toggleLike(visiblePosts[postIndex]),
                        onDelete: () => _deletePost(visiblePosts[postIndex]['id']),
                        onEdit: () => _showCreatePostSheet(context, existingPost: visiblePosts[postIndex]),
                        onHide: () => setState(() => _hiddenPostIds.add(visiblePosts[postIndex]['id'])),
                        onCategoryTap: (categoryName) {
                          final categories = strings['categories'] as List;
                          final catIndex = categories.indexOf(categoryName);
                          if (catIndex != -1) {
                            setState(() {
                              _selectedFilterIndex = catIndex;
                              _isLoading = true;
                              _posts = [];
                              _postLimit = 10;
                            });
                            _listenToPosts();
                          }
                        },
                        localizedStrings: strings,
                        onGuestDialog: () => _showGuestDialog(context, strings),
                      );
                    } else if (_isMoreLoading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
        ),
      ),
    );
  }
}

class _BlogCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onHide;
  final Function(String) onCategoryTap;
  final Map<String, dynamic> localizedStrings;
  final VoidCallback onGuestDialog;

  const _BlogCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onDelete,
    required this.onEdit,
    required this.onHide,
    required this.onCategoryTap,
    required this.localizedStrings,
    required this.onGuestDialog,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user != null && post['authorUid'] == user.uid;
    final isLiked = user != null && (post['likedBy'] ?? {}).containsKey(user.uid);
    final isJobRequest = post['isJobRequest'] == true;
    final isPinned = post['isPinned'] == true;
    final imageUrls = post['imageUrls'] != null ? List<String>.from(post['imageUrls']) : (post['imageUrl'] != null ? [post['imageUrl'] as String] : []);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isPinned
          ? Border.all(color: Colors.blue.shade200, width: 2)
          : (isJobRequest ? Border.all(color: Colors.orange.shade200, width: 2) : null),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PostDetailPage(post: post, onLike: onLike, onEdit: onEdit, onDelete: onDelete, localizedStrings: localizedStrings, onGuestDialog: onGuestDialog))),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrls.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    Image.network(imageUrls[0], height: 180, width: double.infinity, fit: BoxFit.cover),
                    if (imageUrls.length > 1)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.copy, size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text("${imageUrls.length}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPinned)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.push_pin, size: 16, color: Colors.blue),
                        ),
                      GestureDetector(
                        onTap: () => onCategoryTap(post['category'] ?? ''),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isJobRequest ? Colors.orange.shade50 : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Text(
                            post['category'] ?? '',
                            style: TextStyle(
                              color: isJobRequest ? Colors.orange.shade800 : const Color(0xFF4F46E5),
                              fontWeight: FontWeight.bold,
                              fontSize: 12
                            )
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isJobRequest && post['location'] != null && post['location'].toString().isNotEmpty)
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Flexible(child: Text(post['location'], style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Color(0xFF94A3B8)),
                        onSelected: (value) {
                          if (value == 'delete') onDelete();
                          if (value == 'edit') onEdit();
                          if (value == 'share') Share.share('${post['title']}\n${post['content']}');
                          if (value == 'hide') onHide();
                          if (value == 'report') {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported successfully')));
                          }
                        },
                        itemBuilder: (context) => isAuthor ? [
                          PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit), const SizedBox(width: 8), Text(localizedStrings['edit'])])),
                          PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete, color: Colors.red), const SizedBox(width: 8), Text(localizedStrings['delete'], style: const TextStyle(color: Colors.red))])),
                          PopupMenuItem(value: 'share', child: Row(children: [const Icon(Icons.share), const SizedBox(width: 8), Text(localizedStrings['share'])])),
                        ] : [
                          PopupMenuItem(value: 'hide', child: Row(children: [const Icon(Icons.visibility_off), const SizedBox(width: 8), Text(localizedStrings['hide'])])),
                          PopupMenuItem(value: 'share', child: Row(children: [const Icon(Icons.share), const SizedBox(width: 8), Text(localizedStrings['share'])])),
                          PopupMenuItem(value: 'report', child: Row(children: [const Icon(Icons.report, color: Colors.orange), const SizedBox(width: 8), Text(localizedStrings['report'], style: const TextStyle(color: Colors.orange))])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(post['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Text(
                    post['content'] ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF64748B), height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(post['authorName'] ?? 'Anonymous', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onLike,
                        child: Row(
                          children: [
                            Icon(isLiked ? Icons.favorite : Icons.favorite_border, size: 18, color: const Color(0xFFEF4444)),
                            const SizedBox(width: 4),
                            Text((post['likes'] ?? 0).toString(), style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Map<String, dynamic> localizedStrings;
  final VoidCallback onGuestDialog;

  const PostDetailPage({
    super.key,
    required this.post,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
    required this.localizedStrings,
    required this.onGuestDialog,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _comments = [];
  StreamSubscription? _commentsSubscription;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _listenToComments();
  }

  @override
  void dispose() {
    _commentsSubscription?.cancel();
    super.dispose();
  }

  void _listenToComments() {
    _commentsSubscription = _firestore.collection('blog_posts')
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
      }
      if (mounted) setState(() => _comments = loadedComments);
    });
  }

  void _addComment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      widget.onGuestDialog();
      return;
    }

    if (_commentController.text.trim().isEmpty) return;

    final commentData = {
      'text': _commentController.text.trim(),
      'authorName': user.displayName ?? 'Anonymous',
      'authorUid': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
    };
    try {
      await _firestore.collection('blog_posts')
          .doc(widget.post['id'])
          .collection('blog_comments')
          .add(commentData);
      _commentController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Permission denied: Update your rules.")));
    }
  }

  void _deleteComment(String commentId) async {
    try {
      await _firestore.collection('blog_posts')
          .doc(widget.post['id'])
          .collection('blog_comments')
          .doc(commentId)
          .delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user != null && widget.post['authorUid'] == user.uid;
    final isLiked = user != null && (widget.post['likedBy'] ?? {}).containsKey(user.uid);
    final isJobRequest = widget.post['isJobRequest'] == true;
    final imageUrls = widget.post['imageUrls'] != null ? List<String>.from(widget.post['imageUrls']) : (widget.post['imageUrl'] != null ? [widget.post['imageUrl'] as String] : []);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                widget.onDelete();
                Navigator.pop(context);
              }
              if (value == 'edit') {
                widget.onEdit();
                Navigator.pop(context);
              }
              if (value == 'report') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported successfully')));
              }
            },
            itemBuilder: (context) => isAuthor ? [
              PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit), const SizedBox(width: 8), Text(widget.localizedStrings['edit'])])),
              PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete, color: Colors.red), const SizedBox(width: 8), Text(widget.localizedStrings['delete'], style: const TextStyle(color: Colors.red))])),
            ] : [
              PopupMenuItem(value: 'report', child: Row(children: [const Icon(Icons.report, color: Colors.orange), const SizedBox(width: 8), Text(widget.localizedStrings['report'], style: const TextStyle(color: Colors.orange))])),
            ],
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
                  if (imageUrls.isNotEmpty)
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        SizedBox(
                          height: 300,
                          child: PageView.builder(
                            itemCount: imageUrls.length,
                            onPageChanged: (index) => setState(() => _currentImageIndex = index),
                            itemBuilder: (context, index) => Image.network(imageUrls[index], width: double.infinity, fit: BoxFit.cover),
                          ),
                        ),
                        if (imageUrls.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(imageUrls.length, (index) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index ? Colors.white : Colors.white54,
                                ),
                              )),
                            ),
                          ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isJobRequest ? Colors.orange.shade50 : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Text(
                                widget.post['category'] ?? '',
                                style: TextStyle(
                                  color: isJobRequest ? Colors.orange.shade800 : const Color(0xFF4F46E5),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12
                                )
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: widget.onLike,
                              child: Row(
                                children: [
                                  Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: Colors.red),
                                  const SizedBox(width: 4),
                                  Text(widget.post['likes'].toString()),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(widget.post['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                        if (isJobRequest && widget.post['location'] != null && widget.post['location'].toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 18, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(widget.post['location'], style: const TextStyle(fontSize: 16, color: Color(0xFF64748B))),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Text(widget.post['authorName'] ?? 'Anonymous', style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
                        Text(
                          widget.post['content'] ?? '',
                          style: const TextStyle(fontSize: 16, color: Color(0xFF334155), height: 1.7),
                        ),
                        const SizedBox(height: 32),
                        Text(widget.localizedStrings['comments'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        ..._comments.map((comment) {
                          final isCommentAuthor = user != null && comment['authorUid'] == user.uid;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(comment['authorName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    const Spacer(),
                                    if (isCommentAuthor || isAuthor)
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_horiz, size: 18),
                                        onSelected: (val) {
                                          if (val == 'delete') _deleteComment(comment['id']);
                                        },
                                        itemBuilder: (ctx) => [
                                          PopupMenuItem(value: 'delete', child: Text(widget.localizedStrings['delete'], style: const TextStyle(color: Colors.red, fontSize: 13))),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(comment['text'] ?? ''),
                              ],
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: widget.localizedStrings['add_comment'],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send, color: Color(0xFF1976D2)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
