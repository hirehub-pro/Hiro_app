import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/services/language_provider.dart';

const _pageBackground = Color(0xFFF6F8FC);
const _surfaceColor = Color(0xFFFFFFFF);
const _primaryColor = Color(0xFF1259A7);
const _deepColor = Color(0xFF0A2A52);
const _softBlue = Color(0xFFE9F2FF);
const _textPrimary = Color(0xFF10243E);
const _textMuted = Color(0xFF6B7A90);

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
          'guest_title': 'כדי לראות את הרשימה הזו צריך להתחבר',
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
          'guest_title': 'سجّل الدخول لعرض هذه القائمة',
        };
      case 'am':
        return {
          'title': 'የወደድኳቸው ባለሙያዎች',
          'subtitle': 'ያስቀመጧቸውን ባለሙያዎች እና እርስዎን የወደዱትን ይከታተሉ።',
          'tab_favorites': 'እኔ የወደድኳቸው',
          'tab_liked_me': 'እኔን የወደዱ',
          'empty_favorites': 'እስካሁን ምንም ባለሙያ ወደ ተወዳጆች አልጨመሩም።',
          'empty_liked_me': 'እስካሁን እርስዎን የወደዱ ባለሙያዎች የሉም።',
          'open_profile': 'ፕሮፋይል ክፈት',
          'no_name': 'ባለሙያ',
          'saved_count': 'ያስቀመጧቸው',
          'incoming_count': 'እርስዎን ወደዱ',
          'member_since': 'የተቀመጠበት',
          'guest': 'የወደዱትን ዝርዝር ለማየት እባክዎ ይግቡ።',
          'retry_error': 'ውሂብ ሲጫን ችግር ተፈጥሯል።',
          'search_hint': 'በስም ወይም በሙያ ፈልግ',
          'no_results': 'ለፍለጋዎ የሚዛመዱ ውጤቶች አልተገኙም።',
          'remove': 'አስወግድ',
          'removed': 'ከተወዳጆች ተወግዷል',
          'like_back': 'እኔም እወዳለሁ',
          'liked': 'ተቀምጧል',
          'saved_now': 'ወደ ተወዳጆች ተጨምሯል',
          'browse': 'ባለሙያዎችን ፈልግ',
          'empty_title_favorites': 'ገና ተወዳጆች የሉም',
          'empty_title_liked': 'ገና ወደዶች የሉም',
          'guest_title': 'ይህን ዝርዝር ለማየት ይግቡ',
        };
      case 'ru':
        return {
          'title': 'Понравившиеся специалисты',
          'subtitle':
              'Следите за специалистами, которых вы сохранили, и теми, кто отметил вас.',
          'tab_favorites': 'Я отметил',
          'tab_liked_me': 'Отметили меня',
          'empty_favorites': 'Вы еще не добавили специалистов в избранное.',
          'empty_liked_me': 'Пока никто не добавил вас в избранное.',
          'open_profile': 'Открыть профиль',
          'no_name': 'Специалист',
          'saved_count': 'Сохранено',
          'incoming_count': 'Отметили вас',
          'member_since': 'Сохранено',
          'guest':
              'Войдите, чтобы посмотреть список понравившихся специалистов.',
          'retry_error': 'Произошла ошибка при загрузке данных.',
          'search_hint': 'Поиск по имени или профессии',
          'no_results': 'По вашему запросу ничего не найдено.',
          'remove': 'Удалить',
          'removed': 'Удалено из избранного',
          'like_back': 'Отметить в ответ',
          'liked': 'Сохранено',
          'saved_now': 'Добавлено в избранное',
          'browse': 'Найти специалистов',
          'empty_title_favorites': 'Пока нет избранного',
          'empty_title_liked': 'Пока нет отметок',
          'guest_title': 'Войдите, чтобы увидеть этот список',
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
          'guest_title': 'Sign in to see this list',
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
    final currentUser = _currentUser;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _pageBackground,
        body: currentUser == null || currentUser.isAnonymous
            ? _LikedProsGuestState(
                title: strings['guest_title']!,
                message: strings['guest']!,
              )
            : Stack(
                children: [
                  const _LikedProsBackground(),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: _buildHeader(strings),
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
                                  return (data['sourceUserId'] ?? doc.id)
                                      .toString();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF154C8D), Color(0xFF091D39)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29091D39),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings['title']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: _deepColor,
              unselectedLabelColor: Colors.white,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: strings['tab_favorites']),
                Tab(text: strings['tab_liked_me']),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: _primaryColor,
              decoration: InputDecoration(
                border: InputBorder.none,
                prefixIcon: const Icon(
                  CupertinoIcons.search,
                  color: _primaryColor,
                  size: 20,
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
                          color: _textMuted,
                        ),
                      ),
                hintText: strings['search_hint']!,
                hintStyle: const TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
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

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final previewData = entry.previewData;
                      final name = (previewData['name'] ?? '')
                          .toString()
                          .trim();
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

                      return _LikedProCard(
                        title: name.isNotEmpty ? name : fallbackName,
                        imageUrl: imageUrl,
                        professions: professions,
                        addedLabel: addedLabel,
                        memberSinceLabel: strings['member_since']!,
                        openProfileLabel: strings['open_profile']!,
                        onOpenProfile: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Profile(userId: entry.targetUid),
                            ),
                          );
                        },
                        actionButton: _FavoriteActionButton(
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
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 18),
                  ),
                ),
              ],
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
          backgroundColor: const Color(0xFFFFF5F4),
          side: const BorderSide(color: Color(0xFFF3CAC5)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
            foregroundColor: isSaved ? const Color(0xFF117A45) : _primaryColor,
            side: BorderSide(
              color: isSaved
                  ? const Color(0xFFB7E4C7)
                  : const Color(0xFFC6D9F9),
            ),
            backgroundColor: isSaved ? const Color(0xFFEFFAF3) : _softBlue,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        return Container(
          height: 232,
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120A2A52),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SkeletonBox(width: 68, height: 68, radius: 22),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonBox(width: 152, height: 18, radius: 10),
                          SizedBox(height: 10),
                          _SkeletonBox(width: 124, height: 12, radius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    _SkeletonBox(width: 92, height: 30, radius: 999),
                    SizedBox(width: 8),
                    _SkeletonBox(width: 82, height: 30, radius: 999),
                  ],
                ),
                SizedBox(height: 14),
                _SkeletonBox(width: 110, height: 12, radius: 8),
                Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _SkeletonBox(
                        width: double.infinity,
                        height: 48,
                        radius: 16,
                      ),
                    ),
                    SizedBox(width: 10),
                    _SkeletonBox(width: 108, height: 48, radius: 16),
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
        color: const Color(0xFFE6EDF7),
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
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE7F0FF), Color(0xFFD9E8FF)],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.favorite_outline_rounded,
                color: _primaryColor,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                color: _textMuted,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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

class _LikedProsBackground extends StatelessWidget {
  const _LikedProsBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: _pageBackground),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 280,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFD9E8FF), Color(0xFFF6F8FC)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -70,
          right: -40,
          child: Container(
            width: 190,
            height: 190,
            decoration: const BoxDecoration(
              color: Color(0x30FFFFFF),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _LikedProCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final List<String> professions;
  final String addedLabel;
  final String memberSinceLabel;
  final String openProfileLabel;
  final VoidCallback onOpenProfile;
  final Widget actionButton;

  const _LikedProCard({
    required this.title,
    required this.imageUrl,
    required this.professions,
    required this.addedLabel,
    required this.memberSinceLabel,
    required this.openProfileLabel,
    required this.onOpenProfile,
    required this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onOpenProfile,
      child: Ink(
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140A2A52),
              blurRadius: 16,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE8F2FF), Color(0xFFD7E8FF)],
                      ),
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
                            size: 32,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (addedLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F7FD),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$memberSinceLabel $addedLabel',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (professions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  professions.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onOpenProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(openProfileLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  actionButton,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikedProsGuestState extends StatelessWidget {
  final String title;
  final String message;

  const _LikedProsGuestState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _LikedProsBackground(),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x140A2A52),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _softBlue,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: _primaryColor,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
