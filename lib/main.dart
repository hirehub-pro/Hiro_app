import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/home.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/formu.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/sighn_in.dart';
import 'package:untitled1/pages/settings.dart';
import 'package:untitled1/pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://hire-hub-fe6c4-default-rtdb.firebaseio.com'
  );
  
  database.setPersistenceEnabled(false);

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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const MyHomePage();
          }
          return const SplashScreen();
        },
      ),
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
    const SettingsPage(),
  ];

  Map<String, String> _getLocalizedLabels(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {'home': 'בית', 'search': 'חיפוש', 'blog': 'בלוג', 'profile': 'פרופיל', 'settings': 'הגדרות'};
      case 'ar':
        return {'home': 'الرئيسية', 'search': 'بحث', 'blog': 'مدونة', 'profile': 'الملف الشخصي', 'settings': 'الإعدادات'};
      case 'ru':
        return {'home': 'Главная', 'search': 'Поиск', 'blog': 'Блог', 'profile': 'Профиль', 'settings': 'Настройки'};
      case 'am':
        return {'home': 'ዋና ገጽ', 'search': 'ፍለጋ', 'blog': 'ብሎግ', 'profile': 'ፕሮፋይል', 'settings': 'ቅንብሮች'};
      default:
        return {'home': 'Home', 'search': 'Search', 'blog': 'Blog', 'profile': 'Profile', 'settings': 'Settings'};
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _getLocalizedLabels(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

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
            BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: labels['settings']),
          ],
        ),
      ),
    );
  }
}
