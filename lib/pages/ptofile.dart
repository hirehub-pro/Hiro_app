import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:untitled1/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/pages/edit_profile.dart';

class profile extends StatefulWidget {
  final String? userId; 
  const profile({super.key, this.userId});

  @override
  State<profile> createState() => _ProfileState();
}

class _ProfileState extends State<profile> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ImagePicker _picker = ImagePicker();
  
  String _userName = "";
  String _bio = "";
  String _phoneNumber = "";
  String _altPhoneNumber = "";
  String _email = "";
  String _town = "";
  String _profileImageUrl = "";
  List<String> _userProfessions = [];
  List<Map<String, dynamic>> _userReviews = [];
  List<Map<String, dynamic>> _projects = [];
  
  bool _isOwnProfile = false;
  bool _isLoading = true;
  bool _isFollowing = false; 
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUid = widget.userId ?? currentUser?.uid;

    if (targetUid == null) return;

    if (mounted) {
      setState(() {
        _isOwnProfile = (targetUid == currentUser?.uid);
        _isLoading = true;
      });
    }

    try {
      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
      ).ref();
      
      final userSnapshot = await dbRef.child('users').child(targetUid).get();
      if (userSnapshot.exists && mounted) {
        final dynamic userDataValue = userSnapshot.value;
        if (userDataValue is Map) {
          final data = Map<String, dynamic>.from(userDataValue);
          setState(() {
            _userName = data['name']?.toString() ?? "";
            _bio = data['description']?.toString() ?? "";
            _phoneNumber = data['phone']?.toString() ?? "";
            _altPhoneNumber = data['optionalPhone']?.toString() ?? "";
            _email = data['email']?.toString() ?? "";
            _town = data['town']?.toString() ?? "";
            _profileImageUrl = data['profileImageUrl']?.toString() ?? "";
            
            if (data['professions'] is List) {
              _userProfessions = List<String>.from(data['professions']);
            } else if (data['profession'] != null) {
              _userProfessions = [data['profession'].toString()];
            } else {
              _userProfessions = [];
            }
          });
        }
      }

      final reviewsSnapshot = await dbRef.child('reviews').child(targetUid).get();
      List<Map<String, dynamic>> loadedReviews = [];
      
      if (reviewsSnapshot.exists && reviewsSnapshot.value != null) {
        final dynamic rawReviews = reviewsSnapshot.value;
        if (rawReviews is Map) {
          rawReviews.forEach((key, value) {
            if (value is Map) {
              final Map<String, dynamic> reviewMap = {};
              value.forEach((k, v) => reviewMap[k.toString()] = v);
              reviewMap['id'] = key.toString(); // This is the reviewer UID
              loadedReviews.add(reviewMap);
            }
          });
        }
      }

      final projectsSnapshot = await dbRef.child('projects').child(targetUid).get();
      List<Map<String, dynamic>> loadedProjects = [];
      if (projectsSnapshot.exists && projectsSnapshot.value != null) {
        final dynamic rawProjects = projectsSnapshot.value;
        if (rawProjects is Map) {
          rawProjects.forEach((key, value) {
            if (value is Map) {
              final Map<String, dynamic> projectMap = {};
              value.forEach((k, v) => projectMap[k.toString()] = v);
              projectMap['id'] = key.toString();
              loadedProjects.add(projectMap);
            }
          });
        } else if (rawProjects is List) {
          for (int i = 0; i < rawProjects.length; i++) {
            final value = rawProjects[i];
            if (value is Map) {
              final Map<String, dynamic> projectMap = {};
              value.forEach((k, v) => projectMap[k.toString()] = v);
              projectMap['id'] = i.toString();
              loadedProjects.add(projectMap);
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _userReviews = loadedReviews;
          _projects = loadedProjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("FETCH ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'פרופיל',
          'user_name': _userName.isNotEmpty ? _userName : 'שם משתמש',
          'edit_profile': 'ערוך פרופיל',
          'share_profile': 'שתף פרופיל',
          'followers': 'עוקבים',
          'rate': '₪ לשעה',
          'bio': _bio.isNotEmpty ? _bio : 'כאן יופיע התיאור האישי שלך...',
          'projects': 'פרויקטים',
          'reviews': 'ביקורות',
          'about': 'אודות',
          'add_project': 'הוסף פרויקט',
          'call': 'התקשר',
          'message': 'הודעה',
          'follow': 'עקוב',
          'following': 'עוקב',
          'contact_info': 'מידע ליצירת קשר',
          'skills': 'כישורים',
          'no_reviews': 'אין עדיין ביקורות',
          'rating_title': 'דרג את העובד',
          'rating_hint': 'כתוב ביקורת...',
          'submit': 'שלח',
          'cancel': 'ביטול',
          'uploading': 'מעלה...',
          'description': 'תיאור',
          'take_photo': 'צלם תמונה',
          'pick_gallery': 'בחר מהגלריה',
          'add': 'הוסף',
          'delete_project': 'מחק פרויקט',
          'delete_confirm': 'האם אתה בטוח שברצונך למחוק פרויקט זה?',
          'delete': 'מחק',
        };
      case 'ar':
        return {
          'title': 'الملف الشخصي',
          'user_name': _userName.isNotEmpty ? _userName : 'اسم المستخدم',
          'edit_profile': 'تعديل الملف الشخصي',
          'share_profile': 'مشاركة الملف الشخصي',
          'followers': 'متابعون',
          'rate': '₪ لكل ساعة',
          'bio': _bio.isNotEmpty ? _bio : 'هنا سيظهر وصفك الشخصي...',
          'projects': 'المشاريع',
          'reviews': 'المراجعات',
          'about': 'حول',
          'add_project': 'إضافة مشروع',
          'call': 'اتصال',
          'message': 'رسالة',
          'follow': 'متابعة',
          'following': 'متابع',
          'contact_info': 'معلومات الاتصال',
          'skills': 'المهارات',
          'no_reviews': 'لا توجد مراجعات بعد',
          'rating_title': 'تقييم العامل',
          'rating_hint': 'اكتب مراجعة...',
          'submit': 'إرسال',
          'cancel': 'إلغاء',
          'uploading': 'جاري الرفع...',
          'description': 'الوصف',
          'take_photo': 'التقاط صورة',
          'pick_gallery': 'اختيار من الاستوديو',
          'add': 'إضافة',
          'delete_project': 'حذف المشروع',
          'delete_confirm': 'هل أنت متأكد أنك تريد حذف هذا المشروع؟',
          'delete': 'حذف',
        };
      default:
        return {
          'title': 'Profile',
          'user_name': _userName.isNotEmpty ? _userName : 'User Name',
          'edit_profile': 'Edit profile',
          'share_profile': 'Share profile',
          'followers': 'Followers',
          'rate': '₪ per hour',
          'bio': _bio.isNotEmpty ? _bio : 'Professional service provider with years of experience.',
          'projects': 'Projects',
          'reviews': 'Reviews',
          'about': 'About',
          'add_project': 'Add Project',
          'call': 'Call',
          'message': 'Message',
          'follow': 'Follow',
          'following': 'Following',
          'contact_info': 'Contact Info',
          'skills': 'Skills',
          'no_reviews': 'No reviews yet',
          'rating_title': 'Rate Worker',
          'rating_hint': 'Write a review...',
          'submit': 'Submit',
          'cancel': 'Cancel',
          'uploading': 'Uploading...',
          'description': 'Description',
          'take_photo': 'Take Photo',
          'pick_gallery': 'Pick from Gallery',
          'add': 'Add',
          'delete_project': 'Delete Project',
          'delete_confirm': 'Are you sure you want to delete this project?',
          'delete': 'Delete',
        };
    }
  }

  void _shareProfile(Map<String, String> strings) {
    String shareContent = "${strings['user_name']}: $_userName\n${strings['bio']}: $_bio\nCheck out this profile on ProFix!";
    Share.share(shareContent);
  }

  Future<void> _updateProfilePicture() async {
    if (!_isOwnProfile) return;
    
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      maxWidth: 1080,
    );
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _uploadProgress = 0;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final storageRef = FirebaseStorage.instance.ref().child('profile_pictures/${currentUser.uid}.jpg');
      final uploadTask = storageRef.putFile(File(image.path));

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted && snapshot.totalBytes > 0) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      await uploadTask;
      final String downloadUrl = await storageRef.getDownloadURL();

      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
      ).ref();

      await dbRef.child('users').child(currentUser.uid).update({'profileImageUrl': downloadUrl});
      
      _fetchUserData();
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addProject(Map<String, String> strings) async {
    final descController = TextEditingController();
    XFile? pickedFile;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(strings['add_project']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pickedFile != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(pickedFile!.path), height: 120, width: 120, fit: BoxFit.cover)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAddOption(Icons.camera_alt, strings['take_photo']!, () async {
                    final photo = await _picker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 100,
                      maxWidth: 1080,
                    );
                    if (photo != null) setDialogState(() => pickedFile = photo);
                  }),
                  _buildAddOption(Icons.photo_library, strings['pick_gallery']!, () async {
                    final image = await _picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 100,
                      maxWidth: 1080,
                    );
                    if (image != null) setDialogState(() => pickedFile = image);
                  }),
                ],
              ),
              const SizedBox(height: 16),
              TextField(controller: descController, decoration: InputDecoration(hintText: strings['description'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(strings['cancel']!)),
            ElevatedButton(onPressed: () async {
              if (pickedFile != null) {
                Navigator.pop(context);
                await _uploadProject(pickedFile!, descController.text, strings);
              }
            }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2)), child: Text(strings['add']!, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, color: const Color(0xFF1976D2), size: 30), onPressed: onTap),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Future<void> _uploadProject(XFile file, String description, Map<String, String> strings) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
      _uploadProgress = 0;
    });

    try {
      final String fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final storageRef = FirebaseStorage.instance.ref().child('projects/${currentUser.uid}/$fileName');
      
      final uploadTask = storageRef.putFile(File(file.path));

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted && snapshot.totalBytes > 0) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      await uploadTask;
      final String downloadUrl = await storageRef.getDownloadURL();
      
      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
      ).ref();

      final projectData = {
        'imageUrl': downloadUrl,
        'description': description,
        'likes': 0,
        'timestamp': ServerValue.timestamp,
      };

      await dbRef.child('projects').child(currentUser.uid).push().set(projectData);
      _fetchUserData();
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteProject(String projectId, String imageUrl, Map<String, String> strings) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['delete_project']!),
        content: Text(strings['delete_confirm']!),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings['cancel']!)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings['delete']!, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
      ).ref();

      // Delete from Database
      await dbRef.child('projects').child(currentUser.uid).child(projectId).remove();

      // Delete from Storage
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      } catch (e) {
        debugPrint("STORAGE DELETE ERROR: $e");
      }

      _fetchUserData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Project deleted successfully")),
        );
      }
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final theme = Theme.of(context);
    final isRtl = Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                  Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: theme.colorScheme.background,
        body: RefreshIndicator(
          onRefresh: _fetchUserData,
          child: _isLoading 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    if (_uploadProgress > 0) ...[
                      const SizedBox(height: 16),
                      Text("${(_uploadProgress * 100).toStringAsFixed(0)}%", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      Text(strings['uploading']!),
                    ]
                  ],
                ),
              )
            : CustomScrollView(
                slivers: [
                  _buildSliverAppBar(theme),
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                      child: Column(
                        children: [
                          Text(strings['user_name']!, style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 16),
                          _buildStatsRow(strings, theme),
                          const SizedBox(height: 24),
                          Text(strings['bio']!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 32),
                          if (!_isOwnProfile) _buildActionButtons(strings, theme),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: theme.colorScheme.primary,
                        unselectedLabelColor: const Color(0xFF94A3B8),
                        indicatorColor: theme.colorScheme.primary,
                        indicatorWeight: 3,
                        dividerColor: Colors.transparent,
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        tabs: [Tab(text: strings['projects']), Tab(text: strings['reviews']), Tab(text: strings['about'])],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProjectsGrid(strings, theme),
                        _buildReviewsList(strings, theme),
                        _buildAboutSection(strings, theme),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      elevation: 0,
      backgroundColor: theme.colorScheme.primary,
      leading: Navigator.canPop(context) ? const BackButton(color: Colors.white) : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.colorScheme.primary, theme.colorScheme.primary.withBlue(220)],
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: -50,
              child: GestureDetector(
                onTap: _isOwnProfile ? _updateProfilePicture : null,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Hero(
                    tag: 'avatar_${widget.userId ?? FirebaseAuth.instance.currentUser?.uid}',
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      backgroundImage: _profileImageUrl.isNotEmpty ? NetworkImage(_profileImageUrl) : null,
                      child: _profileImageUrl.isEmpty ? Icon(Icons.person_rounded, size: 60, color: theme.colorScheme.primary) : null,
                    ),
                  ),
                ),
              ),
            ),
            if (_isOwnProfile)
              Positioned(
                bottom: -50,
                right: -10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(Map<String, String> strings, ThemeData theme) {
    double avgRating = 0;
    if (_userReviews.isNotEmpty) {
      int totalStars = _userReviews.fold(0, (sum, item) => sum + (item['stars'] as int? ?? 0));
      avgRating = totalStars / _userReviews.length;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatItem('124', strings['followers']!, theme),
        _buildVerticalDivider(),
        _buildStatItem('₪ 85', strings['rate']!, theme),
        _buildVerticalDivider(),
        _buildStatItem(avgRating > 0 ? avgRating.toStringAsFixed(1) : '0.0', 'Rating', theme),
      ],
    );
  }

  Widget _buildStatItem(String value, String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() => Container(height: 24, width: 1, color: const Color(0xFFE2E8F0));

  Widget _buildActionButtons(Map<String, String> strings, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircleAction(
            _isFollowing ? Icons.person_remove_rounded : Icons.person_add_rounded,
            _isFollowing ? strings['following']! : strings['follow']!,
            _isFollowing ? const Color(0xFF94A3B8) : theme.colorScheme.primary,
            () => setState(() => _isFollowing = !_isFollowing),
          ),
          _buildCircleAction(Icons.call_rounded, strings['call']!, const Color(0xFF22C55E), () {
            if (_phoneNumber.isNotEmpty) _makePhoneCall(_phoneNumber);
          }),
          _buildCircleAction(Icons.chat_bubble_rounded, strings['message']!, const Color(0xFF6366F1), () {
            if (_phoneNumber.isNotEmpty) _sendSMS(_phoneNumber);
          }),
          _buildCircleAction(Icons.star_rounded, strings['rating_title']!, const Color(0xFFF59E0B), () => _showRateDialog(strings)),
        ],
      ),
    );
  }

  Widget _buildCircleAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildProjectsGrid(Map<String, String> strings, ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _isOwnProfile ? _projects.length + 1 : _projects.length,
      itemBuilder: (context, index) {
        if (_isOwnProfile && index == _projects.length) {
          return InkWell(
            onTap: () => _addProject(strings),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 2, style: BorderStyle.solid),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 32, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(strings['add_project']!, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          );
        }
        final project = _projects[index];
        final imageUrl = project['imageUrl']?.toString() ?? '';
        final projectId = project['id']?.toString() ?? '';
        
        return InkWell(
          onTap: () => _showProjectDetail(index, strings),
          onLongPress: _isOwnProfile ? () => _deleteProject(projectId, imageUrl, strings) : null,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: imageUrl.isNotEmpty 
                      ? Image.network(
                          imageUrl, 
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                        )
                      : const Center(child: Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
                if (project['description'] != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(project['description'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProjectDetail(int index, Map<String, String> strings) {
    final project = _projects[index];
    final imageUrl = project['imageUrl']?.toString() ?? '';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                child: imageUrl.isNotEmpty 
                  ? Image.network(
                      imageUrl, 
                      fit: BoxFit.cover, 
                      width: double.infinity,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) => const SizedBox(height: 200, child: Center(child: Icon(Icons.error, color: Colors.red, size: 50))),
                    )
                  : const SizedBox(height: 200, child: Center(child: Icon(Icons.image, size: 50, color: Colors.grey))),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project['description'] ?? "", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_alt_outlined, color: Color(0xFF1976D2)),
                        const SizedBox(width: 8),
                        Text("${project['likes'] ?? 0} Likes"),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewsList(Map<String, String> strings, ThemeData theme) {
    if (_userReviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rate_review_rounded, size: 64, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(strings['no_reviews']!, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _userReviews.length,
      itemBuilder: (context, index) {
        final review = _userReviews[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(review['reviewerName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Row(
                    children: List.generate(5, (i) => Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: i < (review['stars'] ?? 0) ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(review['comment'] ?? '', style: const TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.5)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAboutSection(Map<String, String> strings, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_isOwnProfile)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfilePage(
                            userData: {
                              'name': _userName,
                              'bio': _bio,
                              'phone': _phoneNumber,
                              'town': _town,
                            },
                          ),
                        ),
                      );
                      if (result == true) _fetchUserData();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(strings['edit_profile']!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ),
              if (_isOwnProfile) const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareProfile(strings),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text(strings['share_profile']!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(strings['contact_info']!, style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          _buildInfoTile(Icons.phone_rounded, _phoneNumber.isNotEmpty ? _phoneNumber : 'N/A', theme),
          _buildInfoTile(Icons.email_rounded, _email.isNotEmpty ? _email : 'N/A', theme),
          _buildInfoTile(Icons.location_on_rounded, _town.isNotEmpty ? _town : 'N/A', theme),
          const SizedBox(height: 32),
          Text(strings['skills']!, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _userProfessions.map((skill) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(skill, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF334155))),
        ],
      ),
    );
  }

  void _showRateDialog(Map<String, String> strings) {
    final currentUser = FirebaseAuth.instance.currentUser;
    Map<String, dynamic>? existingReview;
    if (currentUser != null) {
      // Find current user's review if it exists
      for (var review in _userReviews) {
        if (review['id'] == currentUser.uid) {
          existingReview = review;
          break;
        }
      }
    }

    int selectedStars = existingReview?['stars'] ?? 5;
    final commentController = TextEditingController(text: existingReview?['comment'] ?? "");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(strings['rating_title']!, textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < selectedStars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => selectedStars = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: strings['rating_hint'],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings['cancel']!),
            ),
            ElevatedButton(
              onPressed: () async {
                final currentUser = FirebaseAuth.instance.currentUser;
                final targetUid = widget.userId;
                
                if (currentUser == null || targetUid == null) return;

                try {
                  final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
                    app: FirebaseAuth.instance.app,
                    databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
                  ).ref();

                  // Fetch current user name
                  final nameSnapshot = await dbRef.child('users').child(currentUser.uid).child('name').get();
                  final String reviewerName = nameSnapshot.value?.toString() ?? "Anonymous";

                  final reviewData = {
                    'reviewerName': reviewerName,
                    'stars': selectedStars,
                    'comment': commentController.text,
                    'timestamp': ServerValue.timestamp,
                  };

                  // Use currentUser.uid as the key to limit to one review and allow editing
                  await dbRef.child('reviews').child(targetUid).child(currentUser.uid).set(reviewData);

                  if (context.mounted) {
                    Navigator.pop(context);
                    _fetchUserData(); // Refresh the reviews list
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Review submitted successfully!")),
                    );
                  }
                } catch (e) {
                  debugPrint("REVIEW SUBMIT ERROR: $e");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(strings['submit']!),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }

  Future<void> _sendSMS(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'sms', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) await launchUrl(launchUri);
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: _tabBar);
  }
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
