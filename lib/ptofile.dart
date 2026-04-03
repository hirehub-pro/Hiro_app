import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/sign_in.dart';
import 'package:untitled1/pages/schedule.dart';
import 'package:untitled1/pages/settings.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/pages/analytics_page.dart';
import 'package:untitled1/pages/add_project.dart';
import 'package:untitled1/pages/add_review.dart';
import 'package:untitled1/pages/post_details_page.dart';
import 'package:untitled1/pages/location_manager_page.dart';
import 'package:untitled1/services/location_context_service.dart';

import 'package:untitled1/widgets/cached_video_player.dart';

class Profile extends StatefulWidget {
  final String? userId;
  final String? viewedProfession;
  const Profile({super.key, this.userId, this.viewedProfession});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> with TickerProviderStateMixin {
  static const String _vpdDocId = 'currentWeek';
  static const int _counterShardCount = 20;
  static const List<String> _weekDayKeys = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];

  TabController? _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<User?>? _authSubscription;

  String _userName = "";
  String _bio = "";
  String _phoneNumber = "";
  String _altPhoneNumber = "";
  String _email = "";
  String _town = "";
  String _profileImageUrl = "";
  String _userRole = "customer";
  List<String> _userProfessions = [];
  Map<String, Map<String, String>> _professionTranslations = {};
  List<Map<String, dynamic>> _userReviews = [];
  List<Map<String, dynamic>> _projects = [];
  int _profileViews = 0;
  bool _isFavorite = false;

  bool _isOwnProfile = false;
  bool _isLoading = true;

  bool _isIdVerified = false;
  bool _isBusinessVerified = false;
  bool _isInsured = false;

  String _distanceStr = "";
  double? _proLat;
  double? _proLng;

  @override
  void initState() {
    super.initState();
    _checkInitialOwnership();
    _initTabController();
    _loadProfessionTranslations();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && widget.userId == null) {
        _fetchUserData();
      }
    });

    _fetchUserData();
  }

  Future<void> _loadProfessionTranslations() async {
    try {
      final doc = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final items = (doc.data()?['items'] as List?) ?? const [];

      final map = <String, Map<String, String>>{};
      for (final raw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final en = item['en']?.toString().trim();
        if (en == null || en.isEmpty) continue;

        map[en.toLowerCase()] = {
          'en': en,
          'he': item['he']?.toString().trim() ?? '',
          'ar': item['ar']?.toString().trim() ?? '',
          'ru': item['ru']?.toString().trim() ?? '',
          'am': item['am']?.toString().trim() ?? '',
        };
      }

      if (!mounted) return;
      setState(() {
        _professionTranslations = map;
      });
    } catch (e) {
      debugPrint("Failed to load profession translations: $e");
    }
  }

  String _translateProfessionName(String profession, String localeCode) {
    final key = profession.trim().toLowerCase();
    final localized = _professionTranslations[key];
    if (localized == null) return profession;

    final translated = localized[localeCode]?.trim();
    if (translated != null && translated.isNotEmpty) {
      return translated;
    }

    return localized['en'] ?? profession;
  }

  List<String> _localizedProfessionList(String localeCode) {
    return _userProfessions
        .map((p) => _translateProfessionName(p, localeCode))
        .toList();
  }

  String _weekKey(DateTime date) {
    final start = _startOfWeek(date);
    return '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }

  int _randomShard() => Random().nextInt(_counterShardCount);

  Future<int> _readShardedProfileViews(String userId) async {
    final shards = await _firestore
        .collection('users')
        .doc(userId)
        .collection('metrics')
        .doc('profileViews')
        .collection('shards')
        .get();

    int total = 0;
    for (final doc in shards.docs) {
      final data = doc.data();
      final count = data['count'];
      if (count is num) total += count.toInt();
    }
    return total;
  }

  Future<void> _incrementShardedProfileViews(String workerId) async {
    final shardRef = _firestore
        .collection('users')
        .doc(workerId)
        .collection('metrics')
        .doc('profileViews')
        .collection('shards')
        .doc(_randomShard().toString());

    await shardRef.set({
      'count': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _checkInitialOwnership() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUid = widget.userId;
    _isOwnProfile = targetUid == null
        ? currentUser != null
        : (currentUser != null && targetUid == currentUser.uid);
  }

  DateTime _startOfWeek(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final offsetToSunday = dayStart.weekday % 7;
    return dayStart.subtract(Duration(days: offsetToSunday));
  }

  String _dayKeyForDate(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
      default:
        return 'sunday';
    }
  }

  bool _isCurrentWeek(dynamic rawWeekStart) {
    DateTime? saved;
    if (rawWeekStart is Timestamp) {
      saved = rawWeekStart.toDate();
    } else if (rawWeekStart is String) {
      saved = DateTime.tryParse(rawWeekStart);
    }

    if (saved == null) return false;
    return _startOfWeek(saved).isAtSameMomentAs(_startOfWeek(DateTime.now()));
  }

  Map<String, int> _emptyWeekMap() {
    return {
      'sunday': 0,
      'monday': 0,
      'tuesday': 0,
      'wednesday': 0,
      'thursday': 0,
      'friday': 0,
      'saturday': 0,
      'TVTW': 0,
    };
  }

  String _docIdForProfession(String profession) {
    return profession.trim().replaceAll('/', '_');
  }

  Future<void> _incrementProfessionWeeklyViews({
    required String workerId,
    required String profession,
  }) async {
    final normalizedProfession = profession.trim();
    if (normalizedProfession.isEmpty) return;
    final professionDocId = _docIdForProfession(normalizedProfession);

    final workerRef = _firestore.collection('users').doc(workerId);
    final proRatingRef = workerRef.collection('ProRating').doc(professionDocId);
    final shardRef = proRatingRef
        .collection('VPD')
        .doc(_vpdDocId)
        .collection('shards')
        .doc(_randomShard().toString());

    await proRatingRef.set({
      'profession': normalizedProfession,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.runTransaction((tx) async {
      final now = DateTime.now();
      final dayKey = _dayKeyForDate(now);
      final weekStart = _startOfWeek(now);
      final currentWeekKey = _weekKey(now);

      final snapshot = await tx.get(shardRef);
      final current = _emptyWeekMap();

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        if (data['weekKey'] == currentWeekKey ||
            _isCurrentWeek(data['weekStart'])) {
          for (final day in _weekDayKeys) {
            final value = data[day];
            if (value is num) current[day] = value.toInt();
          }
          final total = data['TVTW'];
          if (total is num) current['TVTW'] = total.toInt();
        }
      }

      current[dayKey] = (current[dayKey] ?? 0) + 1;
      current['TVTW'] = (current['TVTW'] ?? 0) + 1;

      tx.set(shardRef, {
        ...current,
        'weekKey': currentWeekKey,
        'weekStart': Timestamp.fromDate(weekStart),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  void _initTabController() {
    int tabCount = (_userRole == 'worker' || _isOwnProfile) ? 4 : 2;

    // Dispose old controller if it exists
    _tabController?.dispose();

    _tabController = TabController(length: tabCount, vsync: this);
    _tabController!.addListener(() {
      if (!_tabController!.indexIsChanging) {
        setState(() {});
      }
    });
  }

  Future<void> _fetchUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final targetUid = widget.userId ?? currentUser?.uid;

    if (mounted) {
      setState(() {
        _isOwnProfile = widget.userId == null
            ? currentUser != null
            : (currentUser != null && widget.userId == currentUser.uid);
        if (_userName.isEmpty) _isLoading = true;
      });
    }

    if (targetUid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(targetUid).get();

      if (userDoc.exists && mounted) {
        final data = userDoc.data() as Map<String, dynamic>;

        String oldRole = _userRole;
        setState(() {
          _userName = data['name']?.toString() ?? "";
          _bio = data['description']?.toString() ?? "";
          _phoneNumber = data['phone']?.toString() ?? "";
          _altPhoneNumber = data['optionalPhone']?.toString() ?? "";
          _email = data['email']?.toString() ?? "";
          _town = data['town']?.toString() ?? "";
          _profileImageUrl = data['profileImageUrl']?.toString() ?? "";
          _profileViews = data['profileViews'] ?? 0;
          _userRole = data['role'] ?? 'customer';

          if (data['professions'] is List) {
            _userProfessions = List<String>.from(data['professions']);
          } else if (data['profession'] != null) {
            _userProfessions = [data['profession'].toString()];
          } else {
            _userProfessions = [];
          }

          _isIdVerified = data['isIdVerified'] ?? false;
          _isBusinessVerified = data['isVerified'] ?? false;
          _isInsured = data['isInsured'] ?? false;

          _proLat = data['lat']?.toDouble();
          _proLng = data['lng']?.toDouble();
        });

        if (oldRole != _userRole) {
          _initTabController();
        }

        if (!_isOwnProfile) {
          _calculateDistance();
        }

        final reviews = await _fetchSubcollection(targetUid, 'reviews');
        final projects = await _fetchSubcollection(targetUid, 'projects');

        if (mounted) {
          setState(() {
            _userReviews = reviews;
            _projects = projects;
          });
        }

        if (_isOwnProfile) {
          final shardedViews = await _readShardedProfileViews(targetUid);
          if (mounted && shardedViews > 0) {
            setState(() {
              _profileViews = shardedViews;
            });
          }
        }

        if (currentUser != null && !_isOwnProfile) {
          final favDoc = await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('favorites')
              .doc(targetUid)
              .get();
          if (mounted) setState(() => _isFavorite = favDoc.exists);
        }

        if (!_isOwnProfile) {
          await _incrementShardedProfileViews(targetUid);

          final viewedProfession = widget.viewedProfession?.trim() ?? '';
          if (viewedProfession.isNotEmpty) {
            await _incrementProfessionWeeklyViews(
              workerId: targetUid,
              profession: viewedProfession,
            );
          }

          final shardedViews = await _readShardedProfileViews(targetUid);
          if (mounted) {
            setState(() {
              _profileViews = shardedViews;
            });
          }
        }

        if (mounted) setState(() => _isLoading = false);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("FETCH ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateDistance() async {
    if (_proLat == null || _proLng == null) return;

    try {
      final userPos = await LocationContextService.getActiveLocation();

      if (userPos != null) {
        double distanceInMeters = Geolocator.distanceBetween(
          userPos.latitude,
          userPos.longitude,
          _proLat!,
          _proLng!,
        );
        if (mounted) {
          setState(() {
            if (distanceInMeters < 1000) {
              _distanceStr = "${distanceInMeters.toStringAsFixed(0)}m";
            } else {
              _distanceStr =
                  "${(distanceInMeters / 1000).toStringAsFixed(1)}km";
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Distance error: $e");
    }
  }

  Future<void> _openLocationManager() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LocationManagerPage()),
    );

    if (changed == true && !_isOwnProfile) {
      await _calculateDistance();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSubcollection(
    String uid,
    String sub,
  ) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection(sub)
        .get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<void> _toggleFavorite() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final targetUid = widget.userId;
    if (targetUid == null) return;

    try {
      final favRef = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('favorites')
          .doc(targetUid);
      if (_isFavorite) {
        await favRef.delete();
      } else {
        await favRef.set({
          'addedAt': FieldValue.serverTimestamp(),
          'name': _userName,
          'profileImageUrl': _profileImageUrl,
          'professions': _userProfessions,
        });
      }
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      debugPrint("Favorite error: $e");
    }
  }

  bool _isGuest() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  void _showGuestDialog(BuildContext context, Map<String, String> strings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['guest_title'] ?? "Login Required"),
        content: Text(
          strings['guest_msg'] ?? "Please login to use this feature.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['cancel'] ?? "Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              );
            },
            child: Text(strings['login'] ?? "Login"),
          ),
        ],
      ),
    );
  }

  Future<void> _reportUser(Map<String, String> strings) async {
    // Basic report logic
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Report User"),
        content: const Text(
          "Are you sure you want to report this user for inappropriate content or behavior?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await _firestore.collection('reports').add({
                'reporterId': FirebaseAuth.instance.currentUser?.uid,
                'reportedId': widget.userId,
                'timestamp': FieldValue.serverTimestamp(),
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Report submitted successfully.")),
              );
            },
            child: const Text("Report", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _addProject() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProjectPage()),
    );
    if (result == true) {
      _fetchUserData();
    }
  }

  Future<void> _addReview(Map<String, String> strings) async {
    if (_isGuest()) {
      _showGuestDialog(context, strings);
      return;
    }

    Map<String, dynamic>? existingReview;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        existingReview = _userReviews.firstWhere(
          (r) => r['userId'] == currentUser.uid,
        );
      } catch (_) {
        existingReview = null;
      }
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddReviewPage(
          targetUserId: widget.userId ?? "",
          professions: _userProfessions,
          existingReview: existingReview,
        ),
      ),
    );

    if (result == true) {
      _fetchUserData();
    }
  }

  Future<void> _upgradeToWorker() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final strings = _getLocalizedStrings(context);
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          strings['upgrade_worker']!,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(strings['upgrade_msg']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings['cancel']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
            ),
            child: Text(strings['confirm']!),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'role': 'worker',
        });

        await _fetchUserData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account upgraded to worker successfully!'),
            ),
          );
        }
      } catch (e) {
        debugPrint("Upgrade error: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Upgrade failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _shareProfile(Map<String, String> strings) async {
    final profileUrl =
        "https://hirehub.app/profile/${widget.userId ?? FirebaseAuth.instance.currentUser?.uid}";
    await Share.share("${strings['share_profile']} - $_userName: $profileUrl");
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1976D2)),
        ),
      );
    }

    if (widget.userId == null && _isGuest()) {
      return Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 72,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRtl
                        ? 'יש להתחבר כדי לצפות בפרופיל'
                        : 'Please sign in to view your profile',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignInPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isRtl ? 'להתחברות' : 'Go to Sign In'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.white,
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          color: const Color(0xFF1976D2),
          onRefresh: _fetchUserData,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 450,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFF1976D2),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.place_outlined),
                    onPressed: _openLocationManager,
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _shareProfile(strings),
                  ),
                  if (!_isOwnProfile)
                    IconButton(
                      icon: Icon(
                        _isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: _isFavorite ? Colors.redAccent : Colors.white,
                      ),
                      onPressed: _toggleFavorite,
                    ),
                  if (!_isOwnProfile)
                    IconButton(
                      icon: const Icon(
                        Icons.report_problem_outlined,
                        color: Colors.white70,
                      ),
                      onPressed: () => _reportUser(strings),
                    ),
                  if (_isOwnProfile && !_isGuest())
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ).then((_) => _fetchUserData()),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground,
                  ],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag:
                            widget.userId ??
                            (FirebaseAuth.instance.currentUser?.uid ??
                                'profile'),
                        child: _profileImageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _profileImageUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    Container(color: const Color(0xFF1E3A8A)),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error),
                              )
                            : Container(
                                color: const Color(0xFF1E3A8A),
                                child: const Icon(
                                  Icons.person,
                                  size: 100,
                                  color: Colors.white24,
                                ),
                              ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.2),
                              Colors.black.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 60,
                        left: 24,
                        right: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _userName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                if (_userRole == 'worker')
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Icon(
                                      Icons.verified,
                                      color: Color(0xFF60A5FA),
                                      size: 24,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (_userProfessions.isNotEmpty)
                              Text(
                                _localizedProfessionList(
                                  localeCode,
                                ).join(' • '),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildStatItem(
                                  _projects.length.toString(),
                                  strings['projects']!,
                                ),
                                _buildStatItem(
                                  _userReviews.length.toString(),
                                  strings['reviews']!,
                                ),
                                _buildStatItem(
                                  _profileViews.toString(),
                                  strings['views']!,
                                ),
                                if (_userReviews.isNotEmpty)
                                  _buildStatItem(
                                    _calculateAverageRating().toStringAsFixed(
                                      1,
                                    ),
                                    strings['rating']!,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  if (_isIdVerified)
                                    _buildHeaderBadge(
                                      Icons.assignment_ind,
                                      strings['verified_id']!,
                                      Colors.greenAccent,
                                    ),
                                  if (_isBusinessVerified)
                                    _buildHeaderBadge(
                                      Icons.business_center,
                                      strings['verified_biz']!,
                                      Colors.orangeAccent,
                                    ),
                                  if (_isInsured)
                                    _buildHeaderBadge(
                                      Icons.shield,
                                      strings['insured']!,
                                      Colors.blueAccent,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: -1,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    indicatorColor: const Color(0xFF1976D2),
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: const Color(0xFF1976D2),
                    unselectedLabelColor: Colors.grey[400],
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    tabs: _buildTabs(strings),
                  ),
                ),
              ),
            ],
            body: Container(
              color: Colors.white,
              child: TabBarView(
                controller: _tabController,
                children: _buildTabViews(strings, localeCode),
              ),
            ),
          ),
        ),
        bottomNavigationBar: (!_isOwnProfile && _userRole == 'worker')
            ? _buildBottomBar(strings)
            : null,
        floatingActionButton:
            (_isOwnProfile &&
                _tabController != null &&
                _tabController!.index == 0)
            ? FloatingActionButton.extended(
                heroTag: 'profile_fab',
                onPressed: _addProject,
                backgroundColor: const Color(0xFF1976D2),
                icon: const Icon(
                  Icons.add_photo_alternate_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  strings['add']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  double _calculateAverageRating() {
    if (_userReviews.isEmpty) return 0.0;
    double total = 0;
    for (var r in _userReviews) {
      total += (r['rating'] ?? 0).toDouble();
    }
    return total / _userReviews.length;
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildHeaderBadge(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTabs(Map<String, String> strings) {
    if (_userRole == 'worker' || _isOwnProfile) {
      return [
        Tab(text: strings['projects']),
        Tab(text: strings['reviews']),
        Tab(text: strings['schedule']),
        Tab(text: strings['about']),
      ];
    }
    return [Tab(text: strings['about']), Tab(text: "Activity")];
  }

  List<Widget> _buildTabViews(Map<String, String> strings, String localeCode) {
    if (_userRole == 'worker' || _isOwnProfile) {
      final currentUserId =
          widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        return [
          _buildAboutSection(strings),
          const Center(child: Text("Activity Feed")),
        ];
      }
      return [
        _buildProjectsGrid(strings),
        _buildReviewsList(strings, localeCode),
        SchedulePage(workerId: currentUserId, workerName: _userName),
        _buildAboutSection(strings),
      ];
    }
    return [
      _buildAboutSection(strings),
      const Center(child: Text("Activity Feed")),
    ];
  }

  bool _isPathVideo(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.contains('.mp4') ||
        lowerUrl.contains('.mov') ||
        lowerUrl.contains('.avi') ||
        lowerUrl.contains('.mkv');
  }

  Widget _buildProjectsGrid(Map<String, String> strings) {
    if (_projects.isEmpty && !_isOwnProfile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey[200],
            ),
            const SizedBox(height: 16),
            Text(
              strings['no_projects']!,
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    bool canAdd = _isOwnProfile;

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _projects.length + (canAdd ? 1 : 0),
      itemBuilder: (context, index) {
        if (canAdd && index == 0) {
          return InkWell(
            onTap: _addProject,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.blue[100]!,
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Colors.blue[300],
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings['add_project']!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final project = _projects[canAdd ? index - 1 : index];
        final String firstMedia = project['imageUrl'] ?? project['image'] ?? "";
        final bool isVideo = _isPathVideo(firstMedia);

        return GestureDetector(
          onTap: () => _showProjectDetail(project),
          onLongPress: () => _confirmDeleteProject(project),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  isVideo
                      ? CachedVideoPlayer(
                          url: firstMedia,
                          play: false,
                        ) // Use cached player
                      : CachedNetworkImage(
                          imageUrl: firstMedia,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[100]),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        ),
                  if (isVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  if ((project['imageUrls'] as List?) != null &&
                      (project['imageUrls'] as List).length > 1)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.copy,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "${(project['imageUrls'] as List).length}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.8),
                          ],
                        ),
                      ),
                      child: Text(
                        project['description'] ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

  void _showProjectDetail(Map<String, dynamic> project) {
    final workerId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailsPage(
          workerId: workerId,
          project: project,
          workerName: _userName,
          workerProfileImage: _profileImageUrl,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteProject(Map<String, dynamic> project) async {
    if (!_isOwnProfile) return;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project?'),
        content: const Text(
          'Are you sure you want to remove this project from your profile?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 1. Delete image(s) from Firebase Storage
        final List<dynamic> imageUrls = project['imageUrls'] ?? [];
        final String? singleImageUrl = project['imageUrl'] ?? project['image'];

        if (imageUrls.isNotEmpty) {
          for (var url in imageUrls) {
            await FirebaseStorage.instance.refFromURL(url).delete();
          }
        } else if (singleImageUrl != null && singleImageUrl.isNotEmpty) {
          await FirebaseStorage.instance.refFromURL(singleImageUrl).delete();
        }

        // 2. Delete document from Firestore
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;
        await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('projects')
            .doc(project['id'])
            .delete();

        _fetchUserData();
      } catch (e) {
        debugPrint("Delete project error: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error deleting project: $e")));
        }
      }
    }
  }

  Widget _buildReviewsList(Map<String, String> strings, String localeCode) {
    final currentUser = FirebaseAuth.instance.currentUser;
    bool hasReviewed = false;
    if (currentUser != null) {
      hasReviewed = _userReviews.any((r) => r['userId'] == currentUser.uid);
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!_isOwnProfile)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: ElevatedButton.icon(
              onPressed: () => _addReview(strings),
              icon: Icon(
                hasReviewed
                    ? Icons.edit_note_outlined
                    : Icons.rate_review_outlined,
              ),
              label: Text(
                hasReviewed
                    ? strings['edit_review']!
                    : strings['write_review']!,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasReviewed
                    ? Colors.orange[800]
                    : const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        if (_userReviews.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(
                  Icons.rate_review_outlined,
                  size: 64,
                  color: Colors.grey[200],
                ),
                const SizedBox(height: 16),
                Text(
                  strings['no_reviews']!,
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          )
        else
          ..._userReviews.map((review) {
            final List<dynamic> reviewImages = review['imageUrls'] ?? [];
            final bool isMyReview =
                currentUser != null && review['userId'] == currentUser.uid;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isMyReview ? Colors.orange[200]! : Colors.grey[100]!,
                  width: isMyReview ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review['userName'] ?? 'User',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                          if (review['profession'] != null)
                            Text(
                              _translateProfessionName(
                                review['profession'].toString(),
                                localeCode,
                              ),
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          if (isMyReview)
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                size: 20,
                                color: Colors.orange,
                              ),
                              onPressed: () => _addReview(strings),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          const SizedBox(width: 8),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: i < (review['rating'] ?? 0)
                                    ? Colors.amber
                                    : Colors.grey[300],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (review['priceRating'] != null ||
                      review['workRating'] != null ||
                      review['professionalismRating'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 12,
                        children: [
                          if (review['priceRating'] != null)
                            _buildSmallRatingBadge(
                              Icons.attach_money,
                              review['priceRating'].toString(),
                            ),
                          if (review['workRating'] != null)
                            _buildSmallRatingBadge(
                              Icons.build_circle_outlined,
                              review['workRating'].toString(),
                            ),
                          if (review['professionalismRating'] != null)
                            _buildSmallRatingBadge(
                              Icons.stars_outlined,
                              review['professionalismRating'].toString(),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    review['comment'] ?? '',
                    style: TextStyle(
                      color: Colors.grey[700],
                      height: 1.5,
                      fontSize: 14,
                    ),
                  ),
                  if (reviewImages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 60,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: reviewImages.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: reviewImages[i],
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildSmallRatingBadge(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(Map<String, String> strings) {
    final currentUserId =
        widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(strings['bio_title']!),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              strings['bio']!,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Colors.grey[800],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle(strings['contact_info']!),
          const SizedBox(height: 16),
          _buildInfoCard([
            _buildInfoRow(Icons.phone_rounded, strings['call']!, _phoneNumber),
            if (_altPhoneNumber.isNotEmpty)
              _buildInfoRow(
                Icons.phone_iphone_rounded,
                "Secondary",
                _altPhoneNumber,
              ),
            _buildInfoRow(Icons.email_rounded, "Email", _email),
            _buildInfoRow(Icons.location_city_rounded, "Town", _town),
            if (_distanceStr.isNotEmpty)
              _buildInfoRow(Icons.straighten_rounded, "Distance", _distanceStr),
          ]),

          if (_isOwnProfile) ...[
            const SizedBox(height: 32),
            _buildSectionTitle(
              _userRole == 'worker'
                  ? strings['business_tools']!
                  : strings['upgrade_worker']!,
            ),
            const SizedBox(height: 16),
            if (_userRole == 'worker' && currentUserId != null)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _buildModernToolCard(
                    Icons.analytics_outlined,
                    strings['analytics']!,
                    Colors.indigo,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnalyticsPage(
                          userId: currentUserId,
                          strings: strings,
                        ),
                      ),
                    ),
                  ),
                  _buildModernToolCard(
                    Icons.description_outlined,
                    strings['invoice_builder']!,
                    Colors.teal,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoiceBuilderPage(
                            workerName: _userName,
                            workerPhone: _phoneNumber,
                            workerEmail: _email,
                          ),
                        ),
                      );
                    },
                  ),
                  if (!_isBusinessVerified)
                    _buildModernToolCard(
                      Icons.verified_user_outlined,
                      strings['verify_business']!,
                      Colors.deepOrange,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VerifyBusinessPage(),
                        ),
                      ),
                    ),
                ],
              )
            else
              _buildModernToolCard(
                Icons.upgrade_rounded,
                strings['upgrade_worker']!,
                Colors.purple,
                _upgradeToWorker,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E3A8A),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildModernToolCard(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1976D2), size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value.isNotEmpty ? value : 'N/A',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[100]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => launchUrl(Uri.parse("tel:$_phoneNumber")),
              icon: const Icon(Icons.call, size: 20),
              label: Text(strings['call']!),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                if (_isGuest()) {
                  _showGuestDialog(context, strings);
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      receiverId: widget.userId!,
                      receiverName: _userName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: Text(strings['message']!),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1976D2),
                side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'פרופיל',
          'user_name': _userName.isNotEmpty ? _userName : 'שם משתמש',
          'edit_profile': 'ערוך פרופיל',
          'projects': 'פרויקטים',
          'reviews': 'ביקורות',
          'schedule': 'לו"ז',
          'about': 'אודות',
          'bio_title': 'ביוגרפיה',
          'bio': _bio.isNotEmpty ? _bio : 'אין תיאור זמין עדיין.',
          'contact_info': 'מידע ליצירת קשר',
          'call': 'התקשר',
          'message': 'הודעה',
          'share_profile': 'שתף פרופיל',
          'write_review': 'כתוב ביקורת',
          'edit_review': 'ערוך ביקורת',
          'no_projects': 'אין פרויקטים להצגה.',
          'no_reviews': 'אין ביקורות עדיין.',
          'add': 'הוסף',
          'add_project': 'הוסף פרויקט',
          'verified_id': 'זהות מאומתת',
          'verified_biz': 'עסק מאומת',
          'insured': 'מבוטח',
          'views': 'צפיות',
          'rating': 'דירוג',
          'upgrade_worker': 'שדרג לחשבון בעל מקצוע',
          'upgrade_msg':
              'האם ברצונך להפוך לבעל מקצוע? תוכל להציג את העבודות שלך ולקבל פניות מלקוחות.',
          'confirm': 'אשר',
          'cancel': 'ביטול',
          'business_tools': 'כלי עבודה',
          'analytics': 'אנליטיקה',
          'invoice_builder': 'יוצר חשבוניות',
          'verify_business': 'אמת עסק',
          'change_business': 'עדכן פרטי עסק',
        };
      case 'ar':
        return {
          'title': 'الملف الشخصي',
          'user_name': _userName.isNotEmpty ? _userName : 'اسم المستخدم',
          'edit_profile': 'تعديل الملف الشخصي',
          'projects': 'مشاريع',
          'reviews': 'تقييمات',
          'schedule': 'الجدول',
          'about': 'حول',
          'bio_title': 'السيرة الدراسية',
          'bio': _bio.isNotEmpty ? _bio : 'لا يوجد وصف متاح بعد.',
          'contact_info': 'معلومات الاتصال',
          'call': 'اتصال',
          'message': 'رسالة',
          'share_profile': 'مشاركة الملف',
          'write_review': 'أضف تقييم',
          'edit_review': 'تعديل التقييم',
          'no_projects': 'لا توجد مشاريع.',
          'no_reviews': 'لا توجد تقييمات بعد.',
          'add': 'إضافة',
          'add_project': 'إضافة مشروع',
          'verified_id': 'هوية موثقة',
          'verified_biz': 'عمل موثق',
          'insured': 'مؤمن عليه',
          'views': 'مشاهدات',
          'rating': 'تقييم',
          'upgrade_worker': 'الترقية لحساب عامل',
          'upgrade_msg':
              'هل تريد الترقية إلى حساب عامل؟ ستتمكن من عرض مشاريعك واستقبال طلبات العملاء.',
          'confirm': 'تأكيد',
          'cancel': 'إلغاء',
          'business_tools': 'أدوات العمل',
          'analytics': 'التحليلات',
          'invoice_builder': 'منشئ الفواتير',
          'verify_business': 'توثيق العمل',
          'change_business': 'تحديث بيانات العمل',
        };
      default:
        return {
          'title': 'Profile',
          'user_name': _userName.isNotEmpty ? _userName : 'User Name',
          'edit_profile': 'Edit Profile',
          'projects': 'Projects',
          'reviews': 'Reviews',
          'schedule': 'Schedule',
          'about': 'About',
          'bio_title': 'Biography',
          'bio': _bio.isNotEmpty ? _bio : 'No description available yet.',
          'contact_info': 'Contact Information',
          'call': 'Call',
          'message': 'Message',
          'share_profile': 'Share Profile',
          'write_review': 'Write Review',
          'edit_review': 'Edit Review',
          'no_projects': 'No projects to show.',
          'no_reviews': 'No reviews yet.',
          'add': 'Add',
          'add_project': 'Add Project',
          'verified_id': 'Verified ID',
          'verified_biz': 'Verified Biz',
          'insured': 'Insured',
          'views': 'Views',
          'rating': 'Rating',
          'upgrade_worker': 'Upgrade to Worker',
          'upgrade_msg':
              'Would you like to become a worker? You will be able to showcase your work and receive inquiries.',
          'confirm': 'Confirm',
          'cancel': 'Cancel',
          'business_tools': 'Business Tools',
          'analytics': 'Analytics',
          'invoice_builder': 'Invoice Builder',
          'verify_business': 'Verify Business',
          'change_business': 'Update Business',
        };
    }
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
