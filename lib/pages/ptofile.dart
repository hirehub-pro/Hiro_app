import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/settings.dart';

class profile extends StatefulWidget {
  const profile({super.key});

  @override
  State<profile> createState() => _profileState();
}

class _profileState extends State<profile> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ImagePicker _picker = ImagePicker();

  final List<Map<String, dynamic>> _projects = [
    {
      'image': 'https://picsum.photos/400/400?sig=1',
      'description': 'Renovation project 1',
      'likes': 12,
      'isLiked': false,
      'comments': ['Great work!', 'Nice colors'],
      'isLocal': false,
    },
    {
      'image': 'https://picsum.photos/400/400?sig=2',
      'description': 'Design update 2',
      'likes': 8,
      'isLiked': false,
      'comments': ['Very clean'],
      'isLocal': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
          'user_name': 'שם משתמש',
          'edit_profile': 'ערוך פרופיל',
          'share_profile': 'שתף פרופיל',
          'followers': 'עוקבים',
          'rate': '₪ לשעה',
          'bio': 'כאן יופיע התיאור האישי שלך...',
          'settings': 'הגדרות',
          'logout': 'התנתקות',
          'projects': 'פרויקטים',
          'reviews': 'ביקורות',
          'about': 'אודות',
          'add_project': 'הוסף פרויקט',
          'description': 'תיאור',
          'take_photo': 'צלם תמונה',
          'pick_gallery': 'בחר מהגלריה',
          'add': 'הוסף',
          'cancel': 'ביטול',
          'comments': 'תגובות',
          'likes': 'לייקים',
          'write_comment': 'כתוב תגובה...',
          'menu': 'תפריט אפשרויות',
        };
      case 'ar':
        return {
          'title': 'الملف الشخصي',
          'user_name': 'اسم المستخدم',
          'edit_profile': 'تعديل الملف الشخصي',
          'share_profile': 'مشاركة الملف الشخصي',
          'followers': 'متابعون',
          'rate': '₪ لكل ساعة',
          'bio': 'هنا سيظهر وصفك الشخصي...',
          'settings': 'الإعدادات',
          'logout': 'تسجيل الخروج',
          'projects': 'المشاريع',
          'reviews': 'المراجعات',
          'about': 'حول',
          'add_project': 'إضافة مشروع',
          'description': 'وصف',
          'image_url': 'رابط الصورة',
          'add': 'إضافة',
          'cancel': 'إلغاء',
          'comments': 'تعليقات',
          'likes': 'إعجابات',
          'write_comment': 'اكتب تعليقاً...',
          'menu': 'قائمة الخيارات',
        };
      default:
        return {
          'title': 'Profile',
          'user_name': 'User Name',
          'edit_profile': 'Edit profile',
          'share_profile': 'Share profile',
          'followers': 'Followers',
          'rate': '₪ per hour',
          'bio': 'Professional service provider with years of experience.',
          'settings': 'Settings',
          'logout': 'Logout',
          'projects': 'Projects',
          'reviews': 'Reviews',
          'about': 'About',
          'add_project': 'Add Project',
          'description': 'Description',
          'take_photo': 'Take Photo',
          'pick_gallery': 'Pick from Gallery',
          'add': 'Add',
          'cancel': 'Cancel',
          'comments': 'Comments',
          'likes': 'Likes',
          'write_comment': 'Write a comment...',
          'menu': 'Menu Options',
        };
    }
  }

  Future<void> _addProject(Map<String, String> strings) async {
    final descController = TextEditingController();
    XFile? pickedFile;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(strings['add_project']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pickedFile != null)
                Image.file(File(pickedFile!.path), height: 100, width: 100, fit: BoxFit.cover),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: () async {
                      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
                      if (photo != null) {
                        setDialogState(() => pickedFile = photo);
                      }
                    },
                    tooltip: strings['take_photo'],
                  ),
                  IconButton(
                    icon: const Icon(Icons.photo_library),
                    onPressed: () async {
                      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setDialogState(() => pickedFile = image);
                      }
                    },
                    tooltip: strings['pick_gallery'],
                  ),
                ],
              ),
              TextField(
                controller: descController,
                decoration: InputDecoration(hintText: strings['description']),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(strings['cancel']!)),
            TextButton(
              onPressed: () {
                if (pickedFile != null) {
                  setState(() {
                    _projects.add({
                      'image': pickedFile!.path,
                      'description': descController.text,
                      'likes': 0,
                      'isLiked': false,
                      'comments': <String>[],
                      'isLocal': true,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: Text(strings['add']!),
            ),
          ],
        ),
      ),
    );
  }

  void _showProjectDetail(int index, Map<String, String> strings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final project = _projects[index];
          final commentController = TextEditingController();

          return DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: InteractiveViewer(
                            child: project['isLocal']
                                ? Image.file(
                                    File(project['image']),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 300,
                                  )
                                : Image.network(
                                    project['image'],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 300,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: CircleAvatar(
                            backgroundColor: Colors.black26,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project['description'],
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  project['isLiked'] ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                                  color: const Color(0xFF1976D2),
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (project['isLiked']) {
                                      project['likes']--;
                                      project['isLiked'] = false;
                                    } else {
                                      project['likes']++;
                                      project['isLiked'] = true;
                                    }
                                  });
                                  setModalState(() {});
                                },
                              ),
                              Text('${project['likes']} ${strings['likes']}'),
                            ],
                          ),
                          const Divider(),
                          Text(
                            strings['comments']!,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ...((project['comments'] as List).map((comment) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(comment),
                              ))),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: commentController,
                                  decoration: InputDecoration(
                                    hintText: strings['write_comment'],
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Color(0xFF1976D2)),
                                onPressed: () {
                                  if (commentController.text.isNotEmpty) {
                                    setState(() {
                                      project['comments'].add(commentController.text);
                                    });
                                    setModalState(() {});
                                    commentController.clear();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.grey[50],
        drawer: _buildDrawer(context, strings, isRtl),
        body: CustomScrollView(
          slivers: [
            _buildAppBar(context, strings, isRtl),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  Text(
                    strings['user_name']!,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsRow(strings),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      strings['bio']!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700], fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF1976D2),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF1976D2),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    Tab(text: strings['projects']),
                    Tab(text: strings['reviews']),
                    Tab(text: strings['about']),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProjectsGrid(strings),
                  _buildReviewsList(),
                  _buildAboutSection(strings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, Map<String, String> strings, bool isRtl) {
    return Drawer(
      child: Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E88E5), Color(0xFF1976D2)],
                  ),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 45, color: Color(0xFF1976D2)),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['user_name']!,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Pro Member',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    _buildDrawerItem(Icons.edit_outlined, strings['edit_profile']!, () {
                      Navigator.pop(context);
                    }),
                    _buildDrawerItem(Icons.share_outlined, strings['share_profile']!, () {
                      Navigator.pop(context);
                    }),
                    _buildDrawerItem(Icons.settings_outlined, strings['settings']!, () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(),
                    ),
                    _buildDrawerItem(Icons.logout, strings['logout']!, () {
                      Navigator.pop(context);
                    }, color: Colors.red),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF1976D2)),
      title: Text(
        title,
        style: TextStyle(color: color ?? Colors.black87, fontWeight: FontWeight.w500, fontSize: 16),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
    );
  }

  Widget _buildAppBar(BuildContext context, Map<String, String> strings, bool isRtl) {
    return SliverAppBar(
      expandedHeight: 180,
      backgroundColor: const Color(0xFF1976D2),
      elevation: 0,
      pinned: true,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white, size: 32),
        onPressed: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E88E5), Color(0xFF1976D2)],
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
              child: CircleAvatar(
                radius: 54,
                backgroundColor: Colors.white,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  child: Icon(Icons.person, size: 60, color: Colors.grey[400]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(Map<String, String> strings) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatItem('124', strings['followers']!),
        _buildVerticalDivider(),
        _buildStatItem('₪ 85', strings['rate']!),
        _buildVerticalDivider(),
        _buildStatItem('4.9', 'Rating'),
      ],
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.grey[300],
    );
  }

  Widget _buildProjectsGrid(Map<String, String> strings) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: _projects.length + 1,
      itemBuilder: (context, index) {
        if (index == _projects.length) {
          return InkWell(
            onTap: () => _addProject(strings),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
              ),
              child: const Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
            ),
          );
        }
        final project = _projects[index];
        return InkWell(
          onTap: () => _showProjectDetail(index, strings),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: project['isLocal']
                        ? Image.file(File(project['image']), fit: BoxFit.cover)
                        : Image.network(project['image'], fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    project['description'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReviewsList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('User Name', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(Icons.star, size: 14, color: i < 4 ? Colors.amber : Colors.grey[300]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Excellent service and very professional.', style: TextStyle(color: Colors.grey[700])),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAboutSection(Map<String, String> strings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Contact Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildInfoTile(Icons.phone, '+972 50 123 4567'),
          _buildInfoTile(Icons.email, 'pro.worker@example.com'),
          _buildInfoTile(Icons.location_on, 'Tel Aviv, Israel'),
          const SizedBox(height: 24),
          const Text('Skills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['Plumbing', 'Electrical', 'Repair'].map((skill) {
              return Chip(label: Text(skill));
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1976D2)),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
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
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
