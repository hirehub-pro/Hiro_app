import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroController;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'אודות ומשפטי',
          'app_name': 'hiro',
          'version': 'גרסה 1.0.0',
          'tagline': 'מחברים בין לקוחות לבעלי מקצוע אמינים במהירות.',
          'intro_title': 'מה זה Hiro?',
          'intro_body':
              'Hiro היא פלטפורמה חכמה למציאת בעלי מקצוע, שליחת בקשות עבודה, קבלת הצעות מחיר וניהול תקשורת במקום אחד פשוט.',
          'terms_title': 'תנאי שימוש',
          'privacy_title': 'מדיניות פרטיות',
          'terms_content':
              'ברוכים הבאים ל-Hiro. בשימוש באפליקציה, הנך מסכים לתנאים הבאים:\n1. Hiro היא פלטפורמת תיווך בלבד.\n2. האחריות על איכות העבודה, השירות והתשלום היא בין הלקוח לבעל המקצוע.\n3. חל איסור על פרסום תוכן פוגעני, מטעה או כוזב.\n4. המערכת רשאית להשעות משתמשים המפרים את הכללים או פוגעים בבטיחות הקהילה.',
          'privacy_content':
              'הפרטיות שלך חשובה לנו:\n1. אנו אוספים מידע בסיסי כמו שם, טלפון ועיר כדי לאפשר את פעילות השירות.\n2. מיקום משמש למציאת בעלי מקצוע קרובים ולהצגת שירותים רלוונטיים.\n3. המידע שלך אינו נמכר לצד שלישי למטרות פרסום.\n4. ניתן לבקש מחיקת חשבון ומידע דרך ההגדרות או התמיכה.',
          'highlights_title': 'למה משתמשים ב-Hiro',
          'highlight_match_title': 'חיפוש מהיר',
          'highlight_match_body': 'מצא בעלי מקצוע קרובים לפי עיר, תחום ומיקום.',
          'highlight_request_title': 'בקשות מסודרות',
          'highlight_request_body': 'שלח בקשות עבודה וקבל תגובות במקום אחד.',
          'highlight_safe_title': 'מידע ברור',
          'highlight_safe_body': 'נהל פרטים, סטטוסים והתראות בצורה מסודרת.',
          'developer': 'פותח על ידי צוות Hiro',
          'contact': 'צור קשר: support@hiro.com',
          'contact_hint': 'לשאלות, תמיכה או דיווח על בעיה נשמח לעזור.',
        };
      case 'ar':
        return {
          'title': 'حول والقانونية',
          'app_name': 'Hiro',
          'version': 'الإصدار 1.0.0',
          'tagline': 'نربط العملاء بأصحاب المهن بسرعة ووضوح.',
          'intro_title': 'ما هو Hiro؟',
          'intro_body':
              'Hiro هو تطبيق يساعدك على العثور على المهنيين، إرسال طلبات العمل، تلقي عروض الأسعار، وإدارة التواصل في مكان واحد سهل.',
          'terms_title': 'شروط الخدمة',
          'privacy_title': 'سياسة الخصوصية',
          'terms_content':
              'مرحباً بكم في Hiro. باستخدام التطبيق فإنك توافق على الشروط التالية:\n1. Hiro هي منصة وساطة فقط.\n2. المسؤولية عن جودة العمل والخدمة والدفع تقع بين العميل والمهني.\n3. يمنع نشر محتوى مسيء أو مضلل أو كاذب.\n4. يحق للمنصة تعليق الحسابات التي تنتهك القواعد أو تضر بسلامة المجتمع.',
          'privacy_content':
              'خصوصيتك مهمة لنا:\n1. نجمع معلومات أساسية مثل الاسم والهاتف والمدينة لتشغيل الخدمة.\n2. يتم استخدام الموقع للعثور على المهنيين القريبين وإظهار خدمات مناسبة.\n3. لا يتم بيع بياناتك لأطراف ثالثة لأغراض إعلانية.\n4. يمكنك طلب حذف الحساب والبيانات من خلال الإعدادات أو الدعم.',
          'highlights_title': 'لماذا يستخدم الناس Hiro',
          'highlight_match_title': 'بحث سريع',
          'highlight_match_body': 'اعثر على المهنيين القريبين حسب المدينة والمجال والموقع.',
          'highlight_request_title': 'طلبات منظمة',
          'highlight_request_body': 'أرسل طلبات العمل وتابع الردود من مكان واحد.',
          'highlight_safe_title': 'معلومات واضحة',
          'highlight_safe_body': 'تابع التفاصيل والحالات والتنبيهات بشكل مرتب.',
          'developer': 'تم التطوير بواسطة فريق Hiro',
          'contact': 'تواصل معنا: support@hiro.com',
          'contact_hint': 'للاستفسارات أو الدعم أو الإبلاغ عن مشكلة نحن هنا للمساعدة.',
        };
      case 'am':
        return {
          'title': 'ስለ እኛ እና ህጋዊ',
          'app_name': 'Hiro',
          'version': 'ስሪት 1.0.0',
          'tagline': 'ደንበኞችን ከባለሙያዎች ጋር በፍጥነት የሚያገናኝ መተግበሪያ።',
          'intro_title': 'Hiro ምንድን ነው?',
          'intro_body':
              'Hiro ባለሙያዎችን ለማግኘት፣ የስራ ጥያቄ ለመላክ፣ የዋጋ ጥቅስ ለመቀበል እና ግንኙነትን በአንድ ቦታ ለማስተዳደር የሚረዳ መተግበሪያ ነው።',
          'terms_title': 'የአጠቃቀም ደንቦች',
          'privacy_title': 'የግላዊነት ፖሊሲ',
          'terms_content':
              'ወደ Hiro እንኳን ደህና መጡ። መተግበሪያውን ሲጠቀሙ በሚከተሉት ደንቦች ይስማማሉ፡\n1. Hiro የማገናኛ መድረክ ብቻ ነው።\n2. የስራ ጥራት፣ አገልግሎት እና ክፍያ ኃላፊነት በደንበኛው እና በባለሙያው መካከል ነው።\n3. አስጸያፊ፣ የሚያሳስብ ወይም ሐሰተኛ ይዘት ማቅረብ የተከለከለ ነው።\n4. ደንቦችን የሚጥሱ ወይም የማህበረሰቡን ደህንነት የሚጎዱ ተጠቃሚዎችን ማገድ እንችላለን።',
          'privacy_content':
              'የእርስዎ ግላዊነት ለእኛ አስፈላጊ ነው፡\n1. አገልግሎቱን ለማስኬድ መሰረታዊ መረጃዎችን እንደ ስም፣ ስልክ እና ከተማ እንሰበስባለን።\n2. ቅርብ ባለሙያዎችን ለማግኘት እና ተገቢ አገልግሎቶችን ለማሳየት አካባቢ መረጃ ይጠቀማል።\n3. መረጃዎ ለማስታወቂያ ዓላማ ለሶስተኛ ወገን አይሸጥም።\n4. አካውንት እና መረጃ ስረዛ በቅንብሮች ወይም በድጋፍ ማስገባት ይቻላል።',
          'highlights_title': 'ሰዎች Hiro የሚጠቀሙበት ምክንያት',
          'highlight_match_title': 'ፈጣን ፍለጋ',
          'highlight_match_body': 'በከተማ፣ በሙያ እና በቦታ ቅርብ ባለሙያዎችን ያግኙ።',
          'highlight_request_title': 'የተደራጁ ጥያቄዎች',
          'highlight_request_body': 'የስራ ጥያቄ ላኩ እና ምላሾችን በአንድ ቦታ ይከታተሉ።',
          'highlight_safe_title': 'ግልጽ መረጃ',
          'highlight_safe_body': 'ዝርዝሮችን፣ ሁኔታዎችን እና ማሳወቂያዎችን በቀላሉ ያስተዳድሩ።',
          'developer': 'በ Hiro ቡድን የተገነባ',
          'contact': 'ያግኙን: support@hiro.com',
          'contact_hint': 'ለጥያቄ፣ ለድጋፍ ወይም ችግር ሪፖርት እኛ እንረዳለን።',
        };
      default:
        return {
          'title': 'About & Legal',
          'app_name': 'Hiro',
          'version': 'Version 1.0.0',
          'tagline': 'Connecting clients with trusted professionals, fast.',
          'intro_title': 'What is Hiro?',
          'intro_body':
              'Hiro helps people find professionals, send work requests, receive quotes, and manage communication in one simple place.',
          'terms_title': 'Terms of Service',
          'privacy_title': 'Privacy Policy',
          'terms_content':
              'Welcome to Hiro. By using this app, you agree to the following:\n1. Hiro is a matching platform only.\n2. Quality of work, service delivery, and payment are strictly between the client and the professional.\n3. Posting offensive, misleading, or false content is prohibited.\n4. We may suspend accounts that violate the rules or harm community safety.',
          'privacy_content':
              'Your privacy matters:\n1. We collect basic information like name, phone, and city to operate the service.\n2. Location data is used to find nearby professionals and show relevant services.\n3. Your data is not sold to third parties for advertising.\n4. You can request account and data deletion through settings or support.',
          'highlights_title': 'Why People Use Hiro',
          'highlight_match_title': 'Fast discovery',
          'highlight_match_body':
              'Find nearby professionals by city, category, and location.',
          'highlight_request_title': 'Organized requests',
          'highlight_request_body':
              'Send job requests and manage responses in one place.',
          'highlight_safe_title': 'Clear information',
          'highlight_safe_body':
              'Keep track of details, statuses, and notifications with less friction.',
          'developer': 'Developed by the Hiro Team',
          'contact': 'Contact us: support@hiro.com',
          'contact_hint':
              'Questions, support requests, or issue reports are always welcome.',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: AppBar(
          title: Text(
            strings['title']!,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE3F2FD), Color(0xFFF6F8FC), Color(0xFFFFFFFF)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnimatedSection(
                    delay: 0,
                    child: _buildHero(strings),
                  ),
                  const SizedBox(height: 20),
                  _buildAnimatedSection(
                    delay: 120,
                    child: _buildIntroCard(strings),
                  ),
                  const SizedBox(height: 20),
                  _buildAnimatedSection(
                    delay: 240,
                    child: _buildHighlights(strings),
                  ),
                  const SizedBox(height: 20),
                  _buildAnimatedSection(
                    delay: 360,
                    child: _buildLegalSection(
                      title: strings['terms_title']!,
                      body: strings['terms_content']!,
                      icon: Icons.gavel_rounded,
                      accent: const Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAnimatedSection(
                    delay: 480,
                    child: _buildLegalSection(
                      title: strings['privacy_title']!,
                      body: strings['privacy_content']!,
                      icon: Icons.verified_user_outlined,
                      accent: const Color(0xFF1D4ED8),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildAnimatedSection(
                    delay: 600,
                    child: _buildContactCard(strings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedSection({
    required Widget child,
    required int delay,
  }) {
    final begin = delay / 1000;
    final end = (begin + 0.55).clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        final delayedValue = ((value - begin) / (end - begin)).clamp(0.0, 1.0);
        final opacity = delayedValue.toDouble();
        final offsetY = (1 - delayedValue) * 28;
        final scale = 0.96 + (0.04 * delayedValue);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: animatedChild,
            ),
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildHero(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5), Color(0xFF4FC3F7)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221565C0),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -10,
                top: -8,
                child: AnimatedBuilder(
                  animation: _heroController,
                  builder: (context, child) {
                    final dy = -10 + (_heroController.value * 20);
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 68,
                top: 64,
                child: AnimatedBuilder(
                  animation: _heroController,
                  builder: (context, child) {
                    final dy = 8 - (_heroController.value * 16);
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 850),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset((1 - value) * 18, 0),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        strings['version']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            strings['app_name']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['tagline']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF0369A1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings['intro_title']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strings['intro_body']!,
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlights(Map<String, String> strings) {
    final items = [
      (
        strings['highlight_match_title']!,
        strings['highlight_match_body']!,
        Icons.travel_explore_rounded,
        const Color(0xFFDBEAFE),
        const Color(0xFF1D4ED8),
      ),
      (
        strings['highlight_request_title']!,
        strings['highlight_request_body']!,
        Icons.assignment_turned_in_outlined,
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
      ),
      (
        strings['highlight_safe_title']!,
        strings['highlight_safe_body']!,
        Icons.notifications_active_outlined,
        const Color(0xFFFCE7F3),
        const Color(0xFFBE185D),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            strings['highlights_title']!,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildHighlightCard(
              title: item.$1,
              body: item.$2,
              icon: item.$3,
              background: item.$4,
              foreground: item.$5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightCard({
    required String title,
    required String body,
    required IconData icon,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: foreground),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalSection({
    required String title,
    required String body,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.75,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.support_agent_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Support',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            strings['developer']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['contact']!,
            style: const TextStyle(
              color: Color(0xFF7DD3FC),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['contact_hint']!,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
