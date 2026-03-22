import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/home.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/formu.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/splash_screen.dart';
import 'package:untitled1/pages/inbox_page.dart';
import 'package:untitled1/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Hide the navigation bar and status bar for a full-screen experience
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await Firebase.initializeApp();

  // Enable Firestore persistence to keep user info available offline/between restarts.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Initialize notifications asynchronously to avoid blocking main
  NotificationService.init();

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
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1976D2),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // If auth state is still loading, show the splash screen without auto-navigation
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(navigateToSignIn: false);
        }

        final user = snapshot.data;
        if (user != null) {
          // Start listening for notifications when user is logged in
          NotificationService.startListening();
          return const MyHomePage();
        }

        // Stop listening when logged out
        NotificationService.stopListening();
        // Return SplashScreen which handles the navigation to SignInPage if needed
        return const SplashScreen();
      },
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
    const InboxPage(),
    const Profile(),
  ];

  Map<String, String> _getLocalizedLabels(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {'home': 'בית', 'search': 'חיפוש', 'blog': 'בלוג', 'messages': 'הודעות', 'profile': 'פרופיל'};
      case 'ar':
        return {'home': 'الرئيسية', 'search': 'بحث', 'blog': 'مدونة', 'messages': 'رسائل', 'profile': 'الملف الشخصي'};
      case 'ru':
        return {'home': 'Главная', 'search': 'Поиск', 'blog': 'Блог', 'messages': 'Сообщения', 'profile': 'Профиль'};
      case 'am':
        return {'home': 'ዋና ገጽ', 'search': 'ፍለጋ', 'blog': 'ብሎግ', 'messages': 'መልእክቶች', 'profile': 'ፕሮፋይል'};
      default:
        return {'home': 'Home', 'search': 'Search', 'blog': 'Blog', 'messages': 'Messages', 'profile': 'Profile'};
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
            BottomNavigationBarItem(icon: const Icon(Icons.chat_bubble_outline), label: labels['messages']),
            BottomNavigationBarItem(icon: const Icon(Icons.person_outline), label: labels['profile']),
          ],
        ),
      ),
    );
  }
}
