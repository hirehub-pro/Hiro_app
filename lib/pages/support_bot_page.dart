import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/search.dart';
import 'package:untitled1/pages/verify_business.dart';
import 'package:untitled1/pages/invoice_builder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;

class SupportBotPage extends StatefulWidget {
  const SupportBotPage({super.key});

  @override
  State<SupportBotPage> createState() => _SupportBotPageState();
}

class _SupportBotPageState extends State<SupportBotPage>
    with TickerProviderStateMixin {
  static const String _intentPayment = 'payment';
  static const String _intentInvoice = 'invoice';
  static const String _intentReport = 'report';
  static const String _intentSafety = 'safety';
  static const String _intentHowItWorks = 'how_it_works';
  static const String _intentReviews = 'reviews';
  static const String _intentAccount = 'account';
  static const String _intentStatus = 'status';
  static const String _intentFindPro = 'find_pro';
  static const String _intentWorkerJobs = 'worker_jobs';
  static const String _intentWorkerStats = 'worker_stats';
  static const String _intentGreeting = 'greeting';
  static const String _intentHuman = 'human';

  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  String? _userName;
  String _userRole = 'customer';
  String? _lastIntent;
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _fetchUserData();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  bool get _isRtl {
    final lang = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    return lang == 'he' || lang == 'ar';
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _userName = doc.data()?['name']?.toString().split(' ').first;
          _userRole = doc.data()?['role'] ?? 'customer';
        });
      }
    }
    _addBotMessage(_getGreeting(), quickReplies: _getInitialQuickReplies());
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (_isRtl) {
      String t;
      if (hour < 12) {
        t = "בוקר טוב";
      } else if (hour < 17) {
        t = "צהריים טובים";
      } else {
        t = "ערב טוב";
      }
      return "👋 $t${_userName != null ? ' $_userName' : ''}! אני העוזר החכם של HireHub.\n\nאני יכול לעזור לך **למצוא אנשי מקצוע**, לענות על שאלות בנושאי **תשלום ובטיחות**, ולנהל את **החשבון שלך**. במה אוכל לעזור?";
    }
    String t;
    if (hour < 12) {
      t = "Good morning";
    } else if (hour < 17) {
      t = "Good afternoon";
    } else {
      t = "Good evening";
    }
    return "👋 $t${_userName != null ? ' $_userName' : ''}! I'm your HireHub AI Assistant.\n\nI can help you **find professionals**, answer questions about **payments & safety**, and manage your **account**. How can I help?";
  }

  List<String> _getInitialQuickReplies() {
    if (_userRole == 'worker') {
      return _isRtl
          ? [
              "איך לקבל עבודות?",
              "אימות עסק",
              "חשבונית",
              "הסטטיסטיקות שלי",
              "נציג אנושי",
            ]
          : [
              "How to get jobs?",
              "Verify Business",
              "Invoice Builder",
              "My Stats",
              "Talk to human",
            ];
    }
    return _isRtl
        ? [
            "חיפוש בעל מקצוע",
            "ביטחון ותשלומים",
            "חשבונית",
            "איך זה עובד?",
            "נציג אנושי",
          ]
        : [
            "Find a Pro",
            "Safety & Payments",
            "Invoice Builder",
            "How it works?",
            "Talk to human",
          ];
  }

  void _addBotMessage(
    String text, {
    Widget? action,
    List<String>? quickReplies,
  }) async {
    setState(() => _isTyping = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'text': text,
          'isBot': true,
          'action': action,
          'quickReplies': quickReplies,
          'time': DateTime.now(),
        });
      });
      _scrollToBottom();
    }
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add({'text': text, 'isBot': false, 'time': DateTime.now()});
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleManualInput(String query) {
    if (query.trim().isEmpty || _isTyping) return;
    if (query.trim().length > 500) {
      final isHe = _isRtl;
      _addBotMessage(
        isHe
            ? "ההודעה שלך ארוכה מאוד. אפשר לנסח בקצרה שאלה אחת ואעזור מיד."
            : "Your message is very long. Please send one short question and I'll help right away.",
        quickReplies: _getInitialQuickReplies(),
      );
      return;
    }
    _inputController.clear();
    _addUserMessage(query.trim());
    _processQuery(query);
  }

  String _normalizeQuery(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0590-\u05FF\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesIntent(String normalizedQuery, List<String> keywords) {
    for (final keyword in keywords) {
      final normalizedKeyword = _normalizeQuery(keyword);
      if (normalizedKeyword.isEmpty) continue;
      if (normalizedQuery.contains(normalizedKeyword)) {
        return true;
      }
    }
    return false;
  }

  bool _isFollowUpPrompt(String normalizedQuery) {
    return _matchesIntent(normalizedQuery, [
      'more',
      'details',
      'continue',
      'again',
      'עוד',
      'פרטים',
      'המשך',
      'שוב',
      'زيد',

      'تفاصيل',
    ]);
  }

  String? _detectIntent(String rawQuery) {
    final query = _normalizeQuery(rawQuery);
    if (query.isEmpty) return null;

    final Map<String, List<String>> intentKeywords = {
      _intentPayment: [
        'pay',
        'money',
        'cost',
        'price',
        'fee',
        'charge',
        'שלם',
        'כסף',
        'מחיר',
        'עלות',
        'תשלום',
      ],
      _intentInvoice: [
        'invoice',
        'receipt',
        'document',
        'pdf',
        'חשבונית',
        'קבלה',
        'מסמך',
      ],
      _intentReport: [
        'report',
        'scam',
        'fake',
        'abuse',
        'דיווח',
        'הונאה',
        'מרמה',
      ],
      _intentSafety: [
        'verify',
        'trust',
        'safety',
        'safe',
        'identity',
        'secure',
        'אימות',
        'בטיחות',
        'זהות',
        'מסמכים',
        'מאומת',
      ],
      _intentHowItWorks: [
        'how',
        'work',
        'use',
        'start',
        'begin',
        'explain',
        'איך',
        'כיצד',
        'מה זה',
        'התחל',
        'הסבר',
      ],
      _intentReviews: [
        'review',
        'rating',
        'rate',
        'stars',
        'feedback',
        'דירוג',
        'ביקורת',
        'חוות דעת',
        'כוכבים',
      ],
      _intentAccount: [
        'cancel',
        'delete',
        'account',
        'close',
        'remove',
        'ביטול',
        'בטל',
        'מחק',
        'חשבון',
      ],
      _intentStatus: [
        'status',
        'update',
        'progress',
        'active',
        'סטטוס',
        'עדכון',
        'פרויקט',
      ],
      _intentFindPro: [
        'find',
        'pro',
        'search',
        'hire',
        'professional',
        'worker',
        'contractor',
        'plumber',
        'electrician',
        'painter',
        'handyman',
        'מצא',
        'חפש',
        'עבודה',
        'מקצוע',
        'קבלן',
        'אינסטלטור',
        'חשמלאי',
      ],
      _intentWorkerJobs: [
        'get job',
        'more work',
        'clients',
        'earn',
        'לקוחות',
        'עבודות',
        'הכנסה',
        'להרוויח',
      ],
      _intentWorkerStats: [
        'stat',
        'analytics',
        'earnings',
        'performance',
        'my stats',
        'סטטיסטיקות',
        'ביצועים',
        'הכנסות',
      ],
      _intentGreeting: [
        'hello',
        'hi',
        'hey',
        'thanks',
        'thank you',
        'good',
        'שלום',
        'היי',
        'תודה',
        'בוקר',
      ],
      _intentHuman: [
        'human',
        'person',
        'manager',
        'support',
        'agent',
        'representative',
        'אדם',
        'נציג',
        'מנהל',
        'תמיכה',
      ],
    };

    for (final entry in intentKeywords.entries) {
      if (_matchesIntent(query, entry.value)) {
        return entry.key;
      }
    }

    if (_isFollowUpPrompt(query) && _lastIntent != null) {
      return _lastIntent;
    }

    return null;
  }

  void _processQuery(String query) {
    final isHe = _isRtl;
    final intent = _detectIntent(query);

    if (intent == _intentPayment) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "💰 **מידע על תשלומים:**\nהשימוש ב-HireHub הוא **בחינם לחלוטין**. התשלום מתבצע ישירות מול בעל המקצוע לאחר סיום העבודה.\n\nמומלץ להשתמש ב**מפיק החשבוניות** שלנו לתיעוד בטוח ומסודר."
            : "💰 **Payment Info:**\nHireHub is **completely free** to use. You pay the professional directly after the work is done.\n\nWe recommend using our **Invoice Builder** for secure, professional records.",
        action: _buildNavBtn(
          isHe ? "פתח מפיק חשבוניות" : "Open Invoice Builder",
          InvoiceBuilderPage(workerName: _userName ?? "Professional"),
        ),
        quickReplies: isHe
            ? ["שיטות תשלום בטוחות", "מה לעשות במचלוקת?"]
            : ["Safe payment tips", "What to do in a dispute?"],
      );
    }
    // ── Invoice ─────────────────────────────────────────────────
    else if (intent == _intentInvoice) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "🧾 **מפיק החשבוניות:**\nצור חשבוניות מקצועיות ב-PDF בקלות. מושלם לתיעוד תשלומים והסכמים מול לקוחות."
            : "🧾 **Invoice Builder:**\nCreate professional PDF invoices with ease. Perfect for documenting payments and agreements with clients.",
        action: _buildNavBtn(
          isHe ? "פתח מפיק חשבוניות" : "Open Invoice Builder",
          InvoiceBuilderPage(workerName: _userName ?? "Professional"),
        ),
      );
    }
    // ── Report ──────────────────────────────────────────────────
    else if (intent == _intentReport) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "🚨 **דיווח על בעיה:**\nאנחנו לוקחים כל דיווח ברצינות. אנא פנה לנציג אנושי בצ'אט עם פרטי הבעיה ונטפל בה בהקדם."
            : "🚨 **Report an Issue:**\nWe take every report seriously. Please contact a human representative via chat with the issue details and we'll handle it promptly.",
        action: _buildHumanSupportBtn(isHe),
      );
    }
    // ── Safety & Verification ────────────────────────────────────
    else if (intent == _intentSafety) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "🛡️ **בטיחות ואימות:**\n• עבוד רק עם בעלי מקצוע בעלי תג **מאומת**\n• בקש הצעות מחיר מפורטות לפני תחילת עבודה\n• השתמש במפיק החשבוניות לתיעוד\n\nאם אתה בעל מקצוע, הגש מסמכים ב'פרופיל > אימות עסק'."
            : "🛡️ **Safety & Verification:**\n• Work only with pros with the **Verified** badge\n• Request detailed quotes before work begins\n• Use the Invoice Builder for documentation\n\nIf you're a pro, submit docs in 'Profile > Verify Business'.",
        action: _userRole == 'worker'
            ? _buildNavBtn(
                isHe ? "עבור לאימות עסק" : "Go to Verification",
                const VerifyBusinessPage(),
              )
            : null,
        quickReplies: isHe
            ? ["איך עובד האימות?", "דיווח על בעיה"]
            : ["How does verification work?", "Report an issue"],
      );
    }
    // ── How it works ─────────────────────────────────────────────
    else if (intent == _intentHowItWorks) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "📱 **איך HireHub עובד:**\n\n1️⃣ **חפש** בעל מקצוע לפי תחום\n2️⃣ **צפה** בפרופיל, דירוגים וביקורות\n3️⃣ **שלח הודעה** ישירות דרך הצ'אט\n4️⃣ **סגור פרויקט** וצור חשבונית\n\nכל העסקאות מפוקחות על ידי מערכת האימות שלנו!"
            : "📱 **How HireHub Works:**\n\n1️⃣ **Search** for a professional by trade\n2️⃣ **View** profile, ratings & reviews\n3️⃣ **Message** them directly via chat\n4️⃣ **Close the project** & create an invoice\n\nAll transactions are monitored by our verification system!",
        quickReplies: isHe
            ? ["חיפוש בעל מקצוע", "ביטחון ותשלומים", "חשבונית"]
            : ["Find a Pro", "Safety & Payments", "Invoice Builder"],
      );
    }
    // ── Reviews & Ratings ────────────────────────────────────────
    else if (intent == _intentReviews) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "⭐ **דירוגים וביקורות:**\nלאחר סיום עבודה תוכל לדרג את בעל המקצוע ולהשאיר חוות דעת מהפרופיל שלו.\n\nדירוגים עוזרים לקהילה למצוא את הטובים ביותר!"
            : "⭐ **Ratings & Reviews:**\nAfter a job is done, you can rate the professional and leave a review from their profile.\n\nRatings help the community find the best pros!",
        quickReplies: isHe
            ? ["חיפוש בעל מקצוע", "ביטחון ותשלומים"]
            : ["Find a Pro", "Safety & Payments"],
      );
    }
    // ── Cancellation / Account ───────────────────────────────────
    else if (intent == _intentAccount) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "🗑️ **ניהול חשבון:**\n• **ביטול פרויקט** – תיאם עם בעל המקצוע דרך הצ'אט\n• **מחיקת חשבון** – אפשרי דרך הגדרות הפרופיל תחת 'מחק חשבון'\n\nצריך עזרה נוספת? נציג אנושי ישמח לעזור."
            : "🗑️ **Account Management:**\n• **Cancel a project** – Coordinate with the pro via chat\n• **Delete account** – Available in Profile Settings under 'Delete Account'\n\nNeed more help? A human representative is happy to assist.",
        quickReplies: isHe ? ["נציג אנושי"] : ["Talk to human"],
      );
    }
    // ── Status ───────────────────────────────────────────────────
    else if (intent == _intentStatus) {
      _lastIntent = intent;
      _checkStatus();
    }
    // ── Find a Pro ───────────────────────────────────────────────
    else if (intent == _intentFindPro) {
      _lastIntent = intent;
      _findAProFlow();
    }
    // ── Worker: How to get jobs ───────────────────────────────────
    else if (intent == _intentWorkerJobs) {
      _lastIntent = intent;
      _workerJobTipsFlow();
    }
    // ── Worker: Stats ────────────────────────────────────────────
    else if (intent == _intentWorkerStats) {
      _lastIntent = intent;
      _fetchWorkerStats();
    }
    // ── Greetings ────────────────────────────────────────────────
    else if (intent == _intentGreeting) {
      _lastIntent = intent;
      _addBotMessage(
        isHe
            ? "😊 תמיד שמח לעזור! יש עוד משהו שאוכל לסייע בו?"
            : "😊 Always happy to help! Is there anything else I can assist you with?",
        quickReplies: _getInitialQuickReplies(),
      );
    }
    // ── Human support ────────────────────────────────────────────
    else if (intent == _intentHuman) {
      _lastIntent = intent;
      _connectToHuman(isHe);
    }
    // ── Fallback ─────────────────────────────────────────────────
    else {
      _addBotMessage(
        isHe
            ? "🤔 לא הצלחתי להבין לגמרי. נסה לשאול על:\n• **תשלומים** ומחירים\n• **בטיחות** ואימות\n• **חיפוש** בעל מקצוע\n• **חשבוניות**\n• **הגדרות חשבון**\n\nאו בקש **נציג אנושי** שיעזור לך ישירות."
            : "🤔 I'm not quite sure what you mean. Try asking about:\n• **Payments** & pricing\n• **Safety** & verification\n• **Finding** a professional\n• **Invoices**\n• **Account** settings\n\nOr ask for a **human representative** for direct help.",
        quickReplies: _getInitialQuickReplies(),
      );
    }
  }

  void _connectToHuman(bool isHe) {
    _addBotMessage(
      isHe
          ? "👤 מעביר אותך לנציג אנושי... נא המתן רגע."
          : "👤 Connecting you to a human representative... Please wait a moment.",
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ChatPage(
              receiverId: 'hirehub_manager',
              receiverName: 'HireHub Support',
            ),
          ),
        );
      }
    });
  }

  void _findAProFlow() {
    final isHe = _isRtl;
    _addBotMessage(
      isHe
          ? "🔍 מה אתה מחפש? בחר קטגוריה או הקלד שם מקצוע:"
          : "🔍 What are you looking for? Pick a category or type a trade name:",
      action: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              _buildTradeChip(isHe ? "אינסטלטור" : "Plumber", Icons.plumbing),
              _buildTradeChip(
                isHe ? "חשמלאי" : "Electrician",
                Icons.electrical_services,
              ),
              _buildTradeChip(isHe ? "צבעי" : "Painter", Icons.format_paint),
              _buildTradeChip(isHe ? "הנדימן" : "Handyman", Icons.build),
              _buildTradeChip(isHe ? "נגר" : "Carpenter", Icons.chair),
              _buildTradeChip(
                isHe ? "מנקה" : "Cleaner",
                Icons.cleaning_services,
              ),
              _buildTradeChip(isHe ? "מזגנאי" : "AC Tech", Icons.ac_unit),
              _buildTradeChip(isHe ? "גנן" : "Gardener", Icons.grass),
            ],
          ),
        ),
      ),
      quickReplies: isHe ? ["הצג כל המקצועות"] : ["Show all trades"],
    );
  }

  Widget _buildTradeChip(String trade, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: const Color(0xFF1976D2)),
        label: Text(trade, style: const TextStyle(fontSize: 13)),
        onPressed: () {
          _addUserMessage(trade);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SearchPage(initialTrade: trade)),
          );
        },
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: Color(0xFF1976D2), width: 1),
        elevation: 0,
      ),
    );
  }

  void _workerJobTipsFlow() {
    final isHe = _isRtl;
    _addBotMessage(
      isHe
          ? "💼 **איך להשיג יותר עבודות:**\n\n✅ **מלא פרופיל מלא** – תמונה, תיאור, ניסיון\n✅ **אמת את העסק שלך** – לקוחות מעדיפים בעלי מקצוע מאומתים\n✅ **הגב מהר** – מענה מהיר להודעות מגדיל סיכויים\n✅ **בקש ביקורות** – לאחר כל עבודה\n✅ **הוסף תמונות עבודות** – לפרופיל שלך"
          : "💼 **How to Get More Jobs:**\n\n✅ **Complete your profile** – photo, bio, experience\n✅ **Verify your business** – clients prefer verified pros\n✅ **Respond quickly** – fast replies improve your ranking\n✅ **Request reviews** – after every completed job\n✅ **Add work photos** – to your profile",
      action: _buildNavBtn(
        isHe ? "אמת עסק עכשיו" : "Verify Business Now",
        const VerifyBusinessPage(),
      ),
      quickReplies: isHe
          ? ["אימות עסק", "הסטטיסטיקות שלי"]
          : ["Verify Business", "My Stats"],
    );
  }

  Future<void> _fetchWorkerStats() async {
    final user = FirebaseAuth.instance.currentUser;
    final isHe = _isRtl;

    if (user == null || user.isAnonymous) {
      _addBotMessage(
        isHe
            ? "עליך להתחבר כדי לצפות בסטטיסטיקות."
            : "You need to sign in to view stats.",
      );
      return;
    }

    setState(() => _isTyping = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};
      final int jobsDone = (data['jobsDone'] as num?)?.toInt() ?? 0;
      final double rating = (data['averageRating'] as num?)?.toDouble() ?? 0.0;
      final int reviewCount = (data['reviewCount'] as num?)?.toInt() ?? 0;
      final bool isVerified = data['isVerified'] == true;

      if (mounted) {
        setState(() => _isTyping = false);
        _addBotMessage(
          isHe
              ? "📊 **הסטטיסטיקות שלך:**\n\n🔨 עבודות שהושלמו: **$jobsDone**\n⭐ דירוג ממוצע: **${rating.toStringAsFixed(1)} / 5.0** ($reviewCount ביקורות)\n🛡️ סטטוס אימות: **${isVerified ? 'מאומת ✅' : 'לא מאומת ❌'}**"
              : "📊 **Your Stats:**\n\n🔨 Jobs completed: **$jobsDone**\n⭐ Average rating: **${rating.toStringAsFixed(1)} / 5.0** ($reviewCount reviews)\n🛡️ Verification: **${isVerified ? 'Verified ✅' : 'Not verified ❌'}**",
          action: !isVerified
              ? _buildNavBtn(
                  isHe ? "אמת עסק עכשיו" : "Get Verified Now",
                  const VerifyBusinessPage(),
                )
              : null,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isTyping = false);
        _addBotMessage(
          isHe
              ? "לא הצלחתי לטעון סטטיסטיקות. נסה שוב."
              : "Couldn't load stats. Please try again.",
        );
      }
    }
  }

  Future<void> _checkStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    final isHe = _isRtl;

    if (user == null || user.isAnonymous) {
      _addBotMessage(
        isHe
            ? "עליך להתחבר כדי לראות את הבקשות שלך."
            : "You'll need to sign in to see your active requests.",
      );
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      _addBotMessage(
        isHe
            ? "לא מצאתי בקשות אחרונות. רוצה להתחיל פרויקט חדש?"
            : "I don't see any recent requests. Ready to start your first project?",
        action: _buildNavBtn(
          isHe ? "חיפוש אנשי מקצוע" : "Browse Professionals",
          const SearchPage(),
        ),
      );
    } else {
      final data = snap.docs.first.data();
      final String status = data['status'] ?? 'pending';
      final String name = data['fromName'] ?? (isHe ? 'בעל המקצוע' : 'the pro');
      final String statusEmoji =
          const {
            'pending': '⏳',
            'active': '🔨',
            'completed': '✅',
            'cancelled': '❌',
          }[status] ??
          '📋';
      _addBotMessage(
        isHe
            ? "$statusEmoji הבקשה האחרונה שלך מול **$name** היא בסטטוס: **${status.toUpperCase()}**.\nתקבל התראה ברגע שיהיה עדכון נוסף!"
            : "$statusEmoji Your latest request with **$name** is currently: **${status.toUpperCase()}**.\nYou'll be notified the moment it updates!",
      );
    }
  }

  Widget _buildNavBtn(String label, Widget page) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ElevatedButton.icon(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildHumanSupportBtn(bool isHe) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ElevatedButton.icon(
        onPressed: () => _connectToHuman(isHe),
        icon: const Icon(Icons.support_agent, size: 16),
        label: Text(isHe ? "שוחח עם נציג" : "Chat with Support"),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5FB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1976D2),
          centerTitle: false,
          title: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.smart_toy_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRtl ? "עוזר HireHub" : "HireHub AI Assistant",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[400],
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        isRtl ? "פעיל עכשיו" : "Online",
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
              tooltip: isRtl ? "שיחה חדשה" : "New conversation",
              onPressed: () {
                setState(() => _messages.clear());
                _addBotMessage(
                  _getGreeting(),
                  quickReplies: _getInitialQuickReplies(),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return _buildTypingIndicator(isRtl);
                  }
                  final m = _messages[index];
                  final isLastBot =
                      m['isBot'] == true &&
                      index ==
                          _messages.lastIndexWhere(
                            (msg) => msg['isBot'] == true,
                          );
                  return _buildBubble(m, isRtl, showQuickReplies: isLastBot);
                },
              ),
            ),
            _buildInputArea(isRtl),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(
    Map<String, dynamic> m,
    bool isRtl, {
    bool showQuickReplies = false,
  }) {
    final bool isBot = m['isBot'] as bool;
    final List<String>? quickReplies = m['quickReplies'] as List<String>?;
    final DateTime? time = m['time'] as DateTime?;

    return Column(
      crossAxisAlignment: isBot
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: isBot
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isBot) ...[
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(bottom: 4, right: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.smart_toy,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ],
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isBot ? Colors.white : const Color(0xFF1976D2),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: isBot ? Radius.zero : const Radius.circular(20),
                    bottomRight: isBot
                        ? const Radius.circular(20)
                        : Radius.zero,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildRichText(m['text'] as String, isBot),
              ),
            ),
            if (!isBot) const SizedBox(width: 6),
          ],
        ),
        if (time != null)
          Padding(
            padding: EdgeInsets.only(
              left: isBot ? 42 : 0,
              right: isBot ? 0 : 6,
              bottom: 2,
            ),
            child: Text(
              intl.DateFormat.Hm().format(time),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ),
        if (isBot && m['action'] != null)
          Padding(
            padding: const EdgeInsets.only(left: 42, right: 12),
            child: m['action'] as Widget,
          ),
        if (isBot &&
            showQuickReplies &&
            quickReplies != null &&
            quickReplies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: 42,
              right: 12,
              top: 8,
              bottom: 4,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickReplies
                  .map((reply) => _buildQuickReplyChip(reply))
                  .toList(),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildRichText(String text, bool isBot) {
    final Color baseColor = isBot ? const Color(0xFF334155) : Colors.white;
    final List<InlineSpan> spans = [];
    final RegExp boldReg = RegExp(r'\*\*(.*?)\*\*');
    int lastEnd = 0;
    for (final match in boldReg.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(fontWeight: FontWeight.bold, color: baseColor),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: baseColor, fontSize: 15, height: 1.55),
        children: spans,
      ),
    );
  }

  Widget _buildQuickReplyChip(String label) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF1976D2)),
      ),
      onPressed: () {
        _addUserMessage(label);
        _processQuery(label.toLowerCase());
      },
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFF1976D2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      pressElevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildTypingIndicator(bool isRtl) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(left: 42, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _AnimatedDots(controller: _dotsController),
      ),
    );
  }

  Widget _buildInputArea(bool isRtl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextField(
                  controller: _inputController,
                  enabled: !_isTyping,
                  onSubmitted: _handleManualInput,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: isRtl ? "שאל אותי משהו..." : "Ask me anything...",
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _handleManualInput(_inputController.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _isTyping ? Colors.grey[300] : const Color(0xFF1976D2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: _isTyping ? Colors.grey[500] : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated bouncing dots ───────────────────────────────────────────────────

class _AnimatedDots extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final double offset = (controller.value + i * 0.33) % 1.0;
            final double dy = offset < 0.5
                ? -4 * (offset / 0.5)
                : -4 * (1 - (offset - 0.5) / 0.5);
            return Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF1976D2),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
