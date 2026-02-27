import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/search.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'welcome': 'ברוך הבא',
          'find_pros': 'מצא מקצוענים מקומיים',
          'search_hint': 'חפש שירות...',
          'categories': 'קטגוריות',
          'see_all': 'ראה הכל ←',
          'top_rated': 'הכי מדורגים',
          'view_all': 'צפה בהכל ←',
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
          'see_all': 'عرض الكل ←',
          'top_rated': 'الأعلى تقييماً',
          'view_all': 'عرض الكل ←',
          'cat_names': {
            'plumber': 'سباك',
            'Carpenter': 'نجار',
            'Electrician': 'كهربائي',
            'Painter': 'دهان',
            'Cleaner': 'عامل نظافة',
            'Handyman': 'عامل صيانة',
            'Landscaper': 'منسق حدائق',
            'HVAC': 'تكييف وتبريد'
          }
        };
      case 'ru':
        return {
          'welcome': 'С возвращением',
          'find_pros': 'Найдите местных профи',
          'search_hint': 'Поиск услуги...',
          'categories': 'Категории',
          'see_all': 'Все ←',
          'top_rated': 'Лучшие',
          'view_all': 'Смотреть все ←',
          'cat_names': {
            'plumber': 'Сантехник',
            'Carpenter': 'Плотник',
            'Electrician': 'Электрик',
            'Painter': 'Маляр',
            'Cleaner': 'Уборщик',
            'Handyman': 'Разнорабочий',
            'Landscaper': 'Ландшафт',
            'HVAC': 'Кондиционеры'
          }
        };
      default:
        return {
          'welcome': 'Welcome back',
          'find_pros': 'Find Local Pros',
          'search_hint': 'Search for a service...',
          'categories': 'Categories',
          'see_all': 'See all →',
          'top_rated': 'Top Rated',
          'view_all': 'View all →',
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
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildHeader(localized),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategories(context, localized),
                    _buildTopRated(context, localized),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> strings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E88E5), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
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
                    strings['welcome'],
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  Text(
                    strings['find_pros'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E88E5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_outlined, color: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: TextField(
              textAlign: Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                        Provider.of<LanguageProvider>(context).locale.languageCode == 'ar' 
                        ? TextAlign.right : TextAlign.left,
              decoration: InputDecoration(
                hintText: strings['search_hint'],
                hintStyle: const TextStyle(color: Colors.black45),
                prefixIcon: const Icon(Icons.search, color: Colors.black45),
                border: InputBorder.none,
              ),
              style: const TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(BuildContext context, Map<String, dynamic> strings) {
    final catNames = strings['cat_names'] as Map<String, String>;
    final List<Map<String, dynamic>> categories = [
      {'key': 'plumber', 'icon': Icons.plumbing_outlined, 'color': const Color(0xFFF3E5F5), 'iconColor': const Color(0xFF8E24AA)},
      {'key': 'Carpenter', 'icon': Icons.handyman_outlined, 'color': const Color(0xFFFFF8E1), 'iconColor': const Color(0xFFFFA000)},
      {'key': 'Electrician', 'icon': Icons.bolt, 'color': const Color(0xFFFFFDE7), 'iconColor': const Color(0xFFFBC02D)},
      {'key': 'Painter', 'icon': Icons.format_paint_outlined, 'color': const Color(0xFFFCE4EC), 'iconColor': const Color(0xFFD81B60)},
      {'key': 'Cleaner', 'icon': Icons.auto_awesome_outlined, 'color': const Color(0xFFE8F5E9), 'iconColor': const Color(0xFF43A047)},
      {'key': 'Handyman', 'icon': Icons.architecture_outlined, 'color': const Color(0xFFF3E5F5), 'iconColor': const Color(0xFF8E24AA)},
      {'key': 'Landscaper', 'icon': Icons.park_outlined, 'color': const Color(0xFFE8F5E9), 'iconColor': const Color(0xFF2E7D32)},
      {'key': 'HVAC', 'icon': Icons.air_outlined, 'color': const Color(0xFFE0F7FA), 'iconColor': const Color(0xFF00ACC1)},
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['categories'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                   Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SearchPage()),
                  );
                },
                child: Text(strings['see_all'], style: const TextStyle(color: Color(0xFF1976D2))),
              ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.7,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final categoryName = catNames[categories[index]['key']] ?? categories[index]['key'];
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: categories[index]['color'],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(categories[index]['icon']),
                      color: categories[index]['iconColor'],
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SearchPage(initialTrade: categoryName),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    categoryName,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopRated(BuildContext context, Map<String, dynamic> strings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            strings['top_rated'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          TextButton(
            onPressed: () {
               Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchPage()),
              );
            },
            child: Text(strings['view_all'], style: const TextStyle(color: Color(0xFF1976D2))),
          ),
        ],
      ),
    );
  }
}
