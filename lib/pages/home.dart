import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/notifications.dart';
import 'package:untitled1/widgets/skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _topRatedWorkers = [];
  bool _isTopRatedLoading = true;
  String? _cachedName;

  @override
  void initState() {
    super.initState();
    _fetchTopRatedWorkers();
    _fetchCurrentUserName();
  }

  Future<void> _fetchCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      if (user.displayName == null || user.displayName!.isEmpty) {
        try {
          final doc = await _firestore.collection('users').doc(user.uid).get();
          if (doc.exists && mounted) {
            setState(() {
              _cachedName = doc.data()?['name']?.toString().split(' ').first;
            });
          }
        } catch (e) {
          debugPrint("Error fetching user name: $e");
        }
      }
    }
  }

  Future<void> _fetchTopRatedWorkers() async {
    if (!mounted) return;
    setState(() => _isTopRatedLoading = true);
    
    try {
      // 1. Try Optimized Query (Requires Index)
      // Note: This excludes anyone without the 'avgRating' field.
      final snapshot = await _firestore.collection('users')
          .where('userType', isEqualTo: 'worker')
          .orderBy('avgRating', descending: true)
          .limit(10)
          .get();
      
      if (snapshot.docs.isEmpty) {
        // 2. Fallback: If no rated workers found, just get any workers
        // This ensures the app isn't empty while you're getting your first reviews.
        await _fetchAnyWorkers();
        return;
      }

      final workers = snapshot.docs.map((doc) {
        var userData = doc.data();
        userData['uid'] = doc.id;
        userData['avgRating'] = (userData['avgRating'] ?? 0.0).toDouble();
        userData['reviewCount'] = userData['reviewCount'] ?? 0;
        return userData;
      }).toList();

      if (mounted) {
        setState(() {
          _topRatedWorkers = workers;
          _isTopRatedLoading = false;
        });
      }
    } catch (e) {
      debugPrint("HOME OPTIMIZED FETCH ERROR (Likely missing index): $e");
      // 3. Fallback on Error: Get any workers if sorting fails
      await _fetchAnyWorkers();
    }
  }

  Future<void> _fetchAnyWorkers() async {
    try {
      final snapshot = await _firestore.collection('users')
          .where('userType', isEqualTo: 'worker')
          .limit(10)
          .get();
      
      final workers = snapshot.docs.map((doc) {
        var userData = doc.data();
        userData['uid'] = doc.id;
        userData['avgRating'] = (userData['avgRating'] ?? 0.0).toDouble();
        userData['reviewCount'] = userData['reviewCount'] ?? 0;
        return userData;
      }).toList();

      if (mounted) {
        setState(() {
          _topRatedWorkers = workers;
          _isTopRatedLoading = false;
        });
      }
    } catch (e) {
      debugPrint("HOME FALLBACK FETCH ERROR: $e");
      if (mounted) setState(() => _isTopRatedLoading = false);
    }
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context, {bool listen = true}) {
    final locale = Provider.of<LanguageProvider>(context, listen: listen).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'שלום,',
          'guest': 'אורח',
          'find_pros': 'איזה שירות דרוש לך היום?',
          'search_hint': 'חפש מקצוען (למשל: אינסטלטור)...',
          'categories': 'קטגוריות פופולריות',
          'see_all': 'הכל',
          'top_rated': 'מקצוענים מובילים בשבילך',
          'view_all': 'ראה עוד',
          'cat_names': {
            'plumber': 'אינסטלציה',
            'Carpenter': 'נגרות',
            'Electrician': 'חשמל',
            'Painter': 'צבע',
            'Cleaner': 'ניקיון',
            'Handyman': 'תיקונים',
            'Landscaper': 'גינון',
            'HVAC': 'מיזוג'
          }
        };
      default:
        return {
          'welcome': 'Hello,',
          'guest': 'Guest',
          'find_pros': 'What service do you need today?',
          'search_hint': 'Search for a pro (e.g. Plumber)...',
          'categories': 'Popular Categories',
          'see_all': 'See all',
          'top_rated': 'Top Rated Professionals',
          'view_all': 'View all',
          'cat_names': {
            'plumber': 'Plumbing',
            'Carpenter': 'Carpentry',
            'Electrician': 'Electrical',
            'Painter': 'Painting',
            'Cleaner': 'Cleaning',
            'Handyman': 'Handyman',
            'Landscaper': 'Landscaping',
            'HVAC': 'HVAC'
          }
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final localized = _getLocalizedStrings(context);
    final theme = Theme.of(context);
    final localeCode = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: RefreshIndicator(
          onRefresh: () async {
            await _fetchTopRatedWorkers();
            await _fetchCurrentUserName();
          },
          child: CustomScrollView(
            slivers: [
              _buildSliverAppBar(localized, theme, user),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategories(context, localized, theme),
                      const SizedBox(height: 8),
                      _buildTopRatedSection(context, localized, theme),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(Map<String, dynamic> strings, ThemeData theme, User? user) {
    String displayName = _cachedName ?? user?.displayName?.split(' ').first ?? strings['guest'];
    
    return SliverAppBar(
      expandedHeight: 250,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1976D2),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 12),
          child: StreamBuilder<QuerySnapshot>(
            stream: (user != null && !user.isAnonymous)
                ? _firestore.collection('users').doc(user.uid).collection('notifications').where('status', isEqualTo: 'pending').snapshots()
                : const Stream.empty(),
            builder: (context, snapshot) {
              int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                    ),
                ],
              );
            }
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -20,
                right: -20,
                child: CircleAvatar(radius: 80, backgroundColor: Colors.white.withOpacity(0.05)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 70, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${strings['welcome']} $displayName',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.waving_hand, color: Colors.amber, size: 18),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings['find_pros'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                  const SizedBox(width: 12),
                  Text(
                    strings['search_hint'],
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context, Map<String, dynamic> strings, ThemeData theme) {
    final catNames = strings['cat_names'] as Map<String, String>;
    final List<Map<String, dynamic>> categories = [
      {'key': 'plumber', 'icon': Icons.plumbing_rounded, 'color': const Color(0xFFDBEAFE), 'iconColor': const Color(0xFF2563EB)},
      {'key': 'Carpenter', 'icon': Icons.handyman_rounded, 'color': const Color(0xFFFFEDD5), 'iconColor': const Color(0xFFEA580C)},
      {'key': 'Electrician', 'icon': Icons.bolt_rounded, 'color': const Color(0xFFFEF9C3), 'iconColor': const Color(0xFFCA8A04)},
      {'key': 'Painter', 'icon': Icons.format_paint_rounded, 'color': const Color(0xFFFCE7F3), 'iconColor': const Color(0xFFDB2777)},
      {'key': 'Cleaner', 'icon': Icons.auto_awesome_rounded, 'color': const Color(0xFFDCFCE7), 'iconColor': const Color(0xFF16A34A)},
      {'key': 'Handyman', 'icon': Icons.architecture_rounded, 'color': const Color(0xFFF3E8FF), 'iconColor': const Color(0xFF9333EA)},
      {'key': 'Landscaper', 'icon': Icons.park_rounded, 'color': const Color(0xFFD1FAE5), 'iconColor': const Color(0xFF059669)},
      {'key': 'HVAC', 'icon': Icons.air_rounded, 'color': const Color(0xFFCFFAFE), 'iconColor': const Color(0xFF0891B2)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['categories'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
                child: Text(strings['see_all'], style: const TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final categoryName = catNames[cat['key']] ?? cat['key'];
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SearchPage(initialTrade: categoryName))),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          color: cat['color'],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(cat['icon'], color: cat['iconColor'], size: 28),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        categoryName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTopRatedSection(BuildContext context, Map<String, dynamic> strings, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['top_rated'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
                child: Text(strings['view_all'], style: const TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: _isTopRatedLoading
            ? ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                itemBuilder: (context, index) => _buildWorkerSkeleton(),
              )
            : _topRatedWorkers.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("No pros found")))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _topRatedWorkers.length,
                  itemBuilder: (context, index) {
                    final worker = _topRatedWorkers[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => Profile(userId: worker['uid']))),
                      child: Container(
                        width: 160,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                              child: (worker['profileImageUrl'] != null && worker['profileImageUrl'].toString().isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: worker['profileImageUrl'],
                                    height: 110,
                                    width: 160,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: const Color(0xFFE2E8F0)),
                                    errorWidget: (context, url, error) => const Icon(Icons.error),
                                  )
                                : Container(height: 110, width: 160, color: const Color(0xFFE2E8F0), child: const Icon(Icons.person, size: 40, color: Colors.white)),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    worker['name'] ?? 'Worker',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (worker['professions'] as List?)?.join(', ') ?? 'Service',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        worker['avgRating'].toStringAsFixed(1),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "(${worker['reviewCount']})",
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWorkerSkeleton() {
    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(height: 110, width: 160, borderRadius: 20),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(height: 16, width: 100),
                const SizedBox(height: 8),
                const Skeleton(height: 12, width: 120),
                const SizedBox(height: 16),
                Row(
                  children: const [
                    Skeleton(height: 16, width: 16, borderRadius: 8),
                    SizedBox(width: 8),
                    Skeleton(height: 14, width: 40),
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
