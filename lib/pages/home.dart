import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/ptofile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instanceFor(
    app: FirebaseAuth.instance.app,
    databaseURL: 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app'
  ).ref();

  List<Map<String, dynamic>> _topRatedWorkers = [];
  bool _isTopRatedLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTopRatedWorkers();
  }

  Future<void> _fetchTopRatedWorkers() async {
    try {
      final usersSnapshot = await _dbRef.child('users').get();
      if (!usersSnapshot.exists) {
        if (mounted) setState(() => _isTopRatedLoading = false);
        return;
      }

      Map<Object?, Object?> allUsers = usersSnapshot.value as Map<Object?, Object?>;
      List<Map<String, dynamic>> workers = [];

      for (var entry in allUsers.entries) {
        var userData = Map<String, dynamic>.from(entry.value as Map);
        if (userData['userType'] == 'worker' && userData['isSubscribed'] == true) {
          userData['uid'] = entry.key;
          workers.add(userData);
        }
      }

      // Calculate ratings
      for (var worker in workers) {
        final reviewsSnapshot = await _dbRef.child('reviews').child(worker['uid']).get();
        double totalStars = 0;
        int reviewCount = 0;

        if (reviewsSnapshot.exists) {
          Map<Object?, Object?> reviews = reviewsSnapshot.value as Map<Object?, Object?>;
          reviewCount = reviews.length;
          reviews.forEach((key, value) {
            final reviewData = Map<String, dynamic>.from(value as Map);
            totalStars += (reviewData['stars'] as num).toDouble();
          });
        }

        worker['avgRating'] = reviewCount > 0 ? totalStars / reviewCount : 0.0;
        worker['reviewCount'] = reviewCount;
      }

      // Sort by avgRating DESC
      workers.sort((a, b) => (b['avgRating'] as double).compareTo(a['avgRating'] as double));
      
      if (mounted) {
        setState(() {
          _topRatedWorkers = workers.take(5).toList();
          _isTopRatedLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching top rated: $e");
      if (mounted) setState(() => _isTopRatedLoading = false);
    }
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'ברוך הבא',
          'find_pros': 'מצא מקצוענים מקומיים',
          'search_hint': 'חפש שירות...',
          'categories': 'קטגוריות',
          'see_all': 'ראה הכל',
          'top_rated': 'הכי מדורגים',
          'view_all': 'צפה בהכל',
          'cat_names': {
            'plumber': 'אינסטלטור',
            'Carpenter': 'נגר',
            'Electrician': 'חשמלאי',
            'Painter': 'צבע',
            'Cleaner': 'מנקה',
            'Handyman': 'שיפוצניק',
            'Landscaper': 'גנן',
            'HVAC': 'מיזוג אוויר'
          }
        };
      case 'ar':
        return {
          'welcome': 'مرحباً بعودتك',
          'find_pros': 'ابحث عن محترفين محليين',
          'search_hint': 'ابحث عن خدمة...',
          'categories': 'الفئات',
          'see_all': 'عرض الكل',
          'top_rated': 'الأعلى تقييماً',
          'view_all': 'عرض الكل',
          'cat_names': {
            'plumber': 'سباك',
            'Carpenter': 'נגר',
            'Electrician': 'كهربائي',
            'Painter': 'دهان',
            'Cleaner': 'عامل نظافة',
            'Handyman': 'عامل صيانة',
            'Landscaper': 'منسق حدائق',
            'HVAC': 'تكييف ותברייد'
          }
        };
      default:
        return {
          'welcome': 'Welcome back',
          'find_pros': 'Find Local Pros',
          'search_hint': 'Search for a service...',
          'categories': 'Categories',
          'see_all': 'See all',
          'top_rated': 'Top Rated',
          'view_all': 'View all',
          'cat_names': {
            'plumber': 'Plumber',
            'Carpenter': 'Carpenter',
            'Electrician': 'Electrician',
            'Painter': 'Painter',
            'Cleaner': 'Cleaner',
            'Handyman': 'Handyman',
            'Landscaper': 'Landscaper',
            'HVAC': 'HVAC'
          }
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final localized = _getLocalizedStrings(context);
    final theme = Theme.of(context);
    final isRtl = Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                  Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: theme.colorScheme.background,
        body: RefreshIndicator(
          onRefresh: _fetchTopRatedWorkers,
          child: CustomScrollView(
            slivers: [
              _buildSliverAppBar(localized, theme),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategories(context, localized, theme),
                    _buildTopRatedSection(context, localized, theme),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(Map<String, dynamic> strings, ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 220,
      floating: false,
      pinned: true,
      backgroundColor: theme.colorScheme.primary,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withBlue(220),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings['welcome'],
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings['find_pros'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: strings['search_hint'],
                      prefixIcon: Icon(Icons.search_rounded, color: theme.colorScheme.primary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context, Map<String, dynamic> strings, ThemeData theme) {
    final catNames = strings['cat_names'] as Map<String, String>;
    final List<Map<String, dynamic>> categories = [
      {'key': 'plumber', 'icon': Icons.plumbing_rounded, 'color': const Color(0xFFEEF2FF), 'iconColor': const Color(0xFF6366F1)},
      {'key': 'Carpenter', 'icon': Icons.handyman_rounded, 'color': const Color(0xFFFFF7ED), 'iconColor': const Color(0xFFF97316)},
      {'key': 'Electrician', 'icon': Icons.bolt_rounded, 'color': const Color(0xFFFEFCE8), 'iconColor': const Color(0xFFEAB308)},
      {'key': 'Painter', 'icon': Icons.format_paint_rounded, 'color': const Color(0xFFFDF2F8), 'iconColor': const Color(0xFFEC4899)},
      {'key': 'Cleaner', 'icon': Icons.auto_awesome_rounded, 'color': const Color(0xFFF0FDF4), 'iconColor': const Color(0xFF22C55E)},
      {'key': 'Handyman', 'icon': Icons.architecture_rounded, 'color': const Color(0xFFF5F3FF), 'iconColor': const Color(0xFF8B5CF6)},
      {'key': 'Landscaper', 'icon': Icons.park_rounded, 'color': const Color(0xFFECFDF5), 'iconColor': const Color(0xFF10B981)},
      {'key': 'HVAC', 'icon': Icons.air_rounded, 'color': const Color(0xFFECFEFF), 'iconColor': const Color(0xFF06B6D4)},
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['categories'],
                style: theme.textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
                child: Text(strings['see_all'], style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 20,
              crossAxisSpacing: 16,
              childAspectRatio: 0.68, // Improved aspect ratio to prevent overflow
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final categoryName = catNames[cat['key']] ?? cat['key'];
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SearchPage(initialTrade: categoryName))),
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cat['color'],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(cat['icon'], color: cat['iconColor'], size: 28),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      categoryName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF475569)),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopRatedSection(BuildContext context, Map<String, dynamic> strings, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['top_rated'],
                style: theme.textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
                child: Text(strings['view_all'], style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (_isTopRatedLoading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_topRatedWorkers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text("No pros found yet.", style: TextStyle(color: Colors.grey[500])),
          )
        else
          SizedBox(
            height: 350,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _topRatedWorkers.length,
              itemBuilder: (context, index) {
                return _buildTopRatedCard(_topRatedWorkers[index], theme);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTopRatedCard(Map<String, dynamic> worker, ThemeData theme) {
    final List<String> placeholderProjects = [
      'https://picsum.photos/300/200?sig=${worker['uid'].hashCode + 1}',
      'https://picsum.photos/300/200?sig=${worker['uid'].hashCode + 2}',
      'https://picsum.photos/300/200?sig=${worker['uid'].hashCode + 3}',
    ];

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => profile(userId: worker['uid']))),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Images Preview
            SizedBox(
              height: 140,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Image.network(
                      placeholderProjects[0],
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            (worker['avgRating'] as double).toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
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
                      Hero(
                        tag: 'avatar_${worker['uid']}',
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(Icons.person_rounded, color: theme.colorScheme.primary, size: 24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker['name'] ?? 'Worker',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              worker['town'] ?? '',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Small project snapshots
                  Row(
                    children: [
                      _buildSmallProjectImg(placeholderProjects[1]),
                      const SizedBox(width: 8),
                      _buildSmallProjectImg(placeholderProjects[2]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(Icons.add_rounded, color: theme.colorScheme.primary, size: 20),
                          ),
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

  Widget _buildSmallProjectImg(String url) {
    return Container(
      width: 60,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
    );
  }
}
