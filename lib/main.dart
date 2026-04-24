import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/home.dart';
import 'package:untitled1/search.dart';
import 'package:untitled1/formu.dart';
import 'package:untitled1/ptofile.dart';
import 'package:untitled1/pages/admin_profile.dart';
import 'package:untitled1/widgets/splash_screen.dart';
import 'package:untitled1/pages/inbox_page.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/services/analytics_service.dart';
import 'package:untitled1/services/notification_service.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/sign_in.dart';
import 'services/firebase_options.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve native splash while initializing Firebase and other services.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => LanguageProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool _isInitializing = true;
  bool _isFirebaseInitialized = false;
  Object? _initializationError;

  StreamSubscription<String?>? _notificationTapSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    Object? initializationError;
    var firebaseInitialized = false;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    try {
      debugPrint('Startup: begin Firebase.initializeApp');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw Exception('Firebase.initializeApp timed out on startup.');
        },
      );
      debugPrint('Startup: Firebase.initializeApp completed');

      try {
        await FirebaseAppCheck.instance.activate(
          // Use debug providers on non-release builds to avoid local
          // attestation failures (especially iOS profile/dev runs).
          providerAndroid: kDebugMode
              ? const AndroidDebugProvider()
              : const AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? const AppleDebugProvider()
              : const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (e) {
        debugPrint('App Check activation warning: $e');
      }

      if (isIos) {
        debugPrint(
          'iOS diagnostic mode: skipping notification init during startup.',
        );
      }

      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          kDebugMode) {
        // In local Android debug builds, prefer the reCAPTCHA fallback instead
        // of Play-services verification. This avoids DEVELOPER_ERROR when the
        // current debug keystore fingerprint is not yet registered in Firebase.
        await FirebaseAuth.instance.setSettings(forceRecaptchaFlow: true);
      }

      if (!isIos) {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );

        await NotificationService.init().timeout(
          const Duration(seconds: 5),
          onTimeout: () => debugPrint("Notification initialization timed out"),
        );
        await AnalyticsService.logAppOpen();
        _attachNotificationTapListener();
      } else {
        debugPrint(
          'iOS diagnostic mode: skipping Firestore settings and analytics during startup.',
        );
      }
      firebaseInitialized = true;
    } catch (e, stack) {
      initializationError = e;
      debugPrint("FATAL: Firebase initialization failed: $e");
      debugPrint(stack.toString());
    } finally {
      FlutterNativeSplash.remove();
    }

    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _isFirebaseInitialized = firebaseInitialized;
      _initializationError = initializationError;
    });
  }

  void _attachNotificationTapListener() {
    _notificationTapSubscription?.cancel();
    _notificationTapSubscription = NotificationService
        .selectNotificationStream
        .stream
        .listen((String? payload) {
          if (payload != null && payload.isNotEmpty) {
            try {
              final data = jsonDecode(payload);
              _handleDeepLink(data);
            } catch (e) {
              debugPrint("Error parsing notification payload: $e");
            }
          }
        });
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    if (data['type'] == 'chat' && data['senderId'] != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatPage(
            receiverId: data['senderId'],
            receiverName: data['senderName'] ?? "User",
          ),
        ),
      );
    } else if (data['type'] == 'blog' && data['postId'] != null) {
      _navigateToBlogPost(data['postId']);
    }
  }

  void _navigateToBlogPost(String postId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('blog_posts')
          .doc(postId)
          .get();
      if (doc.exists && mounted) {
        // Post details are handled in BlogPage
      }
    } catch (e) {
      debugPrint("Error navigating to blog post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: Provider.of<LanguageProvider>(context).locale,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF1976D2),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      ),
      navigatorObservers: _isFirebaseInitialized
          ? [AnalyticsService.observer]
          : const <NavigatorObserver>[],
      home: _StartupGate(
        isInitializing: _isInitializing,
        isFirebaseInitialized: _isFirebaseInitialized,
        initializationError: _initializationError,
      ),
    );
  }
}

class _StartupGate extends StatelessWidget {
  final bool isInitializing;
  final bool isFirebaseInitialized;
  final Object? initializationError;

  const _StartupGate({
    required this.isInitializing,
    required this.isFirebaseInitialized,
    required this.initializationError,
  });

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return const SplashScreen();
    }
    if (isFirebaseInitialized) {
      return const AuthWrapper();
    }
    return _ErrorScreen(error: initializationError);
  }
}

class _ErrorScreen extends StatelessWidget {
  final Object? error;
  const _ErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 16),
              const Text(
                "Startup Failed",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? "An unknown error occurred during setup.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text("Exit App"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AuthWrapper manages the navigation state based on Firebase Authentication changes.
/// It acts as the gatekeeper for the application.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SubscriptionAccessService.refreshCurrentUserStateInBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Loading State: Display custom SplashScreen while Firebase is checking auth status.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final user = snapshot.data;

        // 2. Authenticated State: Navigate to the Home Page.
        if (user != null) {
          SubscriptionAccessService.refreshCurrentUserStateInBackground();
          NotificationService.startListening();
          return const MyHomePage();
        }

        // 3. Unauthenticated State: Navigate to the Sign In Page.
        NotificationService.stopListening();
        return const SignInPage();
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
  bool _isAdminProfile = false;

  final List<Widget> _basePages = [
    const HomePage(),
    const SearchPage(),
    const BlogPage(),
    const InboxPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _logCurrentTab();
    NotificationService.selectNotificationStream.stream.listen((
      String? payload,
    ) {
      if (payload != null && payload.isNotEmpty) {
        try {
          final data = jsonDecode(payload);
          _handleDeepLink(data);
        } catch (e) {
          debugPrint("Error parsing notification payload: $e");
        }
      }
    });
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (mounted && doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['role'] == 'admin') {
            setState(() {
              _isAdminProfile = true;
            });
          }
        }
      } catch (e) {
        debugPrint("Admin check error: $e");
      }
    }
  }

  Widget _buildCurrentPage() {
    if (pagenumber < 4) {
      return _basePages[pagenumber];
    }

    if (_isAdminProfile) {
      return const AdminProfile();
    }

    return const Profile();
  }

  Future<void> _logCurrentTab() async {
    const tabNames = [
      'home_tab',
      'search_tab',
      'blog_tab',
      'messages_tab',
      'profile_tab',
    ];
    await AnalyticsService.setCurrentScreen(tabNames[pagenumber]);
  }

  void _onTabSelected(int index) {
    if (pagenumber == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      pagenumber = index;
    });
    _logCurrentTab();
  }

  void _handleDeepLink(Map<String, dynamic> data) {
    if (data['type'] == 'chat' && data['senderId'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            receiverId: data['senderId'],
            receiverName: data['senderName'] ?? "User",
          ),
        ),
      );
    }
  }

  Map<String, String> _getLocalizedLabels(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'home': 'בית',
          'search': 'חיפוש',
          'blog': 'בלוג',
          'messages': 'הודעות',
          'profile': 'פרופיל',
        };
      case 'ar':
        return {
          'home': 'الرئيسية',
          'search': 'بحث',
          'blog': 'مدونة',
          'messages': 'رسائل',
          'profile': 'الملف الشخصي',
        };
      case 'ru':
        return {
          'home': 'Главная',
          'search': 'Поиск',
          'blog': 'Блог',
          'messages': 'Сообщения',
          'profile': 'Профиль',
        };
      case 'am':
        return {
          'home': 'ዋና ገጽ',
          'search': 'ፍለጋ',
          'blog': 'ብሎግ',
          'messages': 'መልእክቶች',
          'profile': 'ፕሮፋይል',
        };
      default:
        return {
          'home': 'Home',
          'search': 'Search',
          'blog': 'Blog',
          'messages': 'Messages',
          'profile': 'Profile',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = _getLocalizedLabels(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final isWide = MediaQuery.of(context).size.width > 900;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: isWide
            ? AppBar(
                title: const Text("Hiro"),
                centerTitle: false,
                actions: [
                  _navButton(0, Icons.home, labels['home'] ?? 'Home'),
                  _navButton(1, Icons.search, labels['search'] ?? 'Search'),
                  _navButton(2, Icons.article, labels['blog'] ?? 'Blog'),
                  _navButton(3, Icons.chat, labels['messages'] ?? 'Messages'),
                  _navButton(4, Icons.person, labels['profile'] ?? 'Profile'),
                  const SizedBox(width: 20),
                ],
              )
            : null,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 1000 : double.infinity,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(pagenumber),
                child: _buildCurrentPage(),
              ),
            ),
          ),
        ),
        bottomNavigationBar: isWide
            ? null
            : _buildFloatingNavigationBar(labels),
      ),
    );
  }

  Widget _buildFloatingNavigationBar(Map<String, String> labels) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1E0F4C81),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: const Color(0x1A1976D2),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF0F4C81)
                      : const Color(0xFF738197),
                );
              }),
            ),
            child: NavigationBar(
              height: 72,
              selectedIndex: pagenumber,
              onDestinationSelected: _onTabSelected,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                NavigationDestination(
                  icon: _AnimatedNavIcon(
                    icon: Icons.home_outlined,
                    isSelected: pagenumber == 0,
                  ),
                  selectedIcon: _AnimatedNavIcon(
                    icon: Icons.home_rounded,
                    isSelected: true,
                  ),
                  label: labels['home'] ?? 'Home',
                ),
                NavigationDestination(
                  icon: _AnimatedNavIcon(
                    icon: Icons.search,
                    isSelected: pagenumber == 1,
                  ),
                  selectedIcon: _AnimatedNavIcon(
                    icon: Icons.search,
                    isSelected: true,
                  ),
                  label: labels['search'] ?? 'Search',
                ),
                NavigationDestination(
                  icon: _AnimatedNavIcon(
                    icon: Icons.article_outlined,
                    isSelected: pagenumber == 2,
                  ),
                  selectedIcon: _AnimatedNavIcon(
                    icon: Icons.article_rounded,
                    isSelected: true,
                  ),
                  label: labels['blog'] ?? 'Blog',
                ),
                NavigationDestination(
                  icon: _AnimatedNavIcon(
                    icon: Icons.chat_bubble_outline,
                    isSelected: pagenumber == 3,
                  ),
                  selectedIcon: _AnimatedNavIcon(
                    icon: Icons.chat_bubble,
                    isSelected: true,
                  ),
                  label: labels['messages'] ?? 'Messages',
                ),
                NavigationDestination(
                  icon: _AnimatedNavIcon(
                    icon: Icons.person_outline,
                    isSelected: pagenumber == 4,
                  ),
                  selectedIcon: _AnimatedNavIcon(
                    icon: Icons.person,
                    isSelected: true,
                  ),
                  label: labels['profile'] ?? 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(int index, IconData icon, String label) {
    final isSelected = pagenumber == index;
    return TextButton.icon(
      onPressed: () => _onTabSelected(index),
      icon: Icon(
        icon,
        color: isSelected ? const Color(0xFF1976D2) : Colors.grey,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF1976D2) : Colors.grey,
        ),
      ),
    );
  }
}

class _AnimatedNavIcon extends StatelessWidget {
  final IconData icon;
  final bool isSelected;

  const _AnimatedNavIcon({required this.icon, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isSelected ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, -2 * t),
          child: Transform.scale(
            scale: 1 + (0.12 * t),
            child: Icon(
              icon,
              color: Color.lerp(
                const Color(0xFF738197),
                const Color(0xFF0F4C81),
                t,
              ),
            ),
          ),
        );
      },
    );
  }
}
