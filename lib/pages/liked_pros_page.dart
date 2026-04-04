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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, String> _strings(String localeCode) {
    switch (localeCode) {
      case 'he':
        return {
          'title': 'בעלי מקצוע שאהבתי',
          'tab_favorites': 'אני אהבתי',
          'tab_liked_me': 'אהבו אותי',
          'empty_favorites': 'עדיין לא שמרת בעלי מקצוע למועדפים.',
          'empty_liked_me': 'עדיין אין בעלי מקצוע שסימנו אותך כמועדף.',
          'open_profile': 'פתח פרופיל',
          'no_name': 'בעל מקצוע',
        };
      case 'ar':
        return {
          'title': 'المهنيون المفضلون',
          'tab_favorites': 'أنا أحببت',
          'tab_liked_me': 'أعجبوا بي',
          'empty_favorites': 'لم تقم بحفظ أي مهني في المفضلة بعد.',
          'empty_liked_me': 'لا يوجد مهنيون أضافوك إلى المفضلة بعد.',
          'open_profile': 'فتح الملف',
          'no_name': 'مهني',
        };
      default:
        return {
          'title': 'Liked Pros',
          'tab_favorites': 'Pros I Like',
          'tab_liked_me': 'Pros Who Like Me',
          'empty_favorites': 'You have not added any pros to favorites yet.',
          'empty_liked_me': 'No pros have favorited you yet.',
          'open_profile': 'Open Profile',
          'no_name': 'Pro',
        };
    }
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
        appBar: AppBar(
          title: Text(strings['title']!),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: strings['tab_favorites']),
              Tab(text: strings['tab_liked_me']),
            ],
          ),
        ),
        body: _currentUser == null || _currentUser!.isAnonymous
            ? const Center(child: Text('Please sign in to continue.'))
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildProsList(
                    collectionName: 'favorites',
                    emptyText: strings['empty_favorites']!,
                    fallbackName: strings['no_name']!,
                    uidResolver: (doc) => doc.id,
                  ),
                  _buildProsList(
                    collectionName: 'likedBy',
                    emptyText: strings['empty_liked_me']!,
                    fallbackName: strings['no_name']!,
                    uidResolver: (doc) {
                      final data = doc.data();
                      return (data['sourceUserId'] ?? doc.id).toString();
                    },
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
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Failed to load data: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final targetUid = uidResolver(doc);
            final name = (data['name'] ?? '').toString().trim();
            final imageUrl = (data['profileImageUrl'] ?? '').toString();
            final professions =
                (data['professions'] as List?)
                    ?.map((e) => e.toString())
                    .where((e) => e.trim().isNotEmpty)
                    .toList() ??
                const <String>[];

            return Card(
              margin: EdgeInsets.zero,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: imageUrl.isNotEmpty
                      ? CachedNetworkImageProvider(imageUrl)
                      : null,
                  child: imageUrl.isEmpty
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                title: Text(
                  name.isNotEmpty ? name : fallbackName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: professions.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          professions.join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  if (targetUid.isEmpty) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Profile(userId: targetUid),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
