import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/pages/admin_profile.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/search.dart';
import 'package:untitled1/pages/my_requests_page.dart';
import 'package:untitled1/pages/notifications.dart';
import 'package:untitled1/pages/location_manager_page.dart';
import 'package:untitled1/widgets/skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/services/location_context_service.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomeSessionState {
  static final Set<String> hiddenPopupIds = <String>{};
  static final Set<String> hiddenBannerIds = <String>{};
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _popupSubscription;
  String? _lastPopupId;
  String? _lastPopupSignature;
  final Set<String> _hiddenPopupIds = _HomeSessionState.hiddenPopupIds;
  final Set<String> _hiddenBannerIds = _HomeSessionState.hiddenBannerIds;
  late final PageController _bannerPageController;
  Timer? _bannerAutoScrollTimer;
  int _bannerPageIndex = 0;
  int _bannerCount = 0;

  List<Map<String, dynamic>> _topRatedWorkers = [];
  List<Map<String, dynamic>> _newWorkers = [];
  List<Map<String, dynamic>> _popularCategories = [];
  List<Map<String, dynamic>> _professionItems = [];
  bool _isTopRatedLoading = true;
  bool _isNewWorkersLoading = true;
  bool _isPopularLoading = true;
  String? _cachedName;
  String? _profileImageUrl;
  String _userRole = "customer";
  AppLocation? _currentPosition;

  List<String> _announcementImages(Map<String, dynamic> data) {
    final raw = data['imageUrls'];
    if (raw is List) {
      final urls = raw
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .toList();
      if (urls.isNotEmpty) return urls;
    }

    final single = (data['imageUrl'] ?? '').toString();
    return single.isEmpty ? [] : [single];
  }

  Widget _buildAnnouncementGallery(
    List<String> imageUrls, {
    double height = 220,
    double? thumbnailWidth,
    BorderRadius? borderRadius,
  }) {
    if (imageUrls.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    if (imageUrls.length == 1) {
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: CachedNetworkImage(
          imageUrl: imageUrls.first,
          height: height,
          width: thumbnailWidth ?? double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: imageUrls[index],
            width: thumbnailWidth ?? (height * 1.45),
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  bool _isAnnouncementActive(
    Map<String, dynamic> data, {
    required int fallbackHours,
  }) {
    final startsAt = data['startsAt'] as Timestamp?;
    final expiresAt = data['expiresAt'] as Timestamp?;
    final now = DateTime.now();
    if (startsAt != null && now.isBefore(startsAt.toDate())) {
      return false;
    }
    if (expiresAt != null) {
      return now.isBefore(expiresAt.toDate());
    }

    final timestamp = data['timestamp'] as Timestamp?;
    if (timestamp == null) return false;
    final diff = DateTime.now().difference(timestamp.toDate());
    return diff.inHours < fallbackHours;
  }

  void _onLocationPermissionGranted() {
    if (!mounted) return;
    _reloadAfterPermissionGranted();
  }

  Future<void> _reloadAfterPermissionGranted() async {
    await _getCurrentLocation();
    await _fetchTopRatedWorkers();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _bannerPageController = PageController(initialPage: 1000);
    LocationContextService.locationPermissionGrantedTick.addListener(
      _onLocationPermissionGranted,
    );
    _initData();
    _listenForPopups();
    _startBannerAutoScroll();
  }

  Future<void> _initData() async {
    await _getCurrentLocation();
    await _loadProfessionMetadata();
    _fetchTopRatedWorkers();
    _fetchNewWorkers();
    _fetchCurrentUserName();
    _fetchPopularCategories();
  }

  Future<void> _loadProfessionMetadata() async {
    try {
      final professionsDoc = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final items =
          ((professionsDoc.data()?['items'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

      if (!mounted) return;
      setState(() {
        _professionItems = items;
      });
    } catch (e) {
      debugPrint("Profession metadata load error: $e");
    }
  }

  Map<String, dynamic>? _findProfessionItem(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final item in _professionItems) {
      for (final key in const ['en', 'he', 'ar', 'ru', 'am']) {
        final candidate = item[key]?.toString().trim().toLowerCase();
        if (candidate != null && candidate.isNotEmpty && candidate == normalized) {
          return item;
        }
      }
    }
    return null;
  }

  String _localizedProfessionLabel(String profession, String localeCode) {
    final item = _findProfessionItem(profession);
    if (item == null) return profession;

    final localized = item[localeCode]?.toString().trim();
    if (localized != null && localized.isNotEmpty) {
      return localized;
    }

    final english = item['en']?.toString().trim();
    if (english != null && english.isNotEmpty) {
      return english;
    }

    return profession;
  }

  String _localizedProfessionsText(dynamic professions, String localeCode) {
    final values = (professions as List?)
            ?.map((value) => value?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty)
            .toList() ??
        const <String>[];

    if (values.isEmpty) return 'Service';
    return values
        .map((profession) => _localizedProfessionLabel(profession, localeCode))
        .join(', ');
  }

  Future<void> _getCurrentLocation() async {
    try {
      final location = await LocationContextService.getActiveLocation();
      if (!mounted) return;
      setState(() {
        _currentPosition = location;
      });
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  Future<void> _openLocationManager() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LocationManagerPage()),
    );

    if (changed == true) {
      await _getCurrentLocation();
      await _fetchTopRatedWorkers();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    LocationContextService.locationPermissionGrantedTick.removeListener(
      _onLocationPermissionGranted,
    );
    _popupSubscription?.cancel();
    _bannerAutoScrollTimer?.cancel();
    _bannerPageController.dispose();
    super.dispose();
  }

  void _startBannerAutoScroll() {
    _bannerAutoScrollTimer?.cancel();
    _bannerAutoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _bannerCount <= 1 || !_bannerPageController.hasClients) {
        return;
      }
      final currentPage =
          _bannerPageController.page?.round() ?? _bannerPageController.initialPage;
      _bannerPageController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    });
  }

  void _listenForPopups() {
    _popupSubscription = _firestore
        .collection('system_announcements')
        .where('isPopup', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
          final activeDocs = snapshot.docs.where((doc) {
            if (_hiddenPopupIds.contains(doc.id)) return false;
            final data = doc.data();
            return _isAnnouncementActive(data, fallbackHours: 24);
          }).toList();

          if (activeDocs.isNotEmpty) {
            final signature = activeDocs.map((doc) => doc.id).join('|');
            if (_lastPopupSignature != signature) {
              _lastPopupSignature = signature;
              _lastPopupId = activeDocs.first.id;
              _showAdPopup(activeDocs);
            }
          }
        });
  }

  void _showAdPopup(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> popupDocs,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final adPageController = PageController();
        var currentAdIndex = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Container(
                color: Colors.white,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.96,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: SingleChildScrollView(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.82,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: PageView.builder(
                            controller: adPageController,
                            itemCount: popupDocs.length,
                            onPageChanged: (index) {
                              setDialogState(() => currentAdIndex = index);
                            },
                            itemBuilder: (context, adIndex) {
                              final doc = popupDocs[adIndex];
                              final data = doc.data();
                              final imageUrls = _announcementImages(data);
                              final adId = doc.id;

                              return SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        _buildAnnouncementGallery(
                                          imageUrls,
                                          height: imageUrls.isEmpty ? 260 : 400,
                                        ),
                                        Positioned(
                                          top: 16,
                                          left: 16,
                                          right: 16,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if ((data['badge'] ?? '')
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    data['badge'].toString(),
                                                    style: const TextStyle(
                                                      color: Color(0xFF1D4ED8),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              const Spacer(),
                                              CircleAvatar(
                                                backgroundColor: Colors.black
                                                    .withValues(alpha: 0.45),
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    color: Colors.white,
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _hiddenPopupIds.add(adId);
                                                    });
                                                    Navigator.pop(context);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        22,
                                        24,
                                        20,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFEFF6FF,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                ),
                                                child: const Text(
                                                  'System Promotion',
                                                  style: TextStyle(
                                                    color: Color(0xFF1D4ED8),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              if (popupDocs.length > 1)
                                                Text(
                                                  '${adIndex + 1}/${popupDocs.length}',
                                                  style: const TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            data['title'] ?? 'Announcement',
                                            style: const TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.bold,
                                              height: 1.06,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            data['message'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 17,
                                              color: Color(0xFF475569),
                                              height: 1.45,
                                            ),
                                          ),
                                          if (popupDocs.length > 1) ...[
                                            const SizedBox(height: 14),
                                            const Text(
                                              'Swipe left or right to see more ads',
                                              style: TextStyle(
                                                color: Color(0xFF64748B),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          if (imageUrls.length > 1) ...[
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              height: 86,
                                              child: ListView.separated(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: imageUrls.length,
                                                separatorBuilder: (_, __) =>
                                                    const SizedBox(width: 8),
                                                itemBuilder: (context, index) =>
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      child: CachedNetworkImage(
                                                        imageUrl:
                                                            imageUrls[index],
                                                        width: 110,
                                                        height: 86,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 24),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 14,
                                                            ),
                                                      ),
                                                  onPressed: () {
                                                    setState(
                                                      () =>
                                                          _hiddenPopupIds.add(
                                                            adId,
                                                          ),
                                                    );
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text('Not Now'),
                                                ),
                                              ),
                                              if (data['link'] != null &&
                                                  data['link']
                                                      .toString()
                                                      .isNotEmpty) ...[
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              const Color(
                                                                0xFF1D4ED8,
                                                              ),
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 14,
                                                              ),
                                                        ),
                                                    onPressed: () async {
                                                      final url = Uri.parse(
                                                        data['link'],
                                                      );
                                                      if (await canLaunchUrl(
                                                        url,
                                                      )) {
                                                        await launchUrl(url);
                                                      }
                                                      if (context.mounted) {
                                                        Navigator.pop(context);
                                                      }
                                                    },
                                                    icon: const Icon(
                                                      Icons.arrow_outward_rounded,
                                                    ),
                                                    label: Text(
                                                      data['buttonText'] ??
                                                          'Learn More',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        if (popupDocs.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                popupDocs.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: currentAdIndex == index ? 22 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: currentAdIndex == index
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFFCBD5E1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            _cachedName = doc.data()?['name']?.toString().split(' ').first;
            _profileImageUrl = doc.data()?['profileImageUrl']?.toString();
            _userRole = doc.data()?['role'] ?? 'customer';
          });
        }
      } catch (e) {
        debugPrint("Error fetching user data: $e");
      }
    }
  }

  Future<void> _fetchPopularCategories() async {
    if (!mounted) return;
    setState(() => _isPopularLoading = true);

    try {
      final professionsDoc = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final List<Map<String, dynamic>> allProfs =
          ((professionsDoc.data()?['items'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      if (mounted && _professionItems.isEmpty) {
        _professionItems = allProfs;
      }

      List<Map<String, dynamic>> popular = [];

      try {
        final snapshot = await _firestore
            .collection('metadata')
            .doc('analytics')
            .collection('professions')
            .orderBy('searchCount', descending: true)
            .limit(8)
            .get();

        if (snapshot.docs.isNotEmpty) {
          for (var doc in snapshot.docs) {
            final enName = doc.id;
            final profDetails = allProfs
                .cast<Map<String, dynamic>?>()
                .firstWhere(
                  (p) =>
                      p?['en'].toString().toLowerCase() == enName.toLowerCase(),
                  orElse: () => null,
                );
            if (profDetails != null) {
              popular.add(profDetails);
            }
          }
        }
      } catch (firestoreError) {
        debugPrint(
          "Firestore analytics fetch failed (using defaults): $firestoreError",
        );
      }

      if (popular.isEmpty) {
        final defaults = [
          'Plumber',
          'Electrician',
          'Carpenter',
          'Painter',
          'AC Technician',
          'Handyman',
          'Gardener',
          'Cleaner',
        ];
        for (var name in defaults) {
          final matches = allProfs.where((p) => p['en'] == name);
          if (matches.isNotEmpty) {
            popular.add(matches.first);
          }
        }
      }

      if (popular.isEmpty && allProfs.isNotEmpty) {
        popular = allProfs.take(8).toList();
      }

      if (mounted) {
        setState(() {
          _popularCategories = popular;
          _isPopularLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Popular categories critical error: $e");
      if (mounted) setState(() => _isPopularLoading = false);
    }
  }

  Future<void> _fetchTopRatedWorkers() async {
    if (!mounted) return;
    setState(() => _isTopRatedLoading = true);

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'worker')
          .orderBy('avgRating', descending: true)
          .limit(30) // Fetch more to filter locally
          .get();

      final workers = snapshot.docs
          .map((doc) {
            var userData = doc.data();
            userData['uid'] = doc.id;
            userData['avgRating'] = (userData['avgRating'] ?? 0.0).toDouble();
            userData['reviewCount'] = userData['reviewCount'] ?? 0;
            return userData;
          })
          .where(SubscriptionAccessService.hasActiveWorkerSubscriptionFromData)
          .toList();

      final filtered = _filterByProximity(workers);

      if (mounted) {
        setState(() {
          _topRatedWorkers = filtered.take(10).toList();
          _isTopRatedLoading = false;
        });
      }
    } catch (e) {
      debugPrint("HOME OPTIMIZED FETCH ERROR: $e");
      if (mounted) setState(() => _isTopRatedLoading = false);
    }
  }

  List<Map<String, dynamic>> _filterByProximity(
    List<Map<String, dynamic>> workers,
  ) {
    if (_currentPosition == null) return workers;

    return workers.where((w) {
      if (w['lat'] == null || w['lng'] == null) return false;

      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        w['lat'].toDouble(),
        w['lng'].toDouble(),
      );

      double radiusInKm = (w['serviceRadius'] ?? 20.0).toDouble();
      return (distanceInMeters / 1000) <= radiusInKm;
    }).toList();
  }

  Future<void> _fetchNewWorkers() async {
    if (!mounted) return;
    setState(() => _isNewWorkersLoading = true);

    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'worker')
          .orderBy('createdAt', descending: true)
          .limit(7)
          .get();

      final workers = snapshot.docs
          .map((doc) {
            var userData = doc.data();
            userData['uid'] = doc.id;
            userData['avgRating'] = (userData['avgRating'] ?? 0.0).toDouble();
            userData['reviewCount'] = userData['reviewCount'] ?? 0;
            return userData;
          })
          .where(SubscriptionAccessService.hasActiveWorkerSubscriptionFromData)
          .toList();

      if (mounted) {
        setState(() {
          _newWorkers = workers;
          _isNewWorkersLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Fetch new workers error: $e");
      if (mounted) setState(() => _isNewWorkersLoading = false);
    }
  }

  Map<String, dynamic> _getLocalizedStrings(
    BuildContext context, {
    bool listen = true,
  }) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: listen,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'שלום,',
          'guest': 'אורח',
          'find_pros': 'איזה שירות דרוש לך היום?',
          'search_hint': 'חפש מקצוען (למשל: אינסטלטור)...',
          'categories': 'קטגוריות פופולריות',
          'see_all': 'הכל',
          'top_rated': 'מקצוענים מובילך בשבילך',
          'new_team': 'חדש בצוות הירו',
          'view_all': 'ראה עוד',
          'broadcast_title': 'הודעת מערכת',
          'my_requests': 'הבקשות שלי',
          'new_tag': 'חדש',
          'no_reviews': 'אין ביקורות',
        };
      case 'ar':
        return {
          'welcome': 'مرحباً،',
          'guest': 'ضيف',
          'find_pros': 'ما هي الخدمة التي تحتاجها اليوم؟',
          'search_hint': 'ابحث عن محترف (مثلاً: سباك)...',
          'categories': 'الفئات الشائعة',
          'see_all': 'الكل',
          'top_rated': 'المحترفون الأعلى تقييماً',
          'new_team': 'جديد في فريق هايرو',
          'view_all': 'عرض الكل',
          'broadcast_title': 'بلاغ النظام',
          'my_requests': 'طلباتي',
          'new_tag': 'جديد',
          'no_reviews': 'لا توجد تقييمات',
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
          'new_team': 'New to hiro Team',
          'view_all': 'View all',
          'broadcast_title': 'System Broadcast',
          'my_requests': 'My Requests',
          'new_tag': 'NEW',
          'no_reviews': 'No reviews',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final localized = _getLocalizedStrings(context);
    final theme = Theme.of(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: RefreshIndicator(
          onRefresh: () async {
            await _initData();
          },
          child: CustomScrollView(
            slivers: [
              _buildSliverAppBar(localized, theme, user),
              _buildBroadcastBanner(localized),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCategories(context, localized, theme),
                      const SizedBox(height: 8),
                      _buildNewToTeamSection(context, localized, theme),
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

  Widget _buildBroadcastBanner(Map<String, dynamic> strings) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('system_announcements')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final showBanner = data['showBanner'] != false;
          if (!showBanner || _hiddenBannerIds.contains(doc.id)) return false;
          return _isAnnouncementActive(data, fallbackHours: 48);
        }).toList();

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _bannerCount == docs.length) return;
          setState(() {
            _bannerCount = docs.length;
            _bannerPageIndex = _bannerPageIndex % docs.length;
          });
        });

        return SliverToBoxAdapter(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                height: 210,
                child: PageView.builder(
                  controller: _bannerPageController,
                  onPageChanged: (index) {
                    if (!mounted) return;
                    setState(() => _bannerPageIndex = index % docs.length);
                  },
                  itemBuilder: (context, index) {
                    final doc = docs[index % docs.length];
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final imageUrls = _announcementImages(data);

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1D4ED8).withValues(alpha: 0.28),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            if ((data['badge'] ?? '')
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(
                                                    alpha: 0.14,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  data['badge'].toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            const Spacer(),
                                            if (docs.length > 1)
                                              Text(
                                                '${(index % docs.length) + 1}/${docs.length}',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(
                                                    alpha: 0.78,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                          ],
                                        ),
                                        if ((data['badge'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty)
                                          const SizedBox(height: 12),
                                        Text(
                                          data['title'] ??
                                              strings['broadcast_title'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          data['message'] ?? '',
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.88,
                                            ),
                                            fontSize: 14,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (imageUrls.isNotEmpty)
                                    SizedBox(
                                      width: 140,
                                      height: 140,
                                      child: _buildAnnouncementGallery(
                                        imageUrls,
                                        height: 140,
                                        thumbnailWidth: 140,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _hiddenBannerIds.add(docId),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  if (docs.length > 1)
                                    Text(
                                      'Swipe for more',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.74,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  const Spacer(),
                                  if (data['link'] != null &&
                                      data['link'].toString().isNotEmpty)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor:
                                            const Color(0xFF0F172A),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      onPressed: () async {
                                        final url = Uri.parse(data['link']);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url);
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.arrow_outward_rounded,
                                      ),
                                      label: Text(
                                        data['buttonText'] ?? 'Learn More',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (docs.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    docs.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _bannerPageIndex == index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _bannerPageIndex == index
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSliverAppBar(
    Map<String, dynamic> strings,
    ThemeData theme,
    User? user,
  ) {
    String displayName =
        _cachedName ?? user?.displayName?.split(' ').first ?? strings['guest'];

    return SliverAppBar(
      expandedHeight: 250,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1976D2),
      actions: [
        IconButton(
          icon: const Icon(Icons.place_outlined, color: Colors.white),
          onPressed: _openLocationManager,
        ),
        IconButton(
          tooltip: strings['my_requests'],
          icon: const Icon(Icons.list_alt_rounded, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyRequestsPage()),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 12),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: (user != null && !user.isAnonymous)
                ? _firestore
                      .collection('users')
                      .doc(user.uid)
                      .collection('notifications')
                      .snapshots()
                : const Stream.empty(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const [];
              final count = docs.where((doc) {
                final data = doc.data();
                final type = (data['type'] ?? '').toString();
                final status = (data['status'] ?? '').toString().toLowerCase();
                final isUnreadResponse =
                    (type == 'request_accepted' ||
                        type == 'request_declined' ||
                        type == 'quote_response') &&
                    data['isRead'] == false;
                final isPendingRequest = status == 'pending';
                return isUnreadResponse || isPendingRequest;
              }).length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsPage(),
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
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
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.white.withOpacity(0.05),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 70, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_userRole == 'admin') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminProfile(),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const Profile(),
                                ),
                              );
                            }
                          },
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            backgroundImage:
                                (_profileImageUrl != null &&
                                    _profileImageUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(_profileImageUrl!)
                                : null,
                            child:
                                (_profileImageUrl == null ||
                                    _profileImageUrl!.isEmpty)
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${strings['welcome']} $displayName',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.waving_hand,
                          color: Colors.amber,
                          size: 18,
                        ),
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchPage()),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                  const SizedBox(width: 12),
                  Text(
                    strings['search_hint'],
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(
    BuildContext context,
    Map<String, dynamic> strings,
    ThemeData theme,
  ) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;

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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchPage()),
                ),
                child: Text(
                  strings['see_all'],
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: _isPopularLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  itemBuilder: (context, index) => _buildCategorySkeleton(),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _popularCategories.length,
                  itemBuilder: (context, index) {
                    final cat = _popularCategories[index];
                    final displayName = cat[locale] ?? cat['en'];
                    final colorHex = cat['color'] ?? "#1E3A8A";
                    final color = _getColorFromHex(colorHex);

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SearchPage(initialTrade: cat['en']),
                        ),
                      ),
                      child: Container(
                        width: 85,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            Container(
                              height: 64,
                              width: 64,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                _getIcon(cat['logo']),
                                color: color,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

  Widget _buildTopRatedSection(
    BuildContext context,
    Map<String, dynamic> strings,
    ThemeData theme,
  ) {
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchPage()),
                ),
                child: Text(
                  strings['view_all'],
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text("No pros found nearby"),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _topRatedWorkers.length,
                  itemBuilder: (context, index) {
                    final worker = _topRatedWorkers[index];
                    return _buildWorkerCard(worker, null, strings);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNewToTeamSection(
    BuildContext context,
    Map<String, dynamic> strings,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            strings['new_team'],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        SizedBox(
          height: 220,
          child: _isNewWorkersLoading
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  itemBuilder: (context, index) => _buildWorkerSkeleton(),
                )
              : _newWorkers.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _newWorkers.length,
                  itemBuilder: (context, index) {
                    final worker = _newWorkers[index];
                    final createdAt = worker['createdAt'] as Timestamp?;
                    bool isNew = false;
                    if (createdAt != null) {
                      final diff = DateTime.now().difference(
                        createdAt.toDate(),
                      );
                      isNew = diff.inDays <= 7;
                    }

                    return _buildWorkerCard(
                      worker,
                      isNew ? strings['new_tag'] : null,
                      strings,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWorkerCard(
    Map<String, dynamic> worker,
    String? tag,
    Map<String, dynamic> strings,
  ) {
    return GestureDetector(
      onTap: () {
        if (worker['role'] == 'admin') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminProfile()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Profile(userId: worker['uid']),
            ),
          );
        }
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child:
                      (worker['profileImageUrl'] != null &&
                          worker['profileImageUrl'].toString().isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: worker['profileImageUrl'],
                          height: 110,
                          width: 160,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: const Color(0xFFE2E8F0)),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        )
                      : Container(
                          height: 110,
                          width: 160,
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker['name'] ?? 'Worker',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localizedProfessionsText(
                          worker['professions'],
                          Provider.of<LanguageProvider>(
                            context,
                            listen: false,
                          ).locale.languageCode,
                        ),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if ((worker['reviewCount'] ?? 0) > 0) ...[
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              worker['avgRating'].toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "(${worker['reviewCount']})",
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                          ] else ...[
                            Text(
                              strings['no_reviews'],
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (tag != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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

  Widget _buildCategorySkeleton() {
    return Container(
      width: 85,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: const [
          Skeleton(height: 64, width: 64, borderRadius: 20),
          SizedBox(height: 8),
          Skeleton(height: 12, width: 60),
        ],
      ),
    );
  }

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1E3A8A);
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  IconData _getIcon(String? name) {
    switch (name) {
      case 'plumbing':
        return Icons.plumbing;
      case 'electrical_services':
        return Icons.electrical_services;
      case 'carpenter':
        return Icons.carpenter;
      case 'format_paint':
        return Icons.format_paint;
      case 'vpn_key':
        return Icons.vpn_key;
      case 'park':
        return Icons.park;
      case 'ac_unit':
        return Icons.ac_unit;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'build':
        return Icons.build;
      case 'handyman':
        return Icons.handyman;
      case 'foundation':
        return Icons.foundation;
      case 'grid_view':
        return Icons.grid_view;
      case 'settings':
        return Icons.settings;
      case 'home_repair_service':
        return Icons.home_repair_service;
      case 'computer':
        return Icons.computer;
      case 'content_cut':
        return Icons.content_cut;
      case 'checkroom':
        return Icons.checkroom;
      case 'local_shipping':
        return Icons.local_shipping;
      case 'pest_control':
        return Icons.pest_control;
      case 'solar_power':
        return Icons.solar_power;
      case 'chair':
        return Icons.chair;
      case 'format_shapes':
        return Icons.format_shapes;
      case 'architecture':
        return Icons.architecture;
      case 'school':
        return Icons.school;
      case 'child_care':
        return Icons.child_care;
      case 'photo_camera':
        return Icons.photo_camera;
      case 'music_note':
        return Icons.music_note;
      case 'face':
        return Icons.face;
      case 'medical_services':
        return Icons.medical_services;
      case 'self_improvement':
        return Icons.self_improvement;
      case 'window':
        return Icons.window;
      case 'pool':
        return Icons.pool;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'pets':
        return Icons.pets;
      case 'home':
        return Icons.home;
      case 'waves':
        return Icons.waves;
      case 'dry_cleaning':
        return Icons.dry_cleaning;
      case 'event':
        return Icons.event;
      case 'restaurant':
        return Icons.restaurant;
      case 'security':
        return Icons.security;
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'local_car_wash':
        return Icons.local_car_wash;
      case 'spa':
        return Icons.spa;
      case 'restaurant_menu':
        return Icons.restaurant_menu;
      case 'flight':
        return Icons.flight;
      case 'real_estate_agent':
        return Icons.real_estate_agent;
      case 'gavel':
        return Icons.gavel;
      case 'calculate':
        return Icons.calculate;
      case 'translate':
        return Icons.translate;
      case 'format_color_fill':
        return Icons.format_color_fill;
      case 'square_foot':
        return Icons.square_foot;
      case 'videocam':
        return Icons.videocam;
      case 'public':
        return Icons.public;
      case 'psychology':
        return Icons.psychology;
      case 'add_a_photo':
        return Icons.add_a_photo;
      case 'flight_takeoff':
        return Icons.flight_takeoff;
      case 'piano':
        return Icons.piano;
      case 'language':
        return Icons.language;
      case 'functions':
        return Icons.functions;
      case 'science':
        return Icons.science;
      case 'biotech':
        return Icons.biotech;
      case 'eco':
        return Icons.eco;
      case 'history_edu':
        return Icons.history_edu;
      case 'palette':
        return Icons.palette;
      case 'pedal_bike':
        return Icons.pedal_bike;
      case 'engineering':
        return Icons.engineering;
      default:
        return Icons.work_rounded;
    }
  }
}
