import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/home.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/formu.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/sighn_in.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => LanguageProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Provider.of<LanguageProvider>(context).locale,
      home: const SignInPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int pagenumber = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const SearchPage(),
    const BlogPage(),
    const profile(),
  ];

  Map<String, String> _getLocalizedLabels(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {'home': 'בית', 'search': 'חיפוש', 'blog': 'בלוג', 'profile': 'פרופיל'};
      case 'ar':
        return {'home': 'الرئيسية', 'search': 'بحث', 'blog': 'مدونة', 'profile': 'الملف الشخصي'};
      case 'ru':
        return {'home': 'Главная', 'search': 'Поиск', 'blog': 'Блог', 'profile': 'Профиль'};
      default:
        return {'home': 'Home', 'search': 'Search', 'blog': 'Blog', 'profile': 'Profile'};
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _getLocalizedLabels(context);
    final isRtl = Provider.of<LanguageProvider>(context).locale.languageCode == 'he' || 
                  Provider.of<LanguageProvider>(context).locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: IndexedStack(
          index: pagenumber,
          children: _pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF1976D2),
          unselectedItemColor: Colors.grey,
          currentIndex: pagenumber,
          onTap: (int index) {
            setState(() {
              pagenumber = index;
            });
          },
          items: [
            BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), label: labels['home']),
            BottomNavigationBarItem(icon: const Icon(Icons.search), label: labels['search']),
            BottomNavigationBarItem(icon: const Icon(Icons.article_outlined), label: labels['blog']),
            BottomNavigationBarItem(icon: const Icon(Icons.person_outline), label: labels['profile']),
          ],
        ),
      ),
    );
  }
}
