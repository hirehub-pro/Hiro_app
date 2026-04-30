import 'dart:async';
import 'dart:io';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:permission_handler/permission_handler.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/services/app_permission_service.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:untitled1/sign_in.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:untitled1/pages/fullscreen_media_viewer.dart';
import 'package:untitled1/utils/profession_localization.dart';
import 'package:untitled1/widgets/cached_video_player.dart';
import 'package:untitled1/ptofile.dart';

const Color _uiPrimaryBlue = Color(0xFF1976D2);
const Color _uiSurfaceBackground = Color(0xFFF7FBFF);
const Color _uiSoftSurface = Color(0xFFF8FAFC);
const Color _uiBorder = Color(0xFFE2E8F0);
const Color _uiTitle = Color(0xFF0F172A);
const Color _uiBody = Color(0xFF334155);
const Color _uiMuted = Color(0xFF64748B);

List<String> _mediaUrlsFromPost(Map<String, dynamic>? post) {
  if (post == null) return const [];

  final imageUrls = post['imageUrls'];
  if (imageUrls is Iterable) {
    final urls = imageUrls
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
    if (urls.isNotEmpty) return urls;
  }

  final imageUrl = post['imageUrl']?.toString().trim() ?? '';
  return imageUrl.isEmpty ? const [] : [imageUrl];
}

class BlogPage extends StatefulWidget {
  const BlogPage({super.key});

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  static const String _myProfessionFilterValue = '__my_profession__';
  static const double _myRadiusFilterValue = -1;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _postsSubscription;
  LatLng? _viewerLocation;
  List<Map<String, dynamic>> _professionItems = [];
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isMoreLoading = false;
  int _postLimit = 10;
  final Set<String> _hiddenPostIds = {};
  final Set<String> _blockedUserIds = {};
  String _sortBy = 'newest';
  int _selectedFilterIndex = 0;
  bool _showOnlyLikedPosts = false;
  bool _showOnlyMyPosts = false;
  bool _isGuideExpanded = false;
  String _jobRequestProfessionFilter = '';
  double _jobRequestRadiusFilterKm = 0;
  final Set<String> _myProfessions = <String>{};
  double _myWorkRadiusKm = 25;
  bool _isCheckingUgcTerms = true;
  bool _hasAcceptedUgcTerms = false;

  @override
  void initState() {
    super.initState();
    _loadProfessionMetadata();
    _loadMyJobRequestFilterProfile();
    _loadViewerLocation();
    _loadUgcTermsStatus();
    _loadBlockedUsers();
    _listenToPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _postsSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
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

  Future<void> _loadViewerLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _viewerLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {}
  }

  String? _distanceLabelForPost(Map<String, dynamic> post) {
    final meters = _distanceMetersForPost(post);
    if (meters == null) return null;

    if (meters < 1000) {
      return "${meters.round()} m";
    }

    return "${(meters / 1000).toStringAsFixed(1)} km";
  }

  double? _distanceMetersForPost(Map<String, dynamic> post) {
    if (_viewerLocation == null ||
        post['locationLat'] == null ||
        post['locationLng'] == null) {
      return null;
    }

    final lat = (post['locationLat'] as num).toDouble();
    final lng = (post['locationLng'] as num).toDouble();
    return Geolocator.distanceBetween(
      _viewerLocation!.latitude,
      _viewerLocation!.longitude,
      lat,
      lng,
    );
  }

  Future<void> _loadProfessionMetadata() async {
    try {
      final snapshot = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final data = snapshot.data();
      final rawItems = data?['items'];
      if (rawItems is! List) return;

      final items =
          rawItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => _professionCanonicalValue(item).isNotEmpty)
              .toList()
            ..sort((a, b) {
              final aId = (a['id'] as num?)?.toInt() ?? 1 << 30;
              final bId = (b['id'] as num?)?.toInt() ?? 1 << 30;
              if (aId != bId) return aId.compareTo(bId);
              return _professionCanonicalValue(
                a,
              ).compareTo(_professionCanonicalValue(b));
            });

      if (!mounted) return;
      setState(() => _professionItems = items);
    } catch (e) {
      debugPrint('Failed to load profession metadata: $e');
    }
  }

  Future<void> _loadMyJobRequestFilterProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) return;

      final snapshot = await _firestore.collection('users').doc(user.uid).get();
      final data = snapshot.data();
      if (data == null) return;

      final myProfessions = <String>{};

      final professionsRaw = data['professions'];
      if (professionsRaw is List) {
        for (final item in professionsRaw) {
          final normalized = _normalizeStoredProfession(item.toString());
          if (normalized.isNotEmpty) {
            myProfessions.add(normalized.toLowerCase());
          }
        }
      }

      final singleProfession = (data['profession'] ?? '').toString().trim();
      if (singleProfession.isNotEmpty) {
        final normalized = _normalizeStoredProfession(singleProfession);
        if (normalized.isNotEmpty) {
          myProfessions.add(normalized.toLowerCase());
        }
      }

      double myWorkRadiusKm = 25;
      final rawRadius = data['workRadius'];
      if (rawRadius is num && rawRadius.toDouble() > 0) {
        final radiusValue = rawRadius.toDouble();
        myWorkRadiusKm = radiusValue > 1000 ? radiusValue / 1000 : radiusValue;
      } else if (rawRadius != null) {
        final parsed = double.tryParse(rawRadius.toString());
        if (parsed != null && parsed > 0) {
          myWorkRadiusKm = parsed > 1000 ? parsed / 1000 : parsed;
        }
      }

      if (!mounted) return;
      setState(() {
        _myProfessions
          ..clear()
          ..addAll(myProfessions);
        _myWorkRadiusKm = myWorkRadiusKm;
      });
    } catch (e) {
      debugPrint('Failed to load current user request filter profile: $e');
    }
  }

  String _professionCanonicalValue(Map<String, dynamic> item) {
    final english = item['en']?.toString().trim();
    if (english != null && english.isNotEmpty) return english;

    for (final key in const ['he', 'ar', 'ru', 'am']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic>? _findProfessionItem(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final item in _professionItems) {
      for (final key in const ['en', 'he', 'ar', 'ru', 'am']) {
        final candidate = item[key]?.toString().trim().toLowerCase();
        if (candidate != null &&
            candidate.isNotEmpty &&
            candidate == normalized) {
          return item;
        }
      }
    }
    return null;
  }

  String _normalizeStoredProfession(String value) {
    final item = _findProfessionItem(value);
    if (item != null) {
      return _professionCanonicalValue(item);
    }
    return ProfessionLocalization.toCanonical(value);
  }

  String _professionLabel(Map<String, dynamic> item, String localeCode) {
    final localized = item[localeCode]?.toString().trim();
    if (localized != null && localized.isNotEmpty) return localized;
    return _professionCanonicalValue(item);
  }

  DateTime? _extractDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  TimeOfDay? _extractTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isJobRequestSectionActive(Map<String, dynamic> strings) {
    final categories = (strings['categories'] as List?) ?? const [];
    if (_selectedFilterIndex < 0 || _selectedFilterIndex >= categories.length) {
      return false;
    }
    return _isJobRequestCategoryValue(
      categories[_selectedFilterIndex].toString(),
    );
  }

  bool _matchesJobRequestFilters(
    Map<String, dynamic> post,
    Map<String, dynamic> strings,
  ) {
    if (!_isJobRequestSectionActive(strings)) return true;

    final isJobRequest =
        post['isJobRequest'] == true ||
        _isJobRequestCategoryValue((post['category'] ?? '').toString());
    if (!isJobRequest) return true;

    if (_jobRequestProfessionFilter == _myProfessionFilterValue) {
      if (_myProfessions.isNotEmpty) {
        final raw = (post['professionLabel'] ?? post['profession'] ?? '')
            .toString()
            .trim();
        final normalized = _normalizeStoredProfession(raw).toLowerCase();
        if (!_myProfessions.contains(normalized)) {
          return false;
        }
      }
    } else if (_jobRequestProfessionFilter.isNotEmpty) {
      final raw = (post['professionLabel'] ?? post['profession'] ?? '')
          .toString()
          .trim();
      final normalized = _normalizeStoredProfession(raw);
      if (normalized.toLowerCase() !=
          _jobRequestProfessionFilter.toLowerCase()) {
        return false;
      }
    }

    if (_jobRequestRadiusFilterKm == _myRadiusFilterValue &&
        _viewerLocation != null &&
        _myWorkRadiusKm > 0) {
      final meters = _distanceMetersForPost(post);
      if (meters == null || meters > (_myWorkRadiusKm * 1000)) {
        return false;
      }
    } else if (_jobRequestRadiusFilterKm > 0 && _viewerLocation != null) {
      final meters = _distanceMetersForPost(post);
      if (meters == null || meters > (_jobRequestRadiusFilterKm * 1000)) {
        return false;
      }
    }

    return true;
  }

  List<MapEntry<String, String>> _jobRequestProfessionChoices(
    String localeCode,
  ) {
    final byValue = <String, String>{};

    for (final item in _professionItems) {
      final value = _professionCanonicalValue(item).trim();
      if (value.isEmpty) continue;
      byValue[value] = _professionLabel(item, localeCode);
    }

    if (byValue.isEmpty) {
      for (final post in _posts) {
        final raw = (post['professionLabel'] ?? post['profession'] ?? '')
            .toString()
            .trim();
        if (raw.isEmpty) continue;
        final value = _normalizeStoredProfession(raw);
        if (value.isEmpty) continue;
        byValue[value] = value;
      }
    }

    final entries =
        byValue.entries
            .map((entry) => MapEntry(entry.key, entry.value))
            .toList()
          ..sort(
            (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
          );
    return entries;
  }

  Widget _buildJobRequestFilters(
    Map<String, dynamic> strings,
    String localeCode,
  ) {
    final professionChoices = _jobRequestProfessionChoices(localeCode);
    final hasMyRadius = _myWorkRadiusKm > 0;
    const radiusChoices = <double>[0, _myRadiusFilterValue];
    final radiusDescription = _jobRequestRadiusFilterKm == 0
        ? (strings['filter_any_radius'] ?? 'Any radius')
        : hasMyRadius
        ? (strings['filter_my_radius_value'] ?? 'My radius: {val} km')
              .replaceFirst('{val}', _myWorkRadiusKm.toStringAsFixed(0))
        : (strings['filter_my_radius_unavailable'] ??
              'My radius is not available');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _jobRequestProfessionFilter,
                  decoration: InputDecoration(
                    labelText: strings['filter_profession'] ?? 'Profession',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        strings['filter_all_professions'] ?? 'All professions',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _myProfessionFilterValue,
                      child: Text(
                        strings['filter_my_profession'] ?? 'My profession',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...professionChoices.map(
                      (choice) => DropdownMenuItem(
                        value: choice.key,
                        child: Text(
                          choice.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _jobRequestProfessionFilter = value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<double>(
                  isExpanded: true,
                  initialValue: _jobRequestRadiusFilterKm,
                  decoration: InputDecoration(
                    labelText: strings['filter_radius'] ?? 'Work radius',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  items: radiusChoices
                      .map(
                        (radiusKm) => DropdownMenuItem<double>(
                          value: radiusKm,
                          child: Text(
                            radiusKm == 0
                                ? (strings['filter_any_radius'] ?? 'Any radius')
                                : hasMyRadius
                                ? (strings['filter_my_radius_value'] ??
                                          'My radius: {val} km')
                                      .replaceFirst(
                                        '{val}',
                                        _myWorkRadiusKm.toStringAsFixed(0),
                                      )
                                : (strings['filter_my_radius_unavailable'] ??
                                      'My radius is not available'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _jobRequestRadiusFilterKm = value);
                  },
                ),
              ),
            ],
          ),
          if (_jobRequestProfessionFilter == _myProfessionFilterValue &&
              _myProfessions.isEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                strings['my_profession_not_set'] ??
                    'Set your profession in profile to use this filter',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (_viewerLocation == null &&
              _jobRequestRadiusFilterKm == _myRadiusFilterValue) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                strings['radius_requires_location'] ??
                    'Enable location to apply radius filter',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                radiusDescription,
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
    );
  }

  void _listenToPosts() {
    _postsSubscription?.cancel();

    Query query = _firestore.collection('blog_posts');
    if (_selectedFilterIndex > 0 &&
        _selectedFilterIndex < _categoryAliases.length) {
      query = query.where(
        'category',
        whereIn: _categoryAliases[_selectedFilterIndex],
      );
    }

    query = query.orderBy('isPinned', descending: true);

    if (_sortBy == 'newest') {
      query = query.orderBy('timestamp', descending: true);
    } else if (_sortBy == 'likes') {
      query = query.orderBy('likes', descending: true);
    }

    _postsSubscription = query
        .limit(_postLimit)
        .snapshots()
        .listen(
          (snapshot) async {
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
          },
          onError: (error) {
            debugPrint("FETCH ERROR: $error");
            if (mounted) {
              setState(() {
                _posts = [];
                _isLoading = false;
                _isMoreLoading = false;
              });
            }
          },
        );
  }

  Future<void> _loadUgcTermsStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      if (!mounted) return;
      setState(() {
        _isCheckingUgcTerms = false;
        _hasAcceptedUgcTerms = true;
      });
      return;
    }

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final accepted = data['ugcTermsAcceptedAt'] != null;
      if (!mounted) return;
      setState(() {
        _hasAcceptedUgcTerms = accepted;
        _isCheckingUgcTerms = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingUgcTerms = false);
    }
  }

  Future<void> _acceptUgcTerms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showGuestDialog(context, _getLocalizedStrings(context));
      return;
    }
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'ugcTermsAcceptedAt': FieldValue.serverTimestamp(),
        'ugcTermsVersion': '2026-04-29',
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _hasAcceptedUgcTerms = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_getLocalizedStrings(context)['error']}')),
      );
      debugPrint('Failed to accept UGC terms: $e');
    }
  }

  Future<void> _loadBlockedUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('blocked_users')
          .get();
      final blockedIds = snapshot.docs.map((d) => d.id).toSet();
      if (!mounted) return;
      setState(() {
        _blockedUserIds
          ..clear()
          ..addAll(blockedIds);
      });
    } catch (e) {
      debugPrint('Failed loading blocked users: $e');
    }
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final strings = _getLocalizedStrings(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showGuestDialog(context, strings);
      return;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['report_content_title'] ?? 'Report content'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText:
                strings['report_reason_hint'] ?? 'Describe what is wrong...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['cancel']),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reasonController.text),
            child: Text(strings['submit_report'] ?? 'Submit report'),
          ),
        ],
      ),
    );

    if (reason == null || reason.trim().isEmpty) return;

    try {
      final trimmedReason = reason.trim();
      final postTitle = (post['title'] ?? '').toString().trim();
      final postAuthorUid = (post['authorUid'] ?? '').toString().trim();

      await _firestore.collection('reports').add({
        'reporterId': user.uid,
        'reportedId': postAuthorUid,
        'reportType': 'content_report',
        'source': 'post_report',
        'subject': 'Content Problem',
        'reason': trimmedReason,
        'details': postTitle.isEmpty
            ? 'Reported from a post in the feed.'
            : 'Reported post: $postTitle',
        'postId': post['id'],
        'postAuthorUid': postAuthorUid,
        'postTitle': postTitle,
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('metadata').doc('system').set({
        'reportsCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings['report_submitted'] ?? 'Report submitted to moderation',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed reporting content: $e');
    }
  }

  Future<void> _blockUserFromPost(Map<String, dynamic> post) async {
    final strings = _getLocalizedStrings(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      _showGuestDialog(context, strings);
      return;
    }
    final blockedUid = (post['authorUid'] ?? '').toString();
    if (blockedUid.isEmpty || blockedUid == user.uid) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['block_user'] ?? 'Block user'),
        content: Text(
          strings['block_user_confirm'] ??
              'This user will be removed from your feed immediately and sent to moderation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings['cancel']),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings['block_user'] ?? 'Block user'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      setState(() {
        _blockedUserIds.add(blockedUid);
      });
    }

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('blocked_users')
          .doc(blockedUid)
          .set({
            'blockedAt': FieldValue.serverTimestamp(),
            'samplePostId': post['id'],
          });
      final postTitle = (post['title'] ?? '').toString().trim();
      await _firestore.collection('reports').add({
        'reporterId': user.uid,
        'reportedId': blockedUid,
        'reportType': 'user_block',
        'source': 'post_block',
        'subject': 'Blocked User',
        'reason': strings['block_user_confirm'] ?? 'User blocked from a post',
        'details': postTitle.isEmpty
            ? 'User blocked from a post in the feed.'
            : 'Blocked after viewing post: $postTitle',
        'blockedUid': blockedUid,
        'reportedUserUid': blockedUid,
        'samplePostId': post['id'],
        'postId': post['id'],
        'postTitle': postTitle,
        'blockedByUid': user.uid,
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('metadata').doc('system').set({
        'reportsCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings['blocked_user_hidden'] ??
                'User blocked and removed from your feed',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed blocking user: $e');
    }
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

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.avi') ||
        lower.contains('.mkv') ||
        lower.contains('.webm');
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return _hebrewStrings();
      case 'ar':
        return _arabicStrings();
      case 'am':
        return _amharicStrings();
      case 'ru':
        return _russianStrings();
      default:
        return _englishStrings();
    }
  }

  Map<String, dynamic> _hebrewStrings() {
    final strings = _englishStrings();
    strings.addAll({
      'title': 'קהילה ודרושים',
      'search_hint': 'חפש בפוסטים...',
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
      'post_actions': 'פעולות בפוסט',
      'report': 'דווח',
      'hide': 'הסתר',
      'edit': 'ערוך',
      'comments': 'תגובות / הצעות',
      'add_comment': 'הוסף תגובה או הצעה...',
      'bid_price': 'מחיר מוצע',
      'bid_price_hint': 'למשל 350',
      'send_bid': 'שלח הצעת מחיר',
      'update_bid': 'עדכן הצעת מחיר',
      'edit_your_bid': 'ניתן לעדכן את ההצעה הקיימת שלכם.',
      'choose_worker': 'בחר בעל מקצוע',
      'confirm_choose_worker_title': 'לבחור בעל מקצוע זה?',
      'confirm_choose_worker_body':
          'הבחירה תסמן את בעל המקצוע כהצעה שנבחרה עבור הבקשה הזו.',
      'selected_worker': 'בעל מקצוע נבחר',
      'selected_offer': 'הצעה נבחרה',
      'offer_price': 'מחיר מוצע',
      'workers_can_offer':
          'בעלי מקצוע יכולים להציע מחיר, ואתם יכולים לבחור את המתאים לכם.',
      'job_request_comment_restriction':
          'רק בעלי מקצוע עם מנוי פעיל יכולים להגיב לבקשות עבודה.',
      'rating': 'דירוג',
      'reviews': 'ביקורות',
      'author': 'מפרסם',
      'posted': 'פורסם',
      'sort': 'מיין לפי',
      'newest': 'הכי חדש',
      'most_liked': 'הכי הרבה לייקים',
      'guest_msg': 'עליך להירשם כדי לבצע פעולה זו',
      'login': 'התחברות',
      'error': 'שגיאה: חסרה הרשאה או בעיית תקשורת',
      'empty_fields': 'נא למלא כותרת ותוכן',
      'location': 'מיקום (עיר/אזור)',
      'job_request': 'דרוש בעל מקצוע',
      'profession': 'מקצוע',
      'profession_hint': 'בחר בעל מקצוע נדרש',
      'profession_required': 'נא לבחור מקצוע',
      'filter_profession': 'סינון לפי מקצוע',
      'filter_all_professions': 'כל המקצועות',
      'filter_my_profession': 'המקצוע שלי',
      'my_profession_not_set': 'הגדר מקצוע בפרופיל כדי להשתמש במסנן הזה',
      'filter_radius': 'סינון לפי רדיוס',
      'filter_any_radius': 'כל רדיוס',
      'filter_my_radius_value': 'הרדיוס שלי: {val} ק"מ',
      'filter_my_radius_unavailable': 'הרדיוס שלי לא זמין',
      'radius_requires_location': 'יש להפעיל מיקום כדי לסנן לפי רדיוס',
      'use_current_location': 'השתמש במיקום נוכחי',
      'choose_from_map': 'בחר מהמפה',
      'selected_location': 'המיקום שנבחר',
      'change_location': 'שנה מיקום',
      'location_loading': 'מאתר מיקום...',
      'date_from': 'מתאריך',
      'date_to': 'עד תאריך',
      'date_anytime': 'אם לא תבחר תאריכים, הבקשה תיחשב לכל זמן',
      'select_date': 'בחר תאריך',
      'time_from': 'משעה',
      'time_to': 'עד שעה',
      'time_anytime': 'אם לא תבחר שעות, הבקשה תיחשב לכל שעה',
      'add_video': 'הוסף וידאו',
      'media_limit': 'ניתן להעלות עד 5 תמונות/סרטונים',
      'gallery': 'גלריה',
      'camera': 'מצלמה',
      'guide_title': 'איך זה עובד?',
      'guide_content':
          '• שתפו שאלות, טיפים והמלצות.\n• צריכים עבודה? פרסמו "דרוש בעל מקצוע".\n• בעלי מקצוע? הציעו שירות בתגובות.\n• סננו לפי קטגוריה או מיין לפי פופולריות.',
      'featured_articles': 'מדריכים ומאמרים',
      'share_article': 'שתף מאמר',
      'anonymous': 'אנונימי',
      'user_fallback': 'משתמש',
      'user_not_signed_in': 'המשתמש אינו מחובר',
      'location_services_disabled': 'שירותי המיקום כבויים.',
      'location_permissions_denied': 'הרשאות המיקום נדחו.',
      'location_permissions_permanently_denied': 'הרשאות המיקום נדחו לצמיתות.',
      'generic_error_prefix': 'שגיאה',
      'articles': [
        {
          'title': 'איך להשיג יותר לקוחות',
          'subtitle': 'אסטרטגיות לבעלי מקצוע',
          'icon': Icons.trending_up,
          'color': Colors.green,
          'content':
              '1. תמונת פרופיל ברורה ומקצועית.\n2. העלאת פרויקטים איכותיים (לפני ואחרי).\n3. מענה מהיר (פחות מ-15 דקות משפר המרה ב-40%).\n4. בקשו ביקורות בסיום כל עבודה.',
        },
        {
          'title': 'בחירת בעל מקצוע נכון',
          'subtitle': 'טיפים ללקוחות',
          'icon': Icons.verified_user,
          'color': Colors.blue,
          'content':
              '1. חפשו את תג "עסק מאומת".\n2. קראו ביקורות עדכניות.\n3. השוו מחירים אך אל תבחרו רק לפי המחיר הזול ביותר.\n4. ודאו שיש ביטוח בתוקף.',
        },
        {
          'title': 'כתיבת פוסט מוצלח',
          'subtitle': 'לקבלת תוצאות טובות',
          'icon': Icons.edit_note,
          'color': Colors.orange,
          'content':
              'כותרת: ציינו את סוג העבודה.\nתוכן: ציינו מיקום ולו"ז.\nתמונות: צלמו את אזור העבודה באור יום.',
        },
        {
          'title': 'היתרון של עסק מאומת',
          'subtitle': 'למה כדאי לאמת?',
          'icon': Icons.verified,
          'color': Colors.indigo,
          'content':
              'עסקים מאומתים זוכים ליותר חשיפה ב-300% ומקבלים תג כחול שמעניק ביטחון ללקוחות. האימות כולל בדיקת תעודת זהות ורישום עסק.',
        },
      ],
    });
    return strings;
  }

  Map<String, dynamic> _arabicStrings() {
    final strings = _englishStrings();
    strings.addAll({
      'title': 'المجتمع والوظائف',
      'search_hint': 'ابحث في المنشورات...',
      'create_post': 'انشر في المجتمع',
      'edit_post': 'تعديل المنشور',
      'post_title': 'العنوان',
      'post_category': 'نوع المنشور',
      'post_content': 'ماذا تريد أن تشارك؟',
      'publish': 'نشر',
      'update': 'تحديث',
      'cancel': 'إلغاء',
      'categories': ['الكل', 'سؤال', 'نصيحة', 'طلب عامل', 'توصية', 'أخرى'],
      'upload_photo': 'إضافة صور',
      'no_posts': 'لا توجد منشورات بعد',
      'delete': 'حذف',
      'share': 'مشاركة',
      'post_actions': 'إجراءات المنشور',
      'hide': 'إخفاء',
      'comments': 'تعليقات / عروض',
      'add_comment': 'أضف تعليقًا أو عرضًا...',
      'bid_price': 'السعر المقترح',
      'bid_price_hint': 'مثال: 350',
      'send_bid': 'إرسال عرض السعر',
      'update_bid': 'تحديث عرض السعر',
      'edit_your_bid': 'يمكنك تحديث عرض السعر الحالي.',
      'choose_worker': 'اختر عاملًا',
      'confirm_choose_worker_title': 'اختيار هذا العامل؟',
      'confirm_choose_worker_body':
          'سيتم تحديد هذا العامل كالعرض المختار لهذا الطلب.',
      'selected_worker': 'العامل المختار',
      'selected_offer': 'العرض المختار',
      'offer_price': 'السعر المعروض',
      'workers_can_offer':
          'يمكن للعمال تقديم عروض سعر هنا، ويمكنك اختيار الأنسب لك.',
      'job_request_comment_restriction':
          'يمكن فقط للعمال أصحاب الاشتراك النشط التعليق على طلبات العمل.',
      'author': 'الناشر',
      'posted': 'تاريخ النشر',
      'newest': 'الأحدث',
      'most_liked': 'الأكثر إعجابًا',
      'login': 'تسجيل الدخول',
      'empty_fields': 'يرجى تعبئة العنوان والمحتوى',
      'location': 'الموقع (المدينة/المنطقة)',
      'profession': 'المهنة',
      'profession_hint': 'اختر المهنة المطلوبة',
      'profession_required': 'يرجى اختيار مهنة',
      'filter_profession': 'تصفية حسب المهنة',
      'filter_all_professions': 'كل المهن',
      'filter_my_profession': 'مهنتي',
      'my_profession_not_set': 'حدّد مهنتك في الملف الشخصي لاستخدام هذا الفلتر',
      'filter_radius': 'تصفية حسب النطاق',
      'filter_any_radius': 'أي نطاق',
      'filter_my_radius_value': 'نطاقي: {val} كم',
      'filter_my_radius_unavailable': 'نطاقي غير متاح',
      'radius_requires_location': 'فعّل الموقع لتفعيل التصفية حسب النطاق',
      'use_current_location': 'استخدم الموقع الحالي',
      'choose_from_map': 'اختر من الخريطة',
      'selected_location': 'الموقع المختار',
      'date_from': 'من تاريخ',
      'date_to': 'إلى تاريخ',
      'time_from': 'من ساعة',
      'time_to': 'إلى ساعة',
      'add_video': 'إضافة فيديو',
      'gallery': 'المعرض',
      'camera': 'الكاميرا',
      'guide_title': 'كيف يعمل؟',
      'guide_content':
          '• شارك الأسئلة والنصائح والتوصيات.\n• تحتاج إلى مختص؟ انشر "طلب عامل".\n• هل أنت صاحب مهنة؟ قدّم خدمتك في التعليقات.\n• صفِّ حسب الفئة أو رتّب حسب الشعبية.',
      'featured_articles': 'أدلة ومقالات',
      'share_article': 'مشاركة المقال',
      'anonymous': 'مجهول',
      'user_fallback': 'مستخدم',
      'user_not_signed_in': 'المستخدم غير مسجل الدخول',
      'location_services_disabled': 'خدمات الموقع غير مفعلة.',
      'location_permissions_denied': 'تم رفض أذونات الموقع.',
      'location_permissions_permanently_denied':
          'تم رفض أذونات الموقع بشكل دائم.',
      'generic_error_prefix': 'خطأ',
      'articles': [
        {
          'title': 'زيادة أرباحك',
          'subtitle': 'استراتيجيات لأصحاب المهن',
          'icon': Icons.trending_up,
          'color': Colors.green,
          'content':
              '1. صورة شخصية واضحة واحترافية.\n2. صور مشاريع عالية الجودة (قبل/بعد).\n3. سرعة الرد (أقل من 15 دقيقة ترفع التحويل بنسبة 40%).\n4. اطلب تقييمًا بعد كل عمل ناجح.',
        },
        {
          'title': 'اختيار المهني المناسب',
          'subtitle': 'نصائح للعملاء',
          'icon': Icons.verified_user,
          'color': Colors.blue,
          'content':
              '1. ابحث عن شارة "نشاط موثّق".\n2. اقرأ التقييمات الحديثة وليس الرقم فقط.\n3. قارن الأسعار وتجنب العروض غير المنطقية.\n4. تأكد من وجود تأمين في الأعمال الكبيرة.',
        },
        {
          'title': 'كتابة منشور ممتاز',
          'subtitle': 'للحصول على عروض دقيقة',
          'icon': Icons.edit_note,
          'color': Colors.orange,
          'content':
              'العنوان: اذكر المهمة الأساسية.\nالمحتوى: أضف الموقع والوقت المناسب لك.\nالصور: التقط صورًا واضحة للمكان في ضوء النهار.',
        },
        {
          'title': 'توثيق النشاط التجاري',
          'subtitle': 'لماذا التوثيق مهم؟',
          'icon': Icons.verified,
          'color': Colors.indigo,
          'content':
              'النشاطات الموثقة تحصل على ظهور أعلى بنسبة 300% وشارة زرقاء تعزز الثقة. يشمل التوثيق فحص الهوية والتسجيل التجاري.',
        },
      ],
    });
    return strings;
  }

  Map<String, dynamic> _amharicStrings() {
    final strings = _englishStrings();
    strings.addAll({
      'title': 'ማህበረሰብ እና ስራዎች',
      'search_hint': 'ፖስቶችን ፈልግ...',
      'create_post': 'በማህበረሰብ ውስጥ ፖስት አድርግ',
      'edit_post': 'ፖስት አርትዕ',
      'post_title': 'ርዕስ',
      'post_category': 'ምድብ',
      'post_content': 'ምን ማጋራት ትፈልጋለህ?',
      'publish': 'አትም',
      'update': 'አዘምን',
      'cancel': 'ሰርዝ',
      'categories': ['ሁሉም', 'ጥያቄ', 'ምክር', 'የስራ ጥያቄ', 'ምክር ሰጪ', 'ሌላ'],
      'upload_photo': 'ፎቶ ጨምር',
      'no_posts': 'እስካሁን ፖስቶች የሉም',
      'delete': 'ሰርዝ',
      'share': 'አጋራ',
      'post_actions': 'የፖስት እርምጃዎች',
      'hide': 'ደብቅ',
      'comments': 'አስተያየቶች / ቅናሾች',
      'add_comment': 'አስተያየት ወይም ቅናሽ ጨምር...',
      'bid_price': 'የቅናሽ ዋጋ',
      'send_bid': 'ቅናሽ ላክ',
      'update_bid': 'ቅናሽ አዘምን',
      'edit_your_bid': 'ያለዎትን ቅናሽ ማዘምን ይችላሉ።',
      'choose_worker': 'ሰራተኛ ምረጥ',
      'confirm_choose_worker_title': 'ይህን ሰራተኛ ይምረጡ?',
      'confirm_choose_worker_body':
          'ይህ ሰራተኛ ለዚህ የስራ ጥያቄ የተመረጠ ቅናሽ እንዲሆን ያደርጋል።',
      'selected_worker': 'የተመረጠ ሰራተኛ',
      'selected_offer': 'የተመረጠ ቅናሽ',
      'offer_price': 'የቀረበ ዋጋ',
      'workers_can_offer': 'ሰራተኞች እዚህ ዋጋ ማቅረብ ይችላሉ፣ እርስዎም የሚስማማውን መምረጥ ይችላሉ።',
      'job_request_comment_restriction':
          'በንቁ ምዝገባ ያላቸው ሰራተኞች ብቻ በስራ ጥያቄዎች ላይ አስተያየት ሊሰጡ ይችላሉ።',
      'bid_price_hint': 'ለምሳሌ 350',
      'location': 'አካባቢ (ከተማ/አካባቢ)',
      'profession': 'ሙያ',
      'date_from': 'ከቀን',
      'time_from': 'ከሰዓት',
      'author': 'አታሚ',
      'posted': 'ታተመ',
      'newest': 'አዲስ',
      'most_liked': 'ብዙ የተወደደ',
      'login': 'ግባ',
      'guide_title': 'እንዴት ይሰራል?',
      'guide_content':
          '• ጥያቄዎችን፣ ምክሮችን እና ማስተላለፊያዎችን ያጋሩ።\n• ባለሙያ ያስፈልጋል? "የስራ ጥያቄ" ያትሙ።\n• ባለሙያ ነህ? አገልግሎትህን በአስተያየቶች ውስጥ አቅርብ።\n• በምድብ ማጣራት ወይም በታዋቂነት መደርደር ትችላለህ።',
      'featured_articles': 'መመሪያዎች እና ጽሑፎች',
      'share_article': 'ጽሑፍ አጋራ',
      'anonymous': 'ስም የሌለው',
      'user_fallback': 'ተጠቃሚ',
      'user_not_signed_in': 'ተጠቃሚው አልገባም',
      'location_services_disabled': 'የአካባቢ አገልግሎቶች ተዘግተዋል።',
      'location_permissions_denied': 'የአካባቢ ፍቃድ ተከልክሏል።',
      'location_permissions_permanently_denied': 'የአካባቢ ፍቃድ ለዘላለም ተከልክሏል።',
      'generic_error_prefix': 'ስህተት',
      'articles': [
        {
          'title': 'ገቢዎን እንዴት መጨመር',
          'subtitle': 'ለባለሙያዎች ስትራቴጂ',
          'icon': Icons.trending_up,
          'color': Colors.green,
          'content':
              '1. ግልጽ እና ሙያዊ ፕሮፋይል ፎቶ ይጠቀሙ።\n2. ከፍተኛ ጥራት ያላቸው የፕሮጀክት ፎቶዎች (በፊት/በኋላ) ያቅርቡ።\n3. ፈጣን ምላሽ ይስጡ (ከ15 ደቂቃ በታች 40% የለውጥ መጠን ያሻሽላል)።\n4. ስራ ከተጠናቀቀ በኋላ ግምገማ ይጠይቁ።',
        },
        {
          'title': 'ትክክለኛ ባለሙያ መምረጥ',
          'subtitle': 'ለደንበኞች ምክሮች',
          'icon': Icons.verified_user,
          'color': Colors.blue,
          'content':
              '1. "የተረጋገጠ ንግድ" ምልክት ይፈልጉ።\n2. የቅርብ ጊዜ ግምገማዎችን ያንብቡ።\n3. ዋጋዎችን ያነጻጽሩ ነገር ግን በጣም ዝቅተኛ ዋጋ ብቻ አትመርጡ።\n4. ለትልቅ ስራዎች ኢንሹራንስ እንዳለ ያረጋግጡ።',
        },
        {
          'title': 'ጥሩ የስራ ፖስት መፃፍ',
          'subtitle': 'ትክክለኛ ቅናሾች ለማግኘት',
          'icon': Icons.edit_note,
          'color': Colors.orange,
          'content':
              'ርዕስ: ዋናውን ተግባር ይግለጹ።\nይዘት: ቦታ እና የሚመችዎትን ጊዜ ያካትቱ።\nፎቶ: ቦታውን በቀን ብርሃን ግልጽ ፎቶ ያንሱ።',
        },
        {
          'title': 'የንግድ ማረጋገጫ',
          'subtitle': 'ለምን መረጋገጥ ይጠቅማል?',
          'icon': Icons.verified,
          'color': Colors.indigo,
          'content':
              'የተረጋገጡ ንግዶች 300% ተጨማሪ ታይነት ያገኛሉ እና የደንበኛ እምነት የሚያጠናክር ሰማያዊ ምልክት ይቀበላሉ። ማረጋገጫው የመታወቂያ እና የንግድ ምዝገባ ምርመራ ያካትታል።',
        },
      ],
    });
    return strings;
  }

  Map<String, dynamic> _russianStrings() {
    final strings = _englishStrings();
    strings.addAll({
      'title': 'Сообщество и заказы',
      'search_hint': 'Поиск по публикациям...',
      'create_post': 'Опубликовать',
      'edit_post': 'Редактировать публикацию',
      'post_title': 'Заголовок',
      'post_category': 'Категория',
      'post_content': 'Чем хотите поделиться?',
      'publish': 'Опубликовать',
      'update': 'Обновить',
      'cancel': 'Отмена',
      'categories': [
        'Все',
        'Вопрос',
        'Совет',
        'Запрос на работу',
        'Рекомендация',
        'Другое',
      ],
      'upload_photo': 'Добавить фото',
      'no_posts': 'Публикаций пока нет',
      'delete': 'Удалить',
      'share': 'Поделиться',
      'post_actions': 'Действия с постом',
      'hide': 'Скрыть',
      'comments': 'Комментарии / Предложения',
      'add_comment': 'Добавить комментарий или предложение...',
      'bid_price': 'Цена предложения',
      'send_bid': 'Отправить предложение',
      'update_bid': 'Обновить предложение',
      'edit_your_bid': 'Вы можете обновить ваше текущее предложение.',
      'choose_worker': 'Выбрать специалиста',
      'confirm_choose_worker_title': 'Выбрать этого специалиста?',
      'confirm_choose_worker_body':
          'Этот специалист будет отмечен как выбранное предложение для этого запроса.',
      'selected_worker': 'Выбранный специалист',
      'selected_offer': 'Выбранное предложение',
      'offer_price': 'Предложенная цена',
      'workers_can_offer':
          'Специалисты могут оставлять здесь предложения, а вы можете выбрать подходящее.',
      'job_request_comment_restriction':
          'Только специалисты с активной подпиской могут комментировать запросы на работу.',
      'bid_price_hint': 'Например, 350',
      'location': 'Местоположение (город/район)',
      'profession': 'Профессия',
      'date_from': 'С даты',
      'time_from': 'С времени',
      'author': 'Автор',
      'posted': 'Опубликовано',
      'newest': 'Новые',
      'most_liked': 'Популярные',
      'login': 'Войти',
      'guide_title': 'Как это работает?',
      'guide_content':
          '• Делитесь вопросами, советами и рекомендациями.\n• Нужен специалист? Опубликуйте "Запрос на работу".\n• Вы специалист? Предлагайте услуги в комментариях.\n• Фильтруйте по категории или сортируйте по популярности.',
      'featured_articles': 'Гайды и статьи',
      'share_article': 'Поделиться статьей',
      'anonymous': 'Аноним',
      'user_fallback': 'Пользователь',
      'user_not_signed_in': 'Пользователь не вошел в систему',
      'location_services_disabled': 'Службы геолокации отключены.',
      'location_permissions_denied': 'Доступ к геолокации запрещен.',
      'location_permissions_permanently_denied':
          'Доступ к геолокации навсегда запрещен.',
      'generic_error_prefix': 'Ошибка',
      'articles': [
        {
          'title': 'Как увеличить доход',
          'subtitle': 'Стратегии для специалистов',
          'icon': Icons.trending_up,
          'color': Colors.green,
          'content':
              '1. Четкое и профессиональное фото профиля.\n2. Качественные фото проектов (до/после).\n3. Быстрый ответ (менее 15 минут повышает конверсию на 40%).\n4. Просите отзывы после каждого успешно завершенного заказа.',
        },
        {
          'title': 'Как выбрать подходящего специалиста',
          'subtitle': 'Советы для клиентов',
          'icon': Icons.verified_user,
          'color': Colors.blue,
          'content':
              '1. Ищите значок "Проверенный бизнес".\n2. Читайте свежие отзывы, а не только рейтинг.\n3. Сравнивайте цены, но избегайте подозрительно дешевых предложений.\n4. Для крупных работ уточняйте наличие страховки.',
        },
        {
          'title': 'Как написать хороший пост',
          'subtitle': 'Чтобы получать точные предложения',
          'icon': Icons.edit_note,
          'color': Colors.orange,
          'content':
              'Заголовок: укажите основную задачу.\nОписание: добавьте локацию и удобные сроки.\nФото: сделайте четкие снимки места при дневном свете.',
        },
        {
          'title': 'Проверка бизнеса',
          'subtitle': 'Зачем проходить верификацию?',
          'icon': Icons.verified,
          'color': Colors.indigo,
          'content':
              'Проверенные компании получают на 300% больше видимости и синий значок, который повышает доверие клиентов. Верификация включает проверку личности и регистрации бизнеса.',
        },
      ],
    });
    return strings;
  }

  Map<String, dynamic> _englishStrings() {
    return {
      'title': 'Community & Jobs',
      'search_hint': 'Search posts...',
      'create_post': 'Post to Community',
      'edit_post': 'Edit Post',
      'post_title': 'Title',
      'post_category': 'Category',
      'post_content': 'What\'s on your mind?',
      'publish': 'Publish',
      'update': 'Update',
      'cancel': 'Cancel',
      'categories': [
        'All',
        'Question',
        'Tip',
        'Job Request',
        'Recommendation',
        'Other',
      ],
      'upload_photo': 'Add Photos',
      'no_posts': 'No posts yet',
      'delete': 'Delete',
      'share': 'Share',
      'post_actions': 'Post actions',
      'report': 'Report',
      'hide': 'Hide',
      'block_user': 'Block user',
      'block_user_confirm':
          'Block this user? Their content will be removed from your feed immediately, and moderation will be notified.',
      'report_content_title': 'Report objectionable content',
      'report_reason_hint': 'What is objectionable about this content?',
      'submit_report': 'Submit report',
      'report_submitted':
          'Report submitted. Our team will review it within 24 hours.',
      'blocked_user_hidden':
          'User blocked. Their content was removed from your feed.',
      'ugc_terms_title': 'Community Terms of Use',
      'ugc_terms_body':
          'Before accessing community content, you agree not to post abusive, hateful, sexual, violent, or illegal content. Report objectionable content using Report, and block abusive users using Block user.',
      'ugc_terms_accept': 'I Agree and Continue',
      'edit': 'Edit',
      'comments': 'Comments / Offers',
      'add_comment': 'Add a comment or offer...',
      'bid_price': 'Bid Price',
      'bid_price_hint': 'For example 350',
      'send_bid': 'Send Bid',
      'update_bid': 'Update Bid',
      'edit_your_bid': 'You can update your existing bid.',
      'choose_worker': 'Choose Worker',
      'confirm_choose_worker_title': 'Choose this worker?',
      'confirm_choose_worker_body':
          'This will mark the worker as the selected offer for this job request.',
      'selected_worker': 'Selected Worker',
      'selected_offer': 'Selected Offer',
      'offer_price': 'Offered Price',
      'workers_can_offer':
          'Workers can place bids here, and you can choose the one you want.',
      'job_request_comment_restriction':
          'Only workers with an active subscription can comment on job requests.',
      'rating': 'Rating',
      'reviews': 'Reviews',
      'author': 'Author',
      'posted': 'Posted',
      'sort': 'Sort by',
      'newest': 'Newest',
      'most_liked': 'Most Liked',
      'guest_msg': 'You must sign up to perform this action',
      'login': 'Sign In',
      'error': 'Error: Permission denied or connection issue',
      'empty_fields': 'Please fill both title and content',
      'location': 'Location (City/Area)',
      'job_request': 'Job Request',
      'profession': 'Profession',
      'profession_hint': 'Choose the profession you need',
      'profession_required': 'Please choose a profession',
      'filter_profession': 'Filter by profession',
      'filter_all_professions': 'All professions',
      'filter_my_profession': 'My profession',
      'my_profession_not_set':
          'Set your profession in profile to use this filter',
      'filter_radius': 'Filter by radius',
      'filter_any_radius': 'Any radius',
      'filter_my_radius_value': 'My radius: {val} km',
      'filter_my_radius_unavailable': 'My radius is not available',
      'radius_requires_location': 'Enable location to apply radius filter',
      'use_current_location': 'Use current location',
      'choose_from_map': 'Choose from map',
      'selected_location': 'Selected location',
      'change_location': 'Change location',
      'location_loading': 'Getting location...',
      'date_from': 'From date',
      'date_to': 'To date',
      'date_anytime':
          'If you do not choose dates, the request will be considered anytime',
      'select_date': 'Select date',
      'time_from': 'From hour',
      'time_to': 'To hour',
      'time_anytime':
          'If you do not choose hours, the request will be considered anytime',
      'add_video': 'Add Video',
      'media_limit': 'You can upload up to 5 photos/videos',
      'gallery': 'Gallery',
      'camera': 'Camera',
      'guide_title': 'How it works?',
      'guide_content':
          '• Share questions, tips, and recommendations.\n• Need a pro? Post a "Job Request".\n• Professionals? Offer your services in the comments.\n• Filter by category or sort by popularity.',
      'featured_articles': 'Guides & Articles',
      'share_article': 'Share Article',
      'anonymous': 'Anonymous',
      'user_fallback': 'User',
      'user_not_signed_in': 'User not signed in',
      'location_services_disabled': 'Location services are disabled.',
      'location_permissions_denied': 'Location permissions are denied.',
      'location_permissions_permanently_denied':
          'Location permissions are permanently denied.',
      'generic_error_prefix': 'Error',
      'articles': [
        {
          'title': 'Maximizing your earnings',
          'subtitle': 'Strategies for professionals',
          'icon': Icons.trending_up,
          'color': Colors.green,
          'content':
              '1. Clear & professional profile photo.\n2. High-quality project photos (before/after).\n3. Fast response time (under 15 mins increases conversion by 40%).\n4. Ask for reviews after every successful job.',
        },
        {
          'title': 'Choosing the right pro',
          'subtitle': 'Tips for customers',
          'icon': Icons.verified_user,
          'color': Colors.blue,
          'content':
              '1. Look for the "Verified Business" badge.\n2. Read recent reviews, not just the rating.\n3. Compare quotes but avoid "too good to be true" prices.\n4. Confirm insurance coverage for major tasks.',
        },
        {
          'title': 'Writing a great job post',
          'subtitle': 'To get accurate quotes',
          'icon': Icons.edit_note,
          'color': Colors.orange,
          'content':
              'Title: Mention the core task.\nContent: Include location and your preferred schedule.\nPhotos: Take clear photos of the area in daylight.',
        },
        {
          'title': 'Business Verification',
          'subtitle': 'Why get verified?',
          'icon': Icons.verified,
          'color': Colors.indigo,
          'content':
              'Verified businesses get 300% more visibility and a blue badge that builds trust. Verification involves ID and registration checks.',
        },
      ],
    };
  }

  bool _isGuest() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  void _showGuestDialog(BuildContext context, Map<String, dynamic> strings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(strings['guest_msg']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings['cancel']),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignInPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
            ),
            child: Text(strings['login']),
          ),
        ],
      ),
    );
  }

  void _showCreatePostSheet(
    BuildContext context, {
    Map<String, dynamic>? existingPost,
  }) {
    final strings = _getLocalizedStrings(context);
    if (_isGuest()) {
      _showGuestDialog(context, strings);
      return;
    }

    final titleController = TextEditingController(text: existingPost?['title']);
    final contentController = TextEditingController(
      text: existingPost?['content'],
    );
    final locationController = TextEditingController(
      text: existingPost?['location'],
    );
    final localeCode = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    LatLng? selectedJobLocation =
        existingPost?['locationLat'] != null &&
            existingPost?['locationLng'] != null
        ? LatLng(
            (existingPost!['locationLat'] as num).toDouble(),
            (existingPost['locationLng'] as num).toDouble(),
          )
        : null;
    String selectedCategory =
        existingPost?['category'] ?? (strings['categories'] as List)[1];
    DateTime? selectedDateFrom = _extractDate(existingPost?['requestDateFrom']);
    DateTime? selectedDateTo = _extractDate(existingPost?['requestDateTo']);
    TimeOfDay? selectedTimeFrom = _extractTime(
      existingPost?['requestTimeFrom'],
    );
    TimeOfDay? selectedTimeTo = _extractTime(existingPost?['requestTimeTo']);
    String? selectedProfession = existingPost?['profession'] != null
        ? _normalizeStoredProfession(existingPost!['profession'].toString())
        : null;
    List<File> selectedMediaFiles = [];
    List<String> existingMediaUrls = _mediaUrlsFromPost(existingPost);
    bool isUploading = false;
    bool isResolvingLocation = false;
    const maxMediaCount = 5;
    final professionOptions = _professionItems.isNotEmpty
        ? _professionItems
        : ProfessionLocalization.canonicalProfessions
              .map((profession) => <String, dynamic>{'en': profession})
              .toList();

    void showMediaLimitMessage() {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['media_limit'])));
    }

    Future<void> showSourcePicker({
      required String title,
      required Future<void> Function(ImageSource source) onSelect,
    }) async {
      await showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(strings['gallery']),
                onTap: () {
                  Navigator.pop(context);
                  onSelect(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(strings['camera']),
                onTap: () {
                  Navigator.pop(context);
                  onSelect(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      );
    }

    Future<void> updateLocationLabel(LatLng loc) async {
      try {
        final placemarks = await placemarkFromCoordinates(
          loc.latitude,
          loc.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts =
              [place.locality, place.subLocality, place.administrativeArea]
                  .where((part) => part != null && part!.trim().isNotEmpty)
                  .cast<String>()
                  .toList();
          locationController.text = parts.isNotEmpty
              ? parts.toSet().join(', ')
              : '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
        } else {
          locationController.text =
              '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
        }
      } catch (e) {
        locationController.text =
            '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
        debugPrint("Reverse geocoding error: $e");
      }
    }

    Future<void> pickCurrentLocation(StateSetter setSheetState) async {
      setSheetState(() => isResolvingLocation = true);
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw strings['location_services_disabled'];
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw strings['location_permissions_denied'];
          }
        }

        if (permission == LocationPermission.deniedForever) {
          throw strings['location_permissions_permanently_denied'];
        }

        final position = await Geolocator.getCurrentPosition();
        final loc = LatLng(position.latitude, position.longitude);
        await updateLocationLabel(loc);
        if (context.mounted) {
          setSheetState(() {
            selectedJobLocation = loc;
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      } finally {
        if (context.mounted) {
          setSheetState(() => isResolvingLocation = false);
        }
      }
    }

    Future<void> pickLocationFromMap(StateSetter setSheetState) async {
      final picked = await Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
          builder: (_) => LocationPicker(initialCenter: selectedJobLocation),
        ),
      );

      if (picked == null || !context.mounted) return;

      setSheetState(() => isResolvingLocation = true);
      await updateLocationLabel(picked);
      if (context.mounted) {
        setSheetState(() {
          selectedJobLocation = picked;
          isResolvingLocation = false;
        });
      }
    }

    Future<void> pickDate({
      required bool isFrom,
      required StateSetter setSheetState,
    }) async {
      final initialDate =
          (isFrom ? selectedDateFrom : selectedDateTo) ?? DateTime.now();
      final firstDate = isFrom
          ? DateTime.now().subtract(const Duration(days: 1))
          : (selectedDateFrom ?? DateTime.now());
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
        firstDate: firstDate,
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      );

      if (picked == null) return;

      setSheetState(() {
        if (isFrom) {
          selectedDateFrom = picked;
          if (selectedDateTo != null && selectedDateTo!.isBefore(picked)) {
            selectedDateTo = picked;
          }
        } else {
          selectedDateTo = picked;
        }
      });
    }

    Future<void> pickTime({
      required bool isFrom,
      required StateSetter setSheetState,
    }) async {
      final picked = await showTimePicker(
        context: context,
        initialTime:
            (isFrom ? selectedTimeFrom : selectedTimeTo) ?? TimeOfDay.now(),
      );

      if (picked == null) return;

      setSheetState(() {
        if (isFrom) {
          selectedTimeFrom = picked;
        } else {
          selectedTimeTo = picked;
        }
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existingPost == null
                          ? strings['create_post']
                          : strings['edit_post'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: InputDecoration(
                    labelText: strings['post_category'],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  items: (strings['categories'] as List)
                      .skip(1)
                      .map(
                        (cat) => DropdownMenuItem(
                          value: cat.toString(),
                          child: Text(cat.toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setSheetState(() => selectedCategory = val!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: strings['post_title'],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isJobRequestCategoryValue(selectedCategory) ||
                    selectedCategory == strings['job_request']) ...[
                  DropdownButtonFormField<String>(
                    value: selectedProfession,
                    decoration: InputDecoration(
                      labelText: strings['profession'],
                      hintText: strings['profession_hint'],
                      prefixIcon: const Icon(Icons.work_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: professionOptions
                        .map(
                          (profession) => DropdownMenuItem(
                            value: _professionCanonicalValue(profession),
                            child: Text(
                              _professionLabel(profession, localeCode),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => selectedProfession = value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(
                            isFrom: true,
                            setSheetState: setSheetState,
                          ),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            selectedDateFrom == null
                                ? strings['date_from']
                                : '${selectedDateFrom!.day.toString().padLeft(2, '0')}/${selectedDateFrom!.month.toString().padLeft(2, '0')}/${selectedDateFrom!.year}',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(
                            isFrom: false,
                            setSheetState: setSheetState,
                          ),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            selectedDateTo == null
                                ? strings['date_to']
                                : '${selectedDateTo!.day.toString().padLeft(2, '0')}/${selectedDateTo!.month.toString().padLeft(2, '0')}/${selectedDateTo!.year}',
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings['date_anytime'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickTime(
                            isFrom: true,
                            setSheetState: setSheetState,
                          ),
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            selectedTimeFrom == null
                                ? strings['time_from']
                                : selectedTimeFrom!.format(context),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickTime(
                            isFrom: false,
                            setSheetState: setSheetState,
                          ),
                          icon: const Icon(Icons.access_time_outlined),
                          label: Text(
                            selectedTimeTo == null
                                ? strings['time_to']
                                : selectedTimeTo!.format(context),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings['time_anytime'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFF8FAFC),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: Color(0xFF1976D2),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                strings['location'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (isResolvingLocation)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          locationController.text.isNotEmpty
                              ? locationController.text
                              : strings['selected_location'],
                          style: TextStyle(
                            color: locationController.text.isNotEmpty
                                ? const Color(0xFF334155)
                                : const Color(0xFF94A3B8),
                            height: 1.4,
                          ),
                        ),
                        if (selectedJobLocation != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${selectedJobLocation!.latitude.toStringAsFixed(5)}, ${selectedJobLocation!.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isResolvingLocation
                                    ? null
                                    : () => pickCurrentLocation(setSheetState),
                                icon: const Icon(Icons.my_location_rounded),
                                label: Text(strings['use_current_location']),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isResolvingLocation
                                    ? null
                                    : () => pickLocationFromMap(setSheetState),
                                icon: const Icon(Icons.map_outlined),
                                label: Text(strings['choose_from_map']),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (selectedMediaFiles.isNotEmpty ||
                    existingMediaUrls.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          selectedMediaFiles.length + existingMediaUrls.length,
                      itemBuilder: (context, index) {
                        final isExisting = index < existingMediaUrls.length;
                        final mediaPath = isExisting
                            ? existingMediaUrls[index]
                            : selectedMediaFiles[index -
                                      existingMediaUrls.length]
                                  .path;
                        final isVideo = _isVideoPath(mediaPath);
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.black,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: isVideo
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (isExisting)
                                          CachedVideoPlayer(
                                            url: mediaPath,
                                            play: false,
                                            showControls: false,
                                            allowFullscreen: false,
                                          )
                                        else
                                          Container(
                                            color: Colors.black87,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.videocam_rounded,
                                              color: Colors.white70,
                                              size: 34,
                                            ),
                                          ),
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: Colors.white,
                                            size: 28,
                                          ),
                                        ),
                                      ],
                                    )
                                  : isExisting
                                  ? CachedNetworkImage(
                                      imageUrl: mediaPath,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      selectedMediaFiles[index -
                                          existingMediaUrls.length],
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: GestureDetector(
                                onTap: () => setSheetState(() {
                                  if (isExisting) {
                                    existingMediaUrls.removeAt(index);
                                  } else {
                                    selectedMediaFiles.removeAt(
                                      index - existingMediaUrls.length,
                                    );
                                  }
                                }),
                                child: const CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  radius: 12,
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await showSourcePicker(
                            title: strings['upload_photo'],
                            onSelect: (source) async {
                              final currentCount =
                                  selectedMediaFiles.length +
                                  existingMediaUrls.length;
                              if (currentCount >= maxMediaCount) {
                                showMediaLimitMessage();
                                return;
                              }

                              final picker = ImagePicker();
                              if (source == ImageSource.camera) {
                                final hasCameraPermission =
                                    await AppPermissionService.ensureGranted(
                                      context,
                                      permission: Permission.camera,
                                      kind: AppPermissionKind.camera,
                                    );
                                if (!hasCameraPermission) return;

                                final picked = await picker.pickImage(
                                  source: source,
                                  imageQuality: 70,
                                );
                                if (picked == null) return;
                                setSheetState(
                                  () =>
                                      selectedMediaFiles.add(File(picked.path)),
                                );
                                return;
                              }

                              final pickedFiles = await picker.pickMultiImage(
                                imageQuality: 70,
                              );
                              if (pickedFiles.isEmpty) return;

                              final remaining = maxMediaCount - currentCount;
                              final files = pickedFiles
                                  .take(remaining)
                                  .map((x) => File(x.path))
                                  .toList();
                              if (pickedFiles.length > remaining) {
                                showMediaLimitMessage();
                              }
                              setSheetState(
                                () => selectedMediaFiles.addAll(files),
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(strings['upload_photo']),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await showSourcePicker(
                            title: strings['add_video'],
                            onSelect: (source) async {
                              final currentCount =
                                  selectedMediaFiles.length +
                                  existingMediaUrls.length;
                              if (currentCount >= maxMediaCount) {
                                showMediaLimitMessage();
                                return;
                              }

                              final picker = ImagePicker();
                              if (source == ImageSource.camera) {
                                final hasCameraPermission =
                                    await AppPermissionService.ensureGranted(
                                      context,
                                      permission: Permission.camera,
                                      kind: AppPermissionKind.camera,
                                    );
                                if (!hasCameraPermission) return;
                              }

                              final pickedVideo = await picker.pickVideo(
                                source: source,
                              );
                              if (pickedVideo == null) return;

                              setSheetState(
                                () => selectedMediaFiles.add(
                                  File(pickedVideo.path),
                                ),
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(strings['add_video']),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${selectedMediaFiles.length + existingMediaUrls.length}/$maxMediaCount',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isUploading
                      ? null
                      : () async {
                          if (titleController.text.trim().isEmpty ||
                              contentController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(strings['empty_fields'])),
                            );
                            return;
                          }

                          if ((_isJobRequestCategoryValue(selectedCategory) ||
                                  selectedCategory == strings['job_request']) &&
                              (selectedProfession == null ||
                                  selectedProfession!.trim().isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(strings['profession_required']),
                              ),
                            );
                            return;
                          }

                          setSheetState(() => isUploading = true);
                          try {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null)
                              throw Exception(strings['user_not_signed_in']);

                            String authorName =
                                user.displayName ?? strings['user_fallback'];
                            if (user.displayName == null ||
                                user.displayName!.isEmpty) {
                              try {
                                final userDoc = await _firestore
                                    .collection('users')
                                    .doc(user.uid)
                                    .get();
                                if (userDoc.exists) {
                                  authorName =
                                      userDoc.data()?['name'] ??
                                      strings['user_fallback'];
                                }
                              } catch (_) {}
                            }

                            List<String> mediaUrls = List.from(
                              existingMediaUrls,
                            );
                            for (
                              var i = 0;
                              i < selectedMediaFiles.length;
                              i++
                            ) {
                              final file = selectedMediaFiles[i];
                              final isVideo = _isVideoPath(file.path);
                              final storageRef = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                    'blog_media/${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i${isVideo ? '.mp4' : '.jpg'}',
                                  );
                              await storageRef.putFile(
                                file,
                                SettableMetadata(
                                  contentType: isVideo
                                      ? 'video/mp4'
                                      : 'image/jpeg',
                                ),
                              );
                              String url = await storageRef.getDownloadURL();
                              mediaUrls.add(url);
                            }

                            final postData = {
                              'title': titleController.text.trim(),
                              'content': contentController.text.trim(),
                              'category': selectedCategory,
                              'location': locationController.text.trim(),
                              'locationLat': selectedJobLocation?.latitude,
                              'locationLng': selectedJobLocation?.longitude,
                              'profession': selectedProfession,
                              'professionLabel': selectedProfession == null
                                  ? null
                                  : ProfessionLocalization.toLocalized(
                                      selectedProfession!,
                                      localeCode,
                                    ),
                              'requestDateFrom': selectedDateFrom == null
                                  ? null
                                  : Timestamp.fromDate(selectedDateFrom!),
                              'requestDateTo': selectedDateTo == null
                                  ? null
                                  : Timestamp.fromDate(selectedDateTo!),
                              'requestTimeFrom': selectedTimeFrom == null
                                  ? null
                                  : _formatTimeOfDay(selectedTimeFrom!),
                              'requestTimeTo': selectedTimeTo == null
                                  ? null
                                  : _formatTimeOfDay(selectedTimeTo!),
                              'imageUrls': mediaUrls,
                              'imageUrl': mediaUrls.isNotEmpty
                                  ? mediaUrls[0]
                                  : null,
                              'mediaTypes': mediaUrls
                                  .map(
                                    (url) =>
                                        _isVideoPath(url) ? 'video' : 'image',
                                  )
                                  .toList(),
                              'authorUid': user.uid,
                              'authorName': authorName,
                              'timestamp':
                                  existingPost?['timestamp'] ??
                                  FieldValue.serverTimestamp(),
                              'likes': existingPost?['likes'] ?? 0,
                              'likedBy': existingPost?['likedBy'] ?? {},
                              'isJobRequest':
                                  _isJobRequestCategoryValue(
                                    selectedCategory,
                                  ) ||
                                  selectedCategory == strings['job_request'],
                              'isPinned': existingPost?['isPinned'] ?? false,
                            };

                            if (existingPost == null) {
                              await _firestore
                                  .collection('blog_posts')
                                  .add(postData);
                            } else {
                              await _firestore
                                  .collection('blog_posts')
                                  .doc(existingPost['id'])
                                  .update(postData);
                            }
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${strings['generic_error_prefix']}: $e',
                                  ),
                                ),
                              );
                          } finally {
                            if (mounted)
                              setSheetState(() => isUploading = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          existingPost == null
                              ? strings['publish']
                              : strings['update'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deletePost(String postId) async {
    try {
      await _firestore.collection('blog_posts').doc(postId).delete();
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
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
    final likedByData = post['likedBy'];
    Map<String, dynamic> likedBy = {};

    if (likedByData is Map) {
      likedBy = Map<String, dynamic>.from(likedByData);
    } else if (likedByData is List) {
      for (var uid in likedByData) {
        if (uid is String) likedBy[uid] = true;
      }
    }

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
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF5FF), Color(0xFFF8FCFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _isGuideExpanded = !_isGuideExpanded),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFDCEEFF),
              child: Icon(Icons.lightbulb_outline, color: _uiPrimaryBlue),
            ),
            title: Text(
              strings['guide_title'],
              style: const TextStyle(
                color: _uiTitle,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            trailing: Icon(
              _isGuideExpanded ? Icons.expand_less : Icons.expand_more,
              color: _uiMuted,
            ),
          ),
          if (_isGuideExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                strings['guide_content'],
                style: const TextStyle(
                  color: _uiBody,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Map<String, dynamic> strings) {
    final categories = strings['categories'] as List;
    final likedLabel = strings['filter_liked_posts'] ?? 'Liked posts';
    final myPostsLabel = strings['filter_my_posts'] ?? 'My posts';
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ...List.generate(categories.length, (index) {
            final isSelected = _selectedFilterIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    _selectedFilterIndex = index;
                    _isLoading = true;
                    _posts = [];
                    _postLimit = 10;
                  });
                  _listenToPosts();
                },
                label: Text(categories[index]),
                selectedColor: _uiPrimaryBlue.withValues(alpha: 0.1),
                backgroundColor: Colors.white,
                checkmarkColor: _uiPrimaryBlue,
                labelStyle: TextStyle(
                  color: isSelected ? _uiPrimaryBlue : _uiMuted,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? _uiPrimaryBlue : _uiBorder,
                  ),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: _showOnlyLikedPosts,
              onSelected: (val) {
                setState(() {
                  _showOnlyLikedPosts = val;
                  if (val) _showOnlyMyPosts = false;
                });
              },
              label: Text(likedLabel),
              selectedColor: _uiPrimaryBlue.withValues(alpha: 0.1),
              backgroundColor: Colors.white,
              checkmarkColor: _uiPrimaryBlue,
              labelStyle: TextStyle(
                color: _showOnlyLikedPosts ? _uiPrimaryBlue : _uiMuted,
                fontWeight: _showOnlyLikedPosts
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _showOnlyLikedPosts ? _uiPrimaryBlue : _uiBorder,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: _showOnlyMyPosts,
              onSelected: (val) {
                setState(() {
                  _showOnlyMyPosts = val;
                  if (val) _showOnlyLikedPosts = false;
                });
              },
              label: Text(myPostsLabel),
              selectedColor: _uiPrimaryBlue.withValues(alpha: 0.1),
              backgroundColor: Colors.white,
              checkmarkColor: _uiPrimaryBlue,
              labelStyle: TextStyle(
                color: _showOnlyMyPosts ? _uiPrimaryBlue : _uiMuted,
                fontWeight: _showOnlyMyPosts
                    ? FontWeight.bold
                    : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _showOnlyMyPosts ? _uiPrimaryBlue : _uiBorder,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isLikedByCurrentUser(Map<String, dynamic> post) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final likedByData = post['likedBy'];
    if (likedByData is Map) {
      return likedByData.containsKey(user.uid);
    }
    if (likedByData is List) {
      return likedByData.contains(user.uid);
    }
    return false;
  }

  bool _matchesOwnerFilters(Map<String, dynamic> post) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return !_showOnlyLikedPosts && !_showOnlyMyPosts;
    }

    if (_showOnlyLikedPosts) {
      return _isLikedByCurrentUser(post);
    }
    if (_showOnlyMyPosts) {
      return (post['authorUid'] ?? '').toString() == user.uid;
    }
    return true;
  }

  bool _matchesSearchQuery(Map<String, dynamic> post) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;

    final searchable = <String>[
      (post['title'] ?? '').toString(),
      (post['content'] ?? '').toString(),
      (post['authorName'] ?? '').toString(),
      (post['category'] ?? '').toString(),
      (post['location'] ?? '').toString(),
      (post['professionLabel'] ?? '').toString(),
      (post['profession'] ?? '').toString(),
    ].join(' ').toLowerCase();

    return searchable.contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final isJobRequestSectionActive = _isJobRequestSectionActive(strings);
    final visiblePosts = _posts
        .where((p) => !_hiddenPostIds.contains(p['id']))
        .where(
          (p) => !_blockedUserIds.contains((p['authorUid'] ?? '').toString()),
        )
        .where((p) => _matchesJobRequestFilters(p, strings))
        .where(_matchesOwnerFilters)
        .where(_matchesSearchQuery)
        .toList();

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _uiSurfaceBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            strings['title'],
            style: const TextStyle(
              color: _uiTitle,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: _uiPrimaryBlue),
              onPressed: _onRefresh,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: _uiPrimaryBlue),
              onSelected: (value) {
                setState(() {
                  _sortBy = value;
                  _sortPosts();
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'newest',
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 20),
                      const SizedBox(width: 10),
                      Text(strings['newest']),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'likes',
                  child: Row(
                    children: [
                      const Icon(Icons.favorite_outline, size: 20),
                      const SizedBox(width: 10),
                      Text(strings['most_liked']),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              isJobRequestSectionActive ? 186 : 110,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: strings['search_hint'],
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      fillColor: const Color(0xFFF9FAFB),
                      filled: true,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: _uiBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: _uiBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: _uiPrimaryBlue,
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
                _buildFilterBar(strings),
                if (isJobRequestSectionActive)
                  _buildJobRequestFilters(strings, locale),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'formu_fab',
          onPressed: () => _showCreatePostSheet(context),
          backgroundColor: _uiPrimaryBlue,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            strings['publish'],
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _isCheckingUgcTerms
              ? const Center(child: CircularProgressIndicator())
              : !_hasAcceptedUgcTerms
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings['ugc_terms_title'] ??
                                'Community Terms of Use',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            strings['ugc_terms_body'] ?? '',
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _acceptUgcTerms,
                              child: Text(
                                strings['ugc_terms_accept'] ??
                                    'I Agree and Continue',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount:
                      visiblePosts.length +
                      1 +
                      (visiblePosts.isEmpty ? 1 : 0) +
                      (_isMoreLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildExplanationCard(strings);

                    if (visiblePosts.isEmpty && index == 1) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text(
                            strings['no_posts'],
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }

                    final postIndex = index - 1;
                    if (postIndex < visiblePosts.length) {
                      return _BlogCard(
                        post: visiblePosts[postIndex],
                        distanceLabel: _distanceLabelForPost(
                          visiblePosts[postIndex],
                        ),
                        onLike: () => _toggleLike(visiblePosts[postIndex]),
                        onDelete: () =>
                            _deletePost(visiblePosts[postIndex]['id']),
                        onEdit: () => _showCreatePostSheet(
                          context,
                          existingPost: visiblePosts[postIndex],
                        ),
                        onHide: () => setState(
                          () =>
                              _hiddenPostIds.add(visiblePosts[postIndex]['id']),
                        ),
                        onReport: () => _reportPost(visiblePosts[postIndex]),
                        onBlockUser: () =>
                            _blockUserFromPost(visiblePosts[postIndex]),
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
                    }
                    return _isMoreLoading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : const SizedBox.shrink();
                  },
                ),
        ),
      ),
    );
  }
}

class _BlogCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String? distanceLabel;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onHide;
  final VoidCallback onReport;
  final VoidCallback onBlockUser;
  final Function(String) onCategoryTap;
  final Map<String, dynamic> localizedStrings;
  final VoidCallback onGuestDialog;

  const _BlogCard({
    required this.post,
    required this.distanceLabel,
    required this.onLike,
    required this.onDelete,
    required this.onEdit,
    required this.onHide,
    required this.onReport,
    required this.onBlockUser,
    required this.onCategoryTap,
    required this.localizedStrings,
    required this.onGuestDialog,
  });

  Future<void> _showPostActionsSheet(
    BuildContext context, {
    required bool isAuthor,
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
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                            localizedStrings['post_actions'] ?? 'Post actions',
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
                      children: isAuthor
                          ? [
                              actionTile(
                                icon: Icons.edit_outlined,
                                title: localizedStrings['edit'],
                                onTap: onEdit,
                              ),
                              actionTile(
                                icon: Icons.delete_outline_rounded,
                                title: localizedStrings['delete'],
                                onTap: onDelete,
                                isDestructive: true,
                              ),
                            ]
                          : [
                              actionTile(
                                icon: Icons.visibility_off_outlined,
                                title: localizedStrings['hide'],
                                onTap: onHide,
                              ),
                              actionTile(
                                icon: Icons.flag_outlined,
                                title: localizedStrings['report'] ?? 'Report',
                                onTap: onReport,
                                isDestructive: true,
                              ),
                              actionTile(
                                icon: Icons.block_outlined,
                                title:
                                    localizedStrings['block_user'] ??
                                    'Block user',
                                onTap: onBlockUser,
                                isDestructive: true,
                              ),
                              actionTile(
                                icon: Icons.share_outlined,
                                title: localizedStrings['share'],
                                onTap: () => Share.share(
                                  '${post['title']}\n${post['content']}',
                                ),
                              ),
                            ],
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
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user != null && post['authorUid'] == user.uid;
    final likedByData = post['likedBy'];
    bool isLiked = false;
    if (user != null && likedByData != null) {
      if (likedByData is Map)
        isLiked = likedByData.containsKey(user.uid);
      else if (likedByData is List)
        isLiked = likedByData.contains(user.uid);
    }

    final isJobRequest =
        post['isJobRequest'] == true ||
        _isJobRequestCategoryValue((post['category'] ?? '').toString());
    final isPinned = post['isPinned'] == true;
    final mediaUrls = _mediaUrlsFromPost(post);
    final firstMedia = mediaUrls.isNotEmpty ? mediaUrls.first : null;
    final firstMediaIsVideo =
        firstMedia != null && _isMediaVideoPath(firstMedia);
    final requestDateFrom = _blogCardDate(post['requestDateFrom']);
    final requestDateTo = _blogCardDate(post['requestDateTo']);
    final postedAt = _blogCardDate(post['timestamp']);
    final cityLabel = _blogCardCityLabel(post['location']);
    final dateLabel = requestDateFrom != null || requestDateTo != null
        ? requestDateFrom != null && requestDateTo != null
              ? "${intl.DateFormat('dd/MM').format(requestDateFrom)} - ${intl.DateFormat('dd/MM').format(requestDateTo)}"
              : intl.DateFormat(
                  'dd/MM',
                ).format(requestDateFrom ?? requestDateTo!)
        : postedAt != null
        ? intl.DateFormat('dd/MM/yyyy').format(postedAt)
        : null;
    final categoryLabel = _localizedCategoryValueForMap(
      (post['category'] ?? '').toString(),
      localizedStrings,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isPinned
            ? Border.all(color: const Color(0xFFBFDBFE), width: 1.6)
            : (isJobRequest
                  ? Border.all(color: const Color(0xFFBFDBFE), width: 1.3)
                  : null),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailPage(
              post: post,
              onLike: onLike,
              onEdit: onEdit,
              onDelete: onDelete,
              onReport: onReport,
              onBlockUser: onBlockUser,
              localizedStrings: localizedStrings,
              onGuestDialog: onGuestDialog,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (firstMedia != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: firstMediaIsVideo
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedVideoPlayer(
                              url: firstMedia,
                              play: false,
                              showControls: false,
                              allowFullscreen: false,
                            ),
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 52,
                              ),
                            ),
                          ],
                        )
                      : CachedNetworkImage(
                          imageUrl: firstMedia,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[200]),
                        ),
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
                        const Icon(
                          Icons.push_pin,
                          size: 16,
                          color: _uiPrimaryBlue,
                        ),
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
                          categoryLabel,
                          style: const TextStyle(
                            color: _uiPrimaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () =>
                            _showPostActionsSheet(context, isAuthor: isAuthor),
                        child: Ink(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: Color(0xFF64748B),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _uiTitle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post['content'] ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _uiMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (dateLabel != null) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.event_rounded,
                                size: 14,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dateLabel,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                (post['authorName'] ??
                                        localizedStrings['anonymous'])
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (distanceLabel != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.near_me_rounded,
                                        size: 14,
                                        color: Color(0xFF1976D2),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          cityLabel == null
                                              ? distanceLabel!
                                              : '${distanceLabel!} · $cityLabel',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF1976D2),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onLike,
                        child: Row(
                          children: [
                            Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 18,
                              color: const Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (post['likes'] ?? 0).toString(),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
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

bool _isMediaVideoPath(String path) {
  final lower = path.toLowerCase();
  return lower.contains('.mp4') ||
      lower.contains('.mov') ||
      lower.contains('.avi') ||
      lower.contains('.mkv') ||
      lower.contains('.webm');
}

DateTime? _blogCardDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _blogCardCityLabel(dynamic rawLocation) {
  final location = rawLocation?.toString().trim() ?? '';
  if (location.isEmpty) return null;

  final coordinatesPattern = RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$');
  if (coordinatesPattern.hasMatch(location)) return null;

  final city = location.split(',').first.trim();
  if (city.isEmpty) return null;
  return city;
}

bool _isJobRequestCategoryValue(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  final aliases = _categoryAliases[3].toSet();
  return aliases.contains(normalized);
}

const List<List<String>> _categoryAliases = <List<String>>[
  ['all', 'הכל', 'الكل', 'ሁሉም', 'все'],
  ['question', 'Question', 'שאלה', 'سؤال', 'ጥያቄ', 'вопрос'],
  ['tip', 'Tip', 'טיפ', 'نصيحة', 'ምክር', 'совет'],
  [
    'job request',
    'Job Request',
    'דרוש בעל מקצוע',
    'طلب عامل',
    'የስራ ጥያቄ',
    'запрос на работу',
  ],
  ['recommendation', 'Recommendation', 'המלצה', 'توصية', 'ምክር ሰጪ', 'рекомендация'],
  ['other', 'Other', 'אחר', 'أخرى', 'ሌላ', 'другое'],
];

String _localizedCategoryValueForMap(
  String raw,
  Map<String, dynamic> localizedStrings,
) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return raw;

  int categoryIndex = -1;
  for (var i = 0; i < _categoryAliases.length; i++) {
    if (_categoryAliases[i].contains(normalized)) {
      categoryIndex = i;
      break;
    }
  }

  if (categoryIndex == -1) return raw;

  final categories = localizedStrings['categories'];
  if (categories is List && categoryIndex < categories.length) {
    return categories[categoryIndex].toString();
  }
  return raw;
}

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
