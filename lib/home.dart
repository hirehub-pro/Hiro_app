import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/pages/admin_profile.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/search.dart';
import 'package:untitled1/pages/my_requests_page.dart';
import 'package:untitled1/pages/my_request_details_page.dart';
import 'package:untitled1/pages/request_details.dart';
import 'package:untitled1/pages/notifications.dart';
import 'package:untitled1/pages/location_manager_page.dart';
import 'package:untitled1/pages/subscription.dart';
import 'package:untitled1/widgets/skeleton.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
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
  int _requestSwipeIndex = 0;
  int _requestTransitionDirection = 1;
  bool _showRequestsSentToMe = false;

  List<Map<String, dynamic>> _popularCategories = [];
  List<Map<String, dynamic>> _professionItems = [];
  bool _isPopularLoading = true;
  String? _cachedName;
  String? _profileImageUrl;
  String _userRole = "customer";
  String _subscriptionStatus = "inactive";

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

  @override
  void initState() {
    super.initState();
    _bannerPageController = PageController(initialPage: 1000);
    _initData();
    _listenForPopups();
    _startBannerAutoScroll();
  }

  Future<void> _initData() async {
    final professionLoad = _loadProfessionMetadata();
    _fetchCurrentUserName();
    await professionLoad;
    _fetchPopularCategories();
  }

  Future<void> _loadProfessionMetadata() async {
    try {
      final professionsDoc = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final items = ((professionsDoc.data()?['items'] as List?) ?? const [])
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

  Future<void> _openLocationManager() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LocationManagerPage()),
    );

    if (changed == true) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
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
          _bannerPageController.page?.round() ??
          _bannerPageController.initialPage;
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
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
            ),
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
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
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
                                                  style: OutlinedButton.styleFrom(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 14,
                                                        ),
                                                  ),
                                                  onPressed: () {
                                                    setState(
                                                      () => _hiddenPopupIds.add(
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
                                                    style: ElevatedButton.styleFrom(
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
                                                      Icons
                                                          .arrow_outward_rounded,
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
            _subscriptionStatus =
                doc.data()?['subscriptionStatus']?.toString().toLowerCase() ??
                'inactive';
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
      var allProfs = _professionItems;
      if (allProfs.isEmpty) {
        await _loadProfessionMetadata();
        allProfs = _professionItems;
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
          'latest_request': 'הבקשה האחרונה',
          'view_all': 'הכל',
          'request_someone_else': 'בקש ממישהו אחר',
          'project_ideas_title': 'איזו עבודה אתה צריך?',
          'project_ideas_subtitle':
              'בחר לפי הבעיה או סוג הפרויקט וקבל כיוון מהיר',
          'project_ideas_hint':
              'בעיות דחופות, שיפוצים ורעיונות לפרויקט במקום אחד',
          'project_ideas_cta': 'צפה באפשרויות',
          'project_find_pros': 'מצא בעלי מקצוע',
          'project_example': 'דוגמאות',
          'project_problem_badge': 'בעיה',
          'project_project_badge': 'פרויקט',
          'project_trade_plumber': 'אינסטלטור',
          'project_trade_electrician': 'חשמלאי',
          'project_trade_painter': 'צבעי',
          'project_trade_handyman': 'הנדימן',
          'project_trade_gardener': 'גנן',
          'project_trade_ac': 'טכנאי מזגנים',
          'project_trade_mover': 'מוביל',
          'project_roof_title': 'בניית או תיקון גג',
          'project_roof_subtitle': 'בדוק סוגי גגות לפני שאתה בוחר בעל מקצוע',
          'project_leak_title': 'נזילת מים',
          'project_leak_subtitle': 'צריך אינסטלטור לאיתור ותיקון מהיר',
          'project_power_title': 'בעיית חשמל',
          'project_power_subtitle': 'שקעים, עומס או קצר? מצא חשמלאי',
          'project_drain_title': 'סתימה או ריח מהניקוז',
          'project_drain_subtitle': 'לכיורים, מקלחות וניקוז שדורשים טיפול מהיר',
          'project_ac_title': 'המזגן לא מקרר',
          'project_ac_subtitle': 'בדיקה, ניקוי או תיקון לפני שהחום מחמיר',
          'project_paint_title': 'צביעת הבית',
          'project_paint_subtitle': 'צביעה פנימית, חיצונית או חידוש קירות',
          'project_bathroom_title': 'שיפוץ חדר רחצה',
          'project_bathroom_subtitle': 'ריצוף, כלים סניטריים, איטום וחידוש מלא',
          'project_garden_title': 'עבודות גינה',
          'project_garden_subtitle': 'דשא, גיזום, השקיה ועיצוב חוץ',
          'project_cracks_title': 'סדקים בקיר',
          'project_cracks_subtitle':
              'בדיקה, תיקון וטיח לקירות פנימיים או חיצוניים',
          'project_move_title': 'עוברים דירה',
          'project_move_subtitle': 'הובלה, פירוק והרכבה לבית או למשרד',
          'roof_options_title': 'אפשרויות לגג',
          'roof_options_subtitle':
              'בחר סגנון כדי לראות דוגמאות ולהמשיך לבעלי מקצוע',
          'roof_tile_title': 'גג רעפים',
          'roof_tile_subtitle': 'מראה קלאסי עם בידוד טוב לבית פרטי',
          'roof_wood_title': 'גג עץ',
          'roof_wood_subtitle': 'מראה חם וטבעי לפרגולות ומבנים מיוחדים',
          'roof_panel_title': 'גג פנלים',
          'roof_panel_subtitle': 'פתרון מהיר, נקי ומודרני למבנים שונים',
          'roof_metal_title': 'גג מתכת',
          'roof_metal_subtitle': 'עמיד וחזק למחסנים, חניות ומבנים תעשייתיים',
          'maintenance_title': 'רשימת תחזוקת הבית',
          'maintenance_subtitle':
              'בדיקות פשוטות שכדאי לעשות לפני שהבעיה מתייקרת',
          'seasonal_pick': 'בחירה עונתית',
          'maintenance_cta': 'מצא בעל מקצוע',
          'maintenance_hint': '6 בדיקות חכמות ששווה לעשות בבית',
          'maintenance_item_1_title': 'ניקוי מסנני מזגן',
          'maintenance_item_1_subtitle': 'לשיפור הקירור ואיכות האוויר בבית',
          'maintenance_item_1_trade': 'טכנאי מזגנים',
          'maintenance_item_2_title': 'בדיקת דוד מים',
          'maintenance_item_2_subtitle': 'למניעת נזילות וחימום חלש',
          'maintenance_item_2_trade': 'אינסטלטור',
          'maintenance_item_3_title': 'בדיקת בטיחות חשמל',
          'maintenance_item_3_subtitle': 'לבדיקת שקעים, עומסים וחיבורים',
          'maintenance_item_3_trade': 'חשמלאי',
          'maintenance_item_4_title': 'ניקוי יסודי לבית',
          'maintenance_item_4_subtitle': 'מעולה לפני חגים, מעבר או אירוח',
          'maintenance_item_4_trade': 'מנקה',
          'maintenance_item_5_title': 'איטום חלונות ומרפסות',
          'maintenance_item_5_subtitle': 'למניעת חדירת מים ורוח בעונות מעבר',
          'maintenance_item_5_trade': 'איש איטום',
          'maintenance_item_6_title': 'גיזום וניקוי גינה',
          'maintenance_item_6_subtitle': 'שומר על החוץ מסודר ובטוח כל השנה',
          'maintenance_item_6_trade': 'גנן',
          'no_active_requests': 'עדיין אין בקשות פעילות',
          'request_sent': 'נשלח',
          'request_pending': 'ממתין לבדיקה',
          'request_reviewed': 'נבדק',
          'request_accepted': 'אושר',
          'request_scheduled': 'נקבע',
          'request_declined': 'נדחה',
          'request_cancelled': 'בוטל',
          'request_swipe_hint': 'החלק ימינה/שמאלה כדי לעבור בין בקשות',
          'requests_to_me': 'בקשות אליי',
          'latest_request_to_me': 'הבקשות שנשלחו אליי',
          'no_incoming_requests': 'אין בקשות חדשות שנשלחו אליך',
          'categories': 'קטגוריות פופולריות',
          'see_all': 'הכל',
          'broadcast_title': 'הודעת מערכת',
          'my_requests': 'הבקשות שלי',
          'subscribe_cta_title': 'הפעלת מנוי Pro',
          'subscribe_cta_subtitle':
              'כדי לפתוח את כל הכלים המקצועיים ולקבל יותר פניות, הפעל מנוי Pro.',
          'subscribe_cta_button': 'מעבר למנוי',
        };
      case 'ar':
        return {
          'welcome': 'مرحباً،',
          'guest': 'ضيف',
          'find_pros': 'ما هي الخدمة التي تحتاجها اليوم؟',
          'search_hint': 'ابحث عن محترف (مثلاً: سباك)...',
          'latest_request': 'أحدث طلب',
          'view_all': 'عرض الكل',
          'request_someone_else': 'اطلب من شخص آخر',
          'project_ideas_title': 'ما هو العمل الذي تحتاجه؟',
          'project_ideas_subtitle':
              'اختر حسب المشكلة أو نوع المشروع واحصل على بداية سريعة',
          'project_ideas_hint':
              'مشاكل عاجلة وتجديدات وأفكار مشاريع في مكان واحد',
          'project_ideas_cta': 'عرض الخيارات',
          'project_find_pros': 'اعثر على محترفين',
          'project_example': 'أمثلة',
          'project_problem_badge': 'مشكلة',
          'project_project_badge': 'مشروع',
          'project_trade_plumber': 'سباك',
          'project_trade_electrician': 'كهربائي',
          'project_trade_painter': 'دهان',
          'project_trade_handyman': 'فني متعدد المهام',
          'project_trade_gardener': 'بستاني',
          'project_trade_ac': 'فني تكييف',
          'project_trade_mover': 'نقّال',
          'project_roof_title': 'بناء أو إصلاح سقف',
          'project_roof_subtitle': 'تعرّف على أنواع الأسقف قبل اختيار المحترف',
          'project_leak_title': 'تسرّب مياه',
          'project_leak_subtitle': 'تحتاج سباكاً للكشف والإصلاح السريع',
          'project_power_title': 'مشكلة كهرباء',
          'project_power_subtitle':
              'مقبس أو حمل زائد أو تماس؟ اعثر على كهربائي',
          'project_drain_title': 'انسداد أو رائحة من المصرف',
          'project_drain_subtitle':
              'للمغاسل والحمامات والتصريف الذي يحتاج معالجة سريعة',
          'project_ac_title': 'المكيف لا يبرّد',
          'project_ac_subtitle': 'فحص أو تنظيف أو إصلاح قبل اشتداد الحر',
          'project_paint_title': 'دهان المنزل',
          'project_paint_subtitle': 'دهان داخلي أو خارجي أو تجديد الجدران',
          'project_bathroom_title': 'تجديد الحمام',
          'project_bathroom_subtitle': 'بلاط وأدوات صحية وعزل وتجديد كامل',
          'project_garden_title': 'أعمال الحديقة',
          'project_garden_subtitle': 'عشب وتشذيب وري وتصميم خارجي',
          'project_cracks_title': 'تشققات في الجدار',
          'project_cracks_subtitle':
              'فحص وإصلاح وطرطشة للجدران الداخلية أو الخارجية',
          'project_move_title': 'الانتقال إلى منزل جديد',
          'project_move_subtitle': 'نقل وفك وتركيب للمنزل أو المكتب',
          'roof_options_title': 'خيارات السقف',
          'roof_options_subtitle':
              'اختر النمط لرؤية أمثلة ثم تابع إلى المحترفين',
          'roof_tile_title': 'سقف قرميد',
          'roof_tile_subtitle': 'مظهر كلاسيكي مع عزل جيد للمنازل',
          'roof_wood_title': 'سقف خشبي',
          'roof_wood_subtitle': 'مظهر دافئ وطبيعي للبرجولات والمباني المميزة',
          'roof_panel_title': 'سقف ألواح',
          'roof_panel_subtitle': 'حل سريع وحديث ونظيف لمشاريع متعددة',
          'roof_metal_title': 'سقف معدني',
          'roof_metal_subtitle': 'متين وقوي للمخازن والمواقف والمباني الصناعية',
          'maintenance_title': 'قائمة صيانة المنزل',
          'maintenance_subtitle': 'فحوصات بسيطة قبل أن تصبح المشكلة أكثر كلفة',
          'seasonal_pick': 'اختيار موسمي',
          'maintenance_cta': 'اعثر على محترف',
          'maintenance_hint': '6 فحوصات ذكية تستحق القيام بها في المنزل',
          'maintenance_item_1_title': 'تنظيف فلاتر المكيف',
          'maintenance_item_1_subtitle':
              'لتحسين التبريد وجودة الهواء في المنزل',
          'maintenance_item_1_trade': 'فني تكييف',
          'maintenance_item_2_title': 'فحص سخان المياه',
          'maintenance_item_2_subtitle': 'لمنع التسريبات وضعف التسخين',
          'maintenance_item_2_trade': 'سباك',
          'maintenance_item_3_title': 'فحص سلامة الكهرباء',
          'maintenance_item_3_subtitle': 'لفحص المقابس والأحمال والتوصيلات',
          'maintenance_item_3_trade': 'كهربائي',
          'maintenance_item_4_title': 'تنظيف عميق للمنزل',
          'maintenance_item_4_subtitle':
              'مناسب قبل الأعياد أو الانتقال أو استقبال الضيوف',
          'maintenance_item_4_trade': 'عامل تنظيف',
          'maintenance_item_5_title': 'عزل النوافذ والشرفات',
          'maintenance_item_5_subtitle':
              'لمنع تسرب الماء والهواء في تغيّر الفصول',
          'maintenance_item_5_trade': 'فني عزل',
          'maintenance_item_6_title': 'تشذيب وتنظيف الحديقة',
          'maintenance_item_6_subtitle':
              'يبقي المساحة الخارجية مرتبة وآمنة طوال العام',
          'maintenance_item_6_trade': 'بستاني',
          'no_active_requests': 'لا توجد طلبات نشطة بعد',
          'request_sent': 'تم الإرسال',
          'request_pending': 'بانتظار المراجعة',
          'request_reviewed': 'تمت المراجعة',
          'request_accepted': 'تم القبول',
          'request_scheduled': 'تمت الجدولة',
          'request_declined': 'تم الرفض',
          'request_cancelled': 'تم الإلغاء',
          'request_swipe_hint': 'اسحب يمينًا/يسارًا للتنقل بين الطلبات',
          'requests_to_me': 'الطلبات المرسلة إليّ',
          'latest_request_to_me': 'الطلبات المرسلة إليّ',
          'no_incoming_requests': 'لا توجد طلبات جديدة مرسلة إليك',
          'categories': 'الفئات الشائعة',
          'see_all': 'الكل',
          'broadcast_title': 'بلاغ النظام',
          'my_requests': 'طلباتي',
          'subscribe_cta_title': 'تفعيل اشتراك Pro',
          'subscribe_cta_subtitle':
              'لفتح جميع الأدوات المهنية والحصول على المزيد من الطلبات، فعّل اشتراك Pro.',
          'subscribe_cta_button': 'الانتقال للاشتراك',
        };
      default:
        return {
          'welcome': 'Hello,',
          'guest': 'Guest',
          'find_pros': 'What service do you need today?',
          'search_hint': 'Search for a pro (e.g. Plumber)...',
          'latest_request': 'Latest Request',
          'view_all': 'View all',
          'request_someone_else': 'Request from someone else',
          'project_ideas_title': 'What work do you need?',
          'project_ideas_subtitle':
              'Choose by problem or project type and get started faster',
          'project_ideas_hint':
              'Urgent fixes, renovations, and project ideas in one place',
          'project_ideas_cta': 'View options',
          'project_find_pros': 'Find pros',
          'project_example': 'Examples',
          'project_problem_badge': 'Problem',
          'project_project_badge': 'Project',
          'project_trade_plumber': 'Plumber',
          'project_trade_electrician': 'Electrician',
          'project_trade_painter': 'Painter',
          'project_trade_handyman': 'Handyman',
          'project_trade_gardener': 'Gardener',
          'project_trade_ac': 'AC Technician',
          'project_trade_mover': 'Mover',
          'project_roof_title': 'Build or repair a roof',
          'project_roof_subtitle':
              'Explore roof types before choosing the right pro',
          'project_leak_title': 'Water leakage',
          'project_leak_subtitle':
              'Need a plumber for fast detection and repair',
          'project_power_title': 'Power issue',
          'project_power_subtitle':
              'Sockets, overload, or short circuit? Find an electrician',
          'project_drain_title': 'Blocked drain or bad smell',
          'project_drain_subtitle':
              'For sinks, showers, and drains that need fast attention',
          'project_ac_title': 'AC not cooling',
          'project_ac_subtitle':
              'Check, clean, or repair it before the heat gets worse',
          'project_paint_title': 'Paint my house',
          'project_paint_subtitle':
              'Interior, exterior, or wall refresh projects',
          'project_bathroom_title': 'Bathroom renovation',
          'project_bathroom_subtitle':
              'Tiles, fixtures, waterproofing, and full refresh work',
          'project_garden_title': 'Garden work',
          'project_garden_subtitle':
              'Grass, trimming, irrigation, and outdoor improvement',
          'project_cracks_title': 'Wall cracks',
          'project_cracks_subtitle':
              'Inspection, patching, and plaster work for indoor or outdoor walls',
          'project_move_title': 'Moving to a new place',
          'project_move_subtitle':
              'Moving, disassembly, and setup for home or office',
          'roof_options_title': 'Roof options',
          'roof_options_subtitle':
              'Choose a style to see examples and continue to pros',
          'roof_tile_title': 'Tiled roof',
          'roof_tile_subtitle':
              'Classic look with strong insulation for family homes',
          'roof_wood_title': 'Wooden roof',
          'roof_wood_subtitle':
              'Warm natural style for pergolas and custom structures',
          'roof_panel_title': 'Panel roof',
          'roof_panel_subtitle':
              'Fast, clean, modern solution for many building types',
          'roof_metal_title': 'Metal roof',
          'roof_metal_subtitle':
              'Durable and strong for storage, parking, and industrial use',
          'maintenance_title': 'Home Maintenance Checklist',
          'maintenance_subtitle':
              'Simple things to check before they become expensive',
          'seasonal_pick': 'Seasonal pick',
          'maintenance_cta': 'Find a pro',
          'maintenance_hint': '6 smart checks worth doing around your home',
          'maintenance_item_1_title': 'Clean AC filters',
          'maintenance_item_1_subtitle':
              'Improve cooling and air quality at home',
          'maintenance_item_1_trade': 'AC Technician',
          'maintenance_item_2_title': 'Check water heater',
          'maintenance_item_2_subtitle':
              'Prevent leaks and weak heating before they get worse',
          'maintenance_item_2_trade': 'Plumber',
          'maintenance_item_3_title': 'Electrical safety check',
          'maintenance_item_3_subtitle':
              'Inspect sockets, overload risks, and wiring',
          'maintenance_item_3_trade': 'Electrician',
          'maintenance_item_4_title': 'Deep home cleaning',
          'maintenance_item_4_subtitle':
              'Great before holidays, moving, or hosting guests',
          'maintenance_item_4_trade': 'Cleaner',
          'maintenance_item_5_title': 'Seal windows and balconies',
          'maintenance_item_5_subtitle':
              'Help prevent water and draft issues during season changes',
          'maintenance_item_5_trade': 'Sealing specialist',
          'maintenance_item_6_title': 'Trim and clean the garden',
          'maintenance_item_6_subtitle':
              'Keep outdoor spaces neat, safe, and easier to maintain',
          'maintenance_item_6_trade': 'Gardener',
          'no_active_requests': 'No active requests yet',
          'request_sent': 'Sent',
          'request_pending': 'Waiting for review',
          'request_reviewed': 'Reviewed',
          'request_accepted': 'Accepted',
          'request_scheduled': 'Scheduled',
          'request_declined': 'Declined',
          'request_cancelled': 'Cancelled',
          'request_swipe_hint': 'Swipe left/right to browse requests',
          'requests_to_me': 'Requests sent to me',
          'latest_request_to_me': 'Requests sent to me',
          'no_incoming_requests': 'No incoming requests yet',
          'categories': 'Popular Categories',
          'see_all': 'See all',
          'broadcast_title': 'System Broadcast',
          'my_requests': 'My Requests',
          'subscribe_cta_title': 'Activate Pro Subscription',
          'subscribe_cta_subtitle':
              'To unlock all professional tools and get more requests, activate Pro.',
          'subscribe_cta_button': 'Go to Subscription',
        };
    }
  }

  bool get _shouldShowSubscriptionCta {
    if (_userRole != 'worker') return false;
    return !SubscriptionAccessService.isEntitledSubscriptionStatus(
      _subscriptionStatus,
    );
  }

  void _goToRequest(int nextIndex, int totalCount) {
    final safeNext = nextIndex.clamp(0, totalCount - 1);
    if (safeNext == _requestSwipeIndex) return;
    setState(() {
      _requestTransitionDirection = safeNext > _requestSwipeIndex ? 1 : -1;
      _requestSwipeIndex = safeNext;
    });
  }

  Widget _buildRequestModeButton({
    required bool selected,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color activeForeground,
    required Color activeBackground,
    required Color activeBorder,
  }) {
    return AnimatedScale(
      scale: selected ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? activeBackground : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? activeBorder : const Color(0xFFE2E8F0),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeForeground.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: selected
                ? activeForeground
                : const Color(0xFF475569),
            side: BorderSide.none,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? activeForeground : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
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
                      if (_shouldShowSubscriptionCta) ...[
                        const SizedBox(height: 16),
                        _buildSubscribeCta(localized),
                      ],
                      const SizedBox(height: 24),
                      _buildRequestStatusTimeline(localized),
                      const SizedBox(height: 20),
                      _buildProjectIdeasSection(localized),
                      const SizedBox(height: 24),
                      _buildMaintenanceChecklist(localized),
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
                            color: const Color(
                              0xFF1D4ED8,
                            ).withValues(alpha: 0.28),
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
                                                  color: Colors.white
                                                      .withValues(alpha: 0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
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
                                                  color: Colors.white
                                                      .withValues(alpha: 0.78),
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
                                        foregroundColor: const Color(
                                          0xFF0F172A,
                                        ),
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

  Widget _buildSubscribeCta(Map<String, dynamic> strings) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings['subscribe_cta_title'] ?? 'Activate Pro Subscription',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F2E67),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['subscribe_cta_subtitle'] ??
                'Activate Pro to unlock worker tools.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubscriptionPage(
                      email: FirebaseAuth.instance.currentUser?.email ?? '',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.workspace_premium_rounded),
              label: Text(
                strings['subscribe_cta_button'] ?? 'Go to Subscription',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
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
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: (user != null && !user.isAnonymous)
              ? _firestore
                    .collection('users')
                    .doc(user.uid)
                    .collection('requests')
                    .snapshots()
              : const Stream.empty(),
          builder: (context, snapshot) {
            final requestCount = (snapshot.data?.docs ?? const []).where((doc) {
              final status = (doc.data()['status'] ?? 'pending')
                  .toString()
                  .toLowerCase();
              return status == 'pending';
            }).length;
            return Stack(
              alignment: Alignment.center,
              children: [
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
                if (requestCount > 0)
                  Positioned(
                    right: 2,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF1976D2)),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        requestCount > 99 ? '99+' : '$requestCount',
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

  Widget _buildRequestStatusTimeline(Map<String, dynamic> strings) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return const SizedBox.shrink();
    }

    final isIncomingForWorker = _userRole == 'worker' && _showRequestsSentToMe;
    final requestStream = isIncomingForWorker
        ? _firestore
              .collection('users')
              .doc(user.uid)
              .collection('notifications')
              .orderBy('timestamp', descending: true)
              .limit(60)
              .snapshots()
        : _firestore
              .collection('users')
              .doc(user.uid)
              .collection('requests')
              .orderBy('timestamp', descending: true)
              .limit(20)
              .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: requestStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildEmptyRequestCard(
              strings,
              customMessage: isIncomingForWorker
                  ? strings['no_incoming_requests']
                  : null,
            ),
          );
        }

        final docs = isIncomingForWorker
            ? snapshot.data!.docs.where((doc) {
                final type = (doc.data()['type'] ?? '').toString();
                return type == 'work_request' || type == 'quote_request';
              }).toList()
            : snapshot.data!.docs;

        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildEmptyRequestCard(
              strings,
              customMessage: isIncomingForWorker
                  ? strings['no_incoming_requests']
                  : null,
            ),
          );
        }
        if (_requestSwipeIndex >= docs.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _requestSwipeIndex = docs.length - 1;
            });
          });
        }
        final currentIndex = _requestSwipeIndex.clamp(0, docs.length - 1);
        final doc = docs[currentIndex];
        final data = doc.data();
        final status = _normalizeHomeRequestStatus(
          (data['status'] ?? 'pending').toString(),
        );
        final reviewedAt = data['reviewedAt'] as Timestamp?;
        final hasSchedule = data['acceptedWindow'] != null;
        final isReviewed =
            reviewedAt != null ||
            status == 'accepted' ||
            status == 'rejected' ||
            status == 'cancelled';
        final statusLabel = switch (status) {
          'rejected' => strings['request_declined'] ?? 'Declined',
          'cancelled' => strings['request_cancelled'] ?? 'Cancelled',
          'accepted' when hasSchedule =>
            strings['request_scheduled'] ?? 'Scheduled',
          'accepted' => strings['request_accepted'] ?? 'Accepted',
          _ when isReviewed => strings['request_reviewed'] ?? 'Reviewed',
          _ => strings['request_pending'] ?? 'Waiting for review',
        };
        final statusColor = switch (status) {
          'rejected' => const Color(0xFFDC2626),
          'cancelled' => const Color(0xFF64748B),
          'accepted' => const Color(0xFF059669),
          _ when isReviewed => const Color(0xFF1D4ED8),
          _ => const Color(0xFFF59E0B),
        };
        final currentStep = switch (status) {
          'accepted' when hasSchedule => 3,
          'accepted' => 2,
          'rejected' || 'cancelled' => 2,
          _ when isReviewed => 1,
          _ => 0,
        };
        final stepLabels = [
          strings['request_sent'] ?? 'Sent',
          strings['request_reviewed'] ?? 'Reviewed',
          status == 'rejected'
              ? (strings['request_declined'] ?? 'Declined')
              : status == 'cancelled'
              ? (strings['request_cancelled'] ?? 'Cancelled')
              : (strings['request_accepted'] ?? 'Accepted'),
          strings['request_scheduled'] ?? 'Scheduled',
        ];
        final title = (data['jobDescription'] ?? 'Request').toString().trim();
        final date = (data['date'] ?? '').toString().trim();
        final profession = (data['profession'] ?? '').toString().trim();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: Color(0xFF1976D2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isIncomingForWorker
                            ? (strings['latest_request_to_me'] ??
                                  'Requests sent to me')
                            : (strings['latest_request'] ?? 'Latest Request'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (docs.length > 1)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: currentIndex > 0
                            ? () => _goToRequest(currentIndex - 1, docs.length)
                            : null,
                      ),
                    if (docs.length > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 2),
                        child: Text(
                          '${currentIndex + 1}/${docs.length}',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (docs.length > 1)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: currentIndex < docs.length - 1
                            ? () => _goToRequest(currentIndex + 1, docs.length)
                            : null,
                      ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => isIncomingForWorker
                                ? const NotificationsPage(
                                    initialFilter: 'requests',
                                  )
                                : const MyRequestsPage(),
                          ),
                        );
                      },
                      child: Text(strings['view_all'] ?? 'View all'),
                    ),
                  ],
                ),
                if (_userRole == 'worker') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildRequestModeButton(
                        selected: !isIncomingForWorker,
                        onPressed: () => setState(() {
                          _showRequestsSentToMe = false;
                          _requestSwipeIndex = 0;
                        }),
                        icon: Icons.assignment_outlined,
                        label: strings['my_requests'] ?? 'My Requests',
                        activeForeground: const Color(0xFF1976D2),
                        activeBackground: const Color(0xFFEFF6FF),
                        activeBorder: const Color(0xFFBFDBFE),
                      ),
                      _buildRequestModeButton(
                        selected: isIncomingForWorker,
                        onPressed: () => setState(() {
                          _showRequestsSentToMe = true;
                          _requestSwipeIndex = 0;
                        }),
                        icon: Icons.mark_email_unread_outlined,
                        label:
                            strings['requests_to_me'] ?? 'Requests sent to me',
                        activeForeground: const Color(0xFF0F766E),
                        activeBackground: const Color(0xFFF0FDFA),
                        activeBorder: const Color(0xFF99F6E4),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isIncomingForWorker) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RequestDetailsPage(
                            notificationId: doc.id,
                            data: data,
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyRequestDetailsPage(
                            requestRef: doc.reference,
                            initialData: data,
                          ),
                        ),
                      );
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 120) return;
                    if (velocity < 0 && currentIndex < docs.length - 1) {
                      _goToRequest(currentIndex + 1, docs.length);
                    } else if (velocity > 0 && currentIndex > 0) {
                      _goToRequest(currentIndex - 1, docs.length);
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final beginOffset = Offset(
                        _requestTransitionDirection * 0.18,
                        0,
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: beginOffset,
                            end: Offset.zero,
                          ).animate(animation),
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.985,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey(doc.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? 'Request' : title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        if (date.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            date,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!isIncomingForWorker) ...[
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(stepLabels.length * 2 - 1, (
                              index,
                            ) {
                              if (index.isOdd) {
                                final connectorIndex = index ~/ 2;
                                final isActive = connectorIndex < currentStep;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 15),
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFF1976D2)
                                            : const Color(0xFFE2E8F0),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final stepIndex = index ~/ 2;
                              final isActive = stepIndex <= currentStep;
                              final isRejectedStep =
                                  status == 'rejected' &&
                                  stepIndex == 2 &&
                                  isActive;
                              final isCancelledStep =
                                  status == 'cancelled' &&
                                  stepIndex == 2 &&
                                  isActive;
                              final stepColor = isRejectedStep
                                  ? const Color(0xFFDC2626)
                                  : isCancelledStep
                                  ? const Color(0xFF64748B)
                                  : isActive
                                  ? const Color(0xFF1976D2)
                                  : const Color(0xFFE2E8F0);
                              final stepIcon = isRejectedStep
                                  ? Icons.close_rounded
                                  : isCancelledStep
                                  ? Icons.remove_rounded
                                  : isActive
                                  ? Icons.check_rounded
                                  : Icons.circle;
                              final iconColor =
                                  isActive &&
                                      !isCancelledStep &&
                                      !isRejectedStep
                                  ? Colors.white
                                  : isRejectedStep || isCancelledStep
                                  ? Colors.white
                                  : const Color(0xFF94A3B8);

                              return SizedBox(
                                width: 62,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: stepColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        stepIcon,
                                        size: 18,
                                        color: iconColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      stepLabels[stepIndex],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF475569),
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                        ],
                        if (status == 'rejected' && profession.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(
                                  color: Color(0xFFFCA5A5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SearchPage(initialTrade: profession),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_search_rounded),
                              label: Text(
                                strings['request_someone_else'] ??
                                    'Request from someone else',
                              ),
                            ),
                          ),
                        ],
                        if (docs.length > 1) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(docs.length, (index) {
                              final selected = index == currentIndex;
                              return GestureDetector(
                                onTap: () => _goToRequest(index, docs.length),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  width: selected ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF1976D2)
                                        : const Color(0xFFCBD5E1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              strings['request_swipe_hint'] ??
                                  'Swipe left/right to browse requests',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyRequestCard(
    Map<String, dynamic> strings, {
    String? customMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              customMessage ??
                  strings['no_active_requests'] ??
                  'No active requests yet',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceChecklist(Map<String, dynamic> strings) {
    final items = [
      {
        'title': strings['maintenance_item_1_title'] ?? 'Clean AC filters',
        'subtitle':
            strings['maintenance_item_1_subtitle'] ??
            'Improve cooling and air quality at home',
        'trade': 'AC Technician',
        'tradeLabel': strings['maintenance_item_1_trade'] ?? 'AC Technician',
        'icon': Icons.ac_unit_rounded,
        'color': const Color(0xFF0EA5E9),
      },
      {
        'title': strings['maintenance_item_2_title'] ?? 'Check water heater',
        'subtitle':
            strings['maintenance_item_2_subtitle'] ??
            'Prevent leaks and weak heating before they get worse',
        'trade': 'Plumber',
        'tradeLabel': strings['maintenance_item_2_trade'] ?? 'Plumber',
        'icon': Icons.water_drop_outlined,
        'color': const Color(0xFF2563EB),
      },
      {
        'title':
            strings['maintenance_item_3_title'] ?? 'Electrical safety check',
        'subtitle':
            strings['maintenance_item_3_subtitle'] ??
            'Inspect sockets, overload risks, and wiring',
        'trade': 'Electrician',
        'tradeLabel': strings['maintenance_item_3_trade'] ?? 'Electrician',
        'icon': Icons.electrical_services_rounded,
        'color': const Color(0xFFF59E0B),
      },
      {
        'title': strings['maintenance_item_4_title'] ?? 'Deep home cleaning',
        'subtitle':
            strings['maintenance_item_4_subtitle'] ??
            'Great before holidays, moving, or hosting guests',
        'trade': 'Cleaner',
        'tradeLabel': strings['maintenance_item_4_trade'] ?? 'Cleaner',
        'icon': Icons.cleaning_services_rounded,
        'color': const Color(0xFF10B981),
      },
      {
        'title':
            strings['maintenance_item_5_title'] ?? 'Seal windows and balconies',
        'subtitle':
            strings['maintenance_item_5_subtitle'] ??
            'Help prevent water and draft issues during season changes',
        'trade': 'Handyman',
        'tradeLabel':
            strings['maintenance_item_5_trade'] ?? 'Sealing specialist',
        'icon': Icons.water_damage_outlined,
        'color': const Color(0xFF7C3AED),
      },
      {
        'title':
            strings['maintenance_item_6_title'] ?? 'Trim and clean the garden',
        'subtitle':
            strings['maintenance_item_6_subtitle'] ??
            'Keep outdoor spaces neat, safe, and easier to maintain',
        'trade': 'Gardener',
        'tradeLabel': strings['maintenance_item_6_trade'] ?? 'Gardener',
        'icon': Icons.yard_rounded,
        'color': const Color(0xFF16A34A),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings['maintenance_title'] ??
                            'Home Maintenance Checklist',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings['maintenance_subtitle'] ??
                            'Simple things to check before they become expensive',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        strings['maintenance_hint'] ??
                            '4 quick checks for your home',
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
                    strings['seasonal_pick'] ?? 'Seasonal pick',
                    style: const TextStyle(
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 244,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final color = item['color'] as Color;

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SearchPage(initialTrade: item['trade']! as String),
                      ),
                    );
                  },
                  child: Container(
                    width: 244,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.80)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              child: Icon(
                                item['icon']! as IconData,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item['tradeLabel']! as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['title']! as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item['subtitle']! as String,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  strings['seasonal_pick'] ?? 'Seasonal pick',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                strings['maintenance_cta'] ?? 'Find a pro',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectIdeasSection(Map<String, dynamic> strings) {
    final items = [
      {
        'title': strings['project_roof_title'] ?? 'Build or repair a roof',
        'subtitle':
            strings['project_roof_subtitle'] ??
            'Explore roof types before choosing the right pro',
        'icon': Icons.roofing_rounded,
        'color': const Color(0xFF7C3AED),
        'action': 'roof_options',
        'badge': strings['project_project_badge'] ?? 'Project',
      },
      {
        'title': strings['project_leak_title'] ?? 'Water leakage',
        'subtitle':
            strings['project_leak_subtitle'] ??
            'Need a plumber for fast detection and repair',
        'icon': Icons.plumbing_rounded,
        'color': const Color(0xFF0284C7),
        'trade': 'Plumber',
        'tradeLabel': strings['project_trade_plumber'] ?? 'Plumber',
        'badge': strings['project_problem_badge'] ?? 'Problem',
      },
      {
        'title': strings['project_power_title'] ?? 'Power issue',
        'subtitle':
            strings['project_power_subtitle'] ??
            'Sockets, overload, or short circuit? Find an electrician',
        'icon': Icons.electrical_services_rounded,
        'color': const Color(0xFFF59E0B),
        'trade': 'Electrician',
        'tradeLabel': strings['project_trade_electrician'] ?? 'Electrician',
        'badge': strings['project_problem_badge'] ?? 'Problem',
      },
      {
        'title': strings['project_drain_title'] ?? 'Blocked drain or bad smell',
        'subtitle':
            strings['project_drain_subtitle'] ??
            'For sinks, showers, and drains that need fast attention',
        'icon': Icons.water_damage_rounded,
        'color': const Color(0xFF0F766E),
        'trade': 'Plumber',
        'tradeLabel': strings['project_trade_plumber'] ?? 'Plumber',
        'badge': strings['project_problem_badge'] ?? 'Problem',
      },
      {
        'title': strings['project_ac_title'] ?? 'AC not cooling',
        'subtitle':
            strings['project_ac_subtitle'] ??
            'Check, clean, or repair it before the heat gets worse',
        'icon': Icons.ac_unit_rounded,
        'color': const Color(0xFF2563EB),
        'trade': 'AC Technician',
        'tradeLabel': strings['project_trade_ac'] ?? 'AC Technician',
        'badge': strings['project_problem_badge'] ?? 'Problem',
      },
      {
        'title': strings['project_paint_title'] ?? 'Paint my house',
        'subtitle':
            strings['project_paint_subtitle'] ??
            'Interior, exterior, or wall refresh projects',
        'icon': Icons.format_paint_rounded,
        'color': const Color(0xFF14B8A6),
        'trade': 'Painter',
        'tradeLabel': strings['project_trade_painter'] ?? 'Painter',
        'badge': strings['project_project_badge'] ?? 'Project',
      },
      {
        'title': strings['project_bathroom_title'] ?? 'Bathroom renovation',
        'subtitle':
            strings['project_bathroom_subtitle'] ??
            'Tiles, fixtures, waterproofing, and full refresh work',
        'icon': Icons.bathtub_rounded,
        'color': const Color(0xFFEC4899),
        'trade': 'Handyman',
        'tradeLabel': strings['project_trade_handyman'] ?? 'Handyman',
        'badge': strings['project_project_badge'] ?? 'Project',
      },
      {
        'title': strings['project_garden_title'] ?? 'Garden work',
        'subtitle':
            strings['project_garden_subtitle'] ??
            'Grass, trimming, irrigation, and outdoor improvement',
        'icon': Icons.yard_rounded,
        'color': const Color(0xFF16A34A),
        'trade': 'Gardener',
        'tradeLabel': strings['project_trade_gardener'] ?? 'Gardener',
        'badge': strings['project_project_badge'] ?? 'Project',
      },
      {
        'title': strings['project_cracks_title'] ?? 'Wall cracks',
        'subtitle':
            strings['project_cracks_subtitle'] ??
            'Inspection, patching, and plaster work for indoor or outdoor walls',
        'icon': Icons.home_repair_service_rounded,
        'color': const Color(0xFF6B7280),
        'trade': 'Handyman',
        'tradeLabel': strings['project_trade_handyman'] ?? 'Handyman',
        'badge': strings['project_problem_badge'] ?? 'Problem',
      },
      {
        'title': strings['project_move_title'] ?? 'Moving to a new place',
        'subtitle':
            strings['project_move_subtitle'] ??
            'Moving, disassembly, and setup for home or office',
        'icon': Icons.local_shipping_rounded,
        'color': const Color(0xFFEA580C),
        'trade': 'Mover',
        'tradeLabel': strings['project_trade_mover'] ?? 'Mover',
        'badge': strings['project_project_badge'] ?? 'Project',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings['project_ideas_title'] ?? 'What work do you need?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings['project_ideas_subtitle'] ??
                      'Choose by problem or project type and get started faster',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  strings['project_ideas_hint'] ??
                      'Urgent fixes, renovations, and project ideas in one place',
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final color = item['color'] as Color;

                return GestureDetector(
                  onTap: () {
                    if (item['action'] == 'roof_options') {
                      _showRoofOptionsSheet(strings);
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SearchPage(initialTrade: item['trade']! as String),
                      ),
                    );
                  },
                  child: Container(
                    width: 252,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.82)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 23,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              child: Icon(
                                item['icon']! as IconData,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item['badge']! as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          item['title']! as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['subtitle']! as String,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        if (item['trade'] != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              item['tradeLabel']! as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              strings['project_ideas_cta'] ?? 'View options',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRoofOptionsSheet(Map<String, dynamic> strings) {
    final options = [
      {
        'title': strings['roof_tile_title'] ?? 'Tiled roof',
        'subtitle':
            strings['roof_tile_subtitle'] ??
            'Classic look with strong insulation for family homes',
        'image':
            'https://commons.wikimedia.org/wiki/Special:FilePath/Roof-Tile-3149.jpg',
      },
      {
        'title': strings['roof_wood_title'] ?? 'Wooden roof',
        'subtitle':
            strings['roof_wood_subtitle'] ??
            'Warm natural style for pergolas and custom structures',
        'image':
            'https://commons.wikimedia.org/wiki/Special:FilePath/Wood%20Shingle%20Roof%20Installation.jpg',
      },
      {
        'title': strings['roof_panel_title'] ?? 'Panel roof',
        'subtitle':
            strings['roof_panel_subtitle'] ??
            'Fast, clean, modern solution for many building types',
        'image':
            'https://commons.wikimedia.org/wiki/Special:FilePath/Sandwichpaneel-Dach07.jpg',
      },
      {
        'title': strings['roof_metal_title'] ?? 'Metal roof',
        'subtitle':
            strings['roof_metal_subtitle'] ??
            'Durable and strong for storage, parking, and industrial use',
        'image':
            'https://commons.wikimedia.org/wiki/Special:FilePath/Standing%20seam%20metal%20roof%203.jpg',
      },
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['roof_options_title'] ?? 'Roof options',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            strings['roof_options_subtitle'] ??
                                'Choose a style to see examples and continue to pros',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final option = options[index];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(22),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: option['image']! as String,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          strings['project_example'] ??
                                              'Examples',
                                          style: const TextStyle(
                                            color: Color(0xFF1D4ED8),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    option['title']! as String,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    option['subtitle']! as String,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF1D4ED8,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          this.context,
                                          MaterialPageRoute(
                                            builder: (_) => SearchPage(
                                              initialTrade: 'Roofer',
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.search_rounded),
                                      label: Text(
                                        strings['project_find_pros'] ??
                                            'Find pros',
                                      ),
                                    ),
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
              ],
            ),
          ),
        );
      },
    );
  }

  String _normalizeHomeRequestStatus(String status) {
    switch (status.toLowerCase()) {
      case 'declined':
      case 'rejected':
        return 'rejected';
      case 'cancelled':
        return 'cancelled';
      case 'accepted':
        return 'accepted';
      default:
        return 'pending';
    }
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
