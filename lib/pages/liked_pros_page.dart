import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/services/language_provider.dart';

class LikedProsPage extends StatefulWidget {
  const LikedProsPage({super.key});

  @override
  State<LikedProsPage> createState() => _LikedProsPageState();
}

class _LikedProsPageState extends State<LikedProsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _pendingFavoriteIds = <String>{};

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Map<String, String> _strings(String localeCode) {
    switch (localeCode) {
      case 'he':
        return {
          'title': 'בעלי מקצוע שאהבתי',
          'subtitle': 'כל בעלי המקצוע ששמרת, ומי שסימנו אותך כמועדף.',
          'tab_favorites': 'אני אהבתי',
          'tab_liked_me': 'אהבו אותי',
          'empty_favorites': 'עדיין לא שמרת בעלי מקצוע למועדפים.',
          'empty_liked_me': 'עדיין אין בעלי מקצוע שסימנו אותך כמועדף.',
          'open_profile': 'לפרופיל',
          'no_name': 'בעל מקצוע',
          'saved_count': 'שמרת',
          'incoming_count': 'אהבו אותך',
          'member_since': 'נשמר בתאריך',
          'guest': 'יש להתחבר כדי לצפות ברשימת המועדפים.',
          'retry_error': 'אירעה שגיאה בטעינת הנתונים.',
          'search_hint': 'חיפוש לפי שם או מקצוע',
          'no_results': 'לא נמצאו תוצאות לחיפוש שלך.',
          'remove': 'הסר',
          'removed': 'הוסר מהמועדפים',
          'like_back': 'אהבתי גם',
          'liked': 'נשמר',
          'saved_now': 'נשמר במועדפים',
          'browse': 'חיפוש בעלי מקצוע',
          'empty_title_favorites': 'עדיין אין לך רשימת מועדפים',
          'empty_title_liked': 'עדיין לא אהבו אותך',
        };
      case 'ar':
        return {
          'title': 'المهنيون المفضلون',
          'subtitle': 'كل المهنيين الذين حفظتهم، ومن أضافوك إلى المفضلة.',
          'tab_favorites': 'أنا أحببت',
          'tab_liked_me': 'أعجبوا بي',
          'empty_favorites': 'لم تقم بحفظ أي مهني في المفضلة بعد.',
          'empty_liked_me': 'لا يوجد مهنيون أضافوك إلى المفضلة بعد.',
          'open_profile': 'فتح الملف',
          'no_name': 'مهني',
          'saved_count': 'حفظتهم',
          'incoming_count': 'أعجبوا بك',
          'member_since': 'تمت الإضافة في',
          'guest': 'يرجى تسجيل الدخول لعرض قائمة المفضلة.',
          'retry_error': 'حدث خطأ أثناء تحميل البيانات.',
          'search_hint': 'ابحث بالاسم أو المهنة',
          'no_results': 'لا توجد نتائج مطابقة لبحثك.',
          'remove': 'إزالة',
          'removed': 'تمت الإزالة من المفضلة',
          'like_back': 'أعجبني أيضًا',
          'liked': 'محفوظ',
          'saved_now': 'تمت الإضافة إلى المفضلة',
          'browse': 'ابحث عن مهنيين',
          'empty_title_favorites': 'لا توجد مفضلة بعد',
          'empty_title_liked': 'لم يضفك أحد بعد',
        };
      default:
        return {
          'title': 'Liked Pros',
          'subtitle':
              'Keep track of the pros you saved and the ones who liked you back.',
          'tab_favorites': 'Pros I Like',
          'tab_liked_me': 'Pros Who Like Me',
          'empty_favorites': 'You have not added any pros to favorites yet.',
          'empty_liked_me': 'No pros have favorited you yet.',
          'open_profile': 'Open Profile',
          'no_name': 'Pro',
          'saved_count': 'Saved',
          'incoming_count': 'Liked You',
          'member_since': 'Saved on',
          'guest': 'Please sign in to view your liked pros.',
          'retry_error': 'Something went wrong while loading this page.',
          'search_hint': 'Search by name or profession',
          'no_results': 'No matches found for your search.',
          'remove': 'Remove',
          'removed': 'Removed from favorites',
          'like_back': 'Like Back',
          'liked': 'Saved',
          'saved_now': 'Added to favorites',
          'browse': 'Browse Pros',
          'empty_title_favorites': 'No favorites yet',
          'empty_title_liked': 'No likes yet',
        };
    }
  }

  Future<void> _setFavorite({
    required String targetUid,
    required Map<String, dynamic> previewData,
    required bool shouldFavorite,
    required Map<String, String> strings,
  }) async {
    final currentUser = _currentUser;
    if (currentUser == null || targetUid.isEmpty) return;
    if (_pendingFavoriteIds.contains(targetUid)) return;

    setState(() {
      _pendingFavoriteIds.add(targetUid);
    });

    final favRef = _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('favorites')
        .doc(targetUid);
    final likedByRef = _firestore
        .collection('users')
        .doc(targetUid)
        .collection('likedBy')
        .doc(currentUser.uid);

    try {
      if (shouldFavorite) {
        final professions =
            (previewData['professions'] as List?)
                ?.map((entry) => entry.toString())
                .where((entry) => entry.trim().isNotEmpty)
                .toList() ??
            <String>[];

        await Future.wait([
          favRef.set({
            'addedAt': FieldValue.serverTimestamp(),
            'name': (previewData['name'] ?? '').toString(),
            'profileImageUrl': (previewData['profileImageUrl'] ?? '')
                .toString(),
            'professions': professions,
          }),
          likedByRef.set({
            'addedAt': FieldValue.serverTimestamp(),
            'sourceUserId': currentUser.uid,
          }),
        ]);
      } else {
        await Future.wait([favRef.delete(), likedByRef.delete()]);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              shouldFavorite ? strings['saved_now']! : strings['removed']!,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(strings['retry_error']!),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _pendingFavoriteIds.remove(targetUid);
        });
      }
    }
  }

  Future<Map<String, dynamic>> _loadUserPreview(
    String targetUid,
    Map<String, dynamic> storedData,
  ) async {
    try {
      final doc = await _firestore.collection('users').doc(targetUid).get();
      if (!doc.exists) {
        return storedData;
      }

      final liveData = doc.data() ?? <String, dynamic>{};
      return {
        ...storedData,
        ...liveData,
        'uid': targetUid,
        'name': (liveData['name'] ?? storedData['name'] ?? '').toString(),
        'profileImageUrl':
            (liveData['profileImageUrl'] ?? storedData['profileImageUrl'] ?? '')
                .toString(),
        'professions':
            (liveData['professions'] ??
                    storedData['professions'] ??
                    const <dynamic>[])
                as List,
      };
    } catch (_) {
      return {...storedData, 'uid': targetUid};
    }
  }

  String _formatTimestamp(dynamic value) {
    DateTime? dateTime;
    if (value is Timestamp) {
      dateTime = value.toDate();
    } else if (value is DateTime) {
      dateTime = value;
    }

    if (dateTime == null) return '';

    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    return '$day/$month/$year';
  }

  Future<List<_LikedProEntry>> _resolveEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String Function(QueryDocumentSnapshot<Map<String, dynamic>>) uidResolver,
  ) async {
    final futures = docs.map((doc) async {
      final targetUid = uidResolver(doc);
      final storedData = doc.data();
      final preview = targetUid.isEmpty
          ? <String, dynamic>{...storedData}
          : await _loadUserPreview(targetUid, storedData);
      return _LikedProEntry(
        targetUid: targetUid,
        storedData: storedData,
        previewData: preview,
      );
    });

    return Future.wait(futures);
  }

  List<_LikedProEntry> _filterEntries(List<_LikedProEntry> entries) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return entries;

    return entries.where((entry) {
      final data = entry.previewData;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final professions =
          (data['professions'] as List?)
              ?.map((profession) => profession.toString().toLowerCase())
              .toList() ??
          const <String>[];
      return name.contains(query) ||
          professions.any((profession) => profession.contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';
    final strings = _strings(localeCode);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8FC),
        body: _currentUser == null || _currentUser!.isAnonymous
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    strings['guest']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1976D2), Color(0xFF0F4C81)],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings['title']!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      strings['subtitle']!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _CountCard(
                                  label: strings['saved_count']!,
                                  icon: Icons.favorite_rounded,
                                  stream: _firestore
                                      .collection('users')
                                      .doc(_currentUser!.uid)
                                      .collection('favorites')
                                      .snapshots(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CountCard(
                                  label: strings['incoming_count']!,
                                  icon: Icons.favorite_border_rounded,
                                  stream: _firestore
                                      .collection('users')
                                      .doc(_currentUser!.uid)
                                      .collection('likedBy')
                                      .snapshots(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            height: 52,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              labelColor: const Color(0xFF0F4C81),
                              unselectedLabelColor: Colors.white,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              tabs: [
                                Tab(text: strings['tab_favorites']),
                                Tab(text: strings['tab_liked_me']),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value;
                                });
                              },
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: Colors.white70,
                                ),
                                suffixIcon: _searchQuery.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                        ),
                                      ),
                                hintText: strings['search_hint']!,
                                hintStyle: const TextStyle(
                                  color: Colors.white70,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProsList(
                          collectionName: 'favorites',
                          emptyText: strings['empty_favorites']!,
                          fallbackName: strings['no_name']!,
                          strings: strings,
                          uidResolver: (doc) => doc.id,
                        ),
                        _buildProsList(
                          collectionName: 'likedBy',
                          emptyText: strings['empty_liked_me']!,
                          fallbackName: strings['no_name']!,
                          strings: strings,
                          uidResolver: (doc) {
                            final data = doc.data();
                            return (data['sourceUserId'] ?? doc.id).toString();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProsList({
    required String collectionName,
    required String emptyText,
    required String fallbackName,
    required Map<String, String> strings,
    required String Function(QueryDocumentSnapshot<Map<String, dynamic>>)
    uidResolver,
  }) {
    final uid = _currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collectionName)
          .orderBy('addedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LikedProsLoadingList();
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(strings['retry_error']!, textAlign: TextAlign.center),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];

        return FutureBuilder<List<_LikedProEntry>>(
          future: _resolveEntries(docs, uidResolver),
          builder: (context, resolvedSnapshot) {
            if (resolvedSnapshot.connectionState == ConnectionState.waiting) {
              return const _LikedProsLoadingList();
            }

            final entries = _filterEntries(resolvedSnapshot.data ?? const []);
            if (entries.isEmpty) {
              return _LikedProsEmptyState(
                title: _searchQuery.isEmpty
                    ? collectionName == 'favorites'
                          ? strings['empty_title_favorites']!
                          : strings['empty_title_liked']!
                    : strings['no_results']!,
                message: _searchQuery.isEmpty
                    ? emptyText
                    : strings['no_results']!,
                actionLabel:
                    collectionName == 'favorites' && _searchQuery.isEmpty
                    ? strings['browse']!
                    : null,
                onAction: collectionName == 'favorites' && _searchQuery.isEmpty
                    ? () => Navigator.pop(context)
                    : null,
              );
            }

            return ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final previewData = entry.previewData;
                final name = (previewData['name'] ?? '').toString().trim();
                final imageUrl = (previewData['profileImageUrl'] ?? '')
                    .toString();
                final professions =
                    (previewData['professions'] as List?)
                        ?.map((e) => e.toString())
                        .where((e) => e.trim().isNotEmpty)
                        .toList() ??
                    const <String>[];
                final addedLabel = _formatTimestamp(
                  entry.storedData['addedAt'],
                );

                return InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Profile(userId: entry.targetUid),
                      ),
                    );
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F4C81),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: const Color(0xFFE8F1FB),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(
                                        Icons.person_rounded,
                                        color: Color(0xFF5E7EA6),
                                        size: 30,
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isNotEmpty ? name : fallbackName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF14324A),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (addedLabel.isNotEmpty)
                                      Text(
                                        '${strings['member_since']!} $addedLabel',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF6B7A8C),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE9F3FE),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF0F4C81),
                                ),
                              ),
                            ],
                          ),
                          if (professions.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: professions.take(4).map((profession) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F7FD),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    profession,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF29557A),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            Profile(userId: entry.targetUid),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1976D2),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(strings['open_profile']!),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _FavoriteActionButton(
                                collectionName: collectionName,
                                currentUserId: uid,
                                targetUid: entry.targetUid,
                                strings: strings,
                                isPending: _pendingFavoriteIds.contains(
                                  entry.targetUid,
                                ),
                                onSetFavorite: (shouldFavorite) => _setFavorite(
                                  targetUid: entry.targetUid,
                                  previewData: previewData,
                                  shouldFavorite: shouldFavorite,
                                  strings: strings,
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
            );
          },
        );
      },
    );
  }
}

class _LikedProEntry {
  final String targetUid;
  final Map<String, dynamic> storedData;
  final Map<String, dynamic> previewData;

  const _LikedProEntry({
    required this.targetUid,
    required this.storedData,
    required this.previewData,
  });
}

class _FavoriteActionButton extends StatelessWidget {
  final String collectionName;
  final String currentUserId;
  final String targetUid;
  final Map<String, String> strings;
  final bool isPending;
  final ValueChanged<bool> onSetFavorite;

  const _FavoriteActionButton({
    required this.collectionName,
    required this.currentUserId,
    required this.targetUid,
    required this.strings,
    required this.isPending,
    required this.onSetFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (collectionName == 'favorites') {
      return OutlinedButton(
        onPressed: isPending ? null : () => onSetFavorite(false),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB42318),
          side: const BorderSide(color: Color(0xFFF1C5C5)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isPending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(strings['remove']!),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('favorites')
          .doc(targetUid)
          .snapshots(),
      builder: (context, snapshot) {
        final isSaved = snapshot.data?.exists ?? false;
        return OutlinedButton(
          onPressed: isPending || isSaved ? null : () => onSetFavorite(true),
          style: OutlinedButton.styleFrom(
            foregroundColor: isSaved
                ? const Color(0xFF117A45)
                : const Color(0xFF0F4C81),
            side: BorderSide(
              color: isSaved
                  ? const Color(0xFFB7E4C7)
                  : const Color(0xFFBFD9F4),
            ),
            backgroundColor: isSaved ? const Color(0xFFEFFAF3) : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: isPending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isSaved ? strings['liked']! : strings['like_back']!),
        );
      },
    );
  }
}

class _LikedProsLoadingList extends StatelessWidget {
  const _LikedProsLoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        return Container(
          height: 178,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F4C81),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SkeletonBox(width: 62, height: 62, radius: 18),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonBox(width: 140, height: 16, radius: 8),
                          SizedBox(height: 10),
                          _SkeletonBox(width: 110, height: 12, radius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    _SkeletonBox(width: 84, height: 28, radius: 999),
                    SizedBox(width: 8),
                    _SkeletonBox(width: 74, height: 28, radius: 999),
                  ],
                ),
                Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _SkeletonBox(
                        width: double.infinity,
                        height: 44,
                        radius: 14,
                      ),
                    ),
                    SizedBox(width: 10),
                    _SkeletonBox(width: 96, height: 44, radius: 14),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF5),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _LikedProsEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _LikedProsEmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FD),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.favorite_outline_rounded,
                color: Color(0xFF0F4C81),
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF14324A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                color: Color(0xFF66788A),
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _CountCard({
    required this.label,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
