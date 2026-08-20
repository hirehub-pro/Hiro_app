import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/help_page.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

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
          'title': 'אודות',
          'app_name': 'Hiro',
          'version': 'גרסה 1.0.0',
          'tagline':
              'מחברים בין לקוחות לבעלי מקצוע, צ׳אטים, בקשות עבודה וכלי ניהול במקום אחד.',
          'intro_title': 'מה זה Hiro?',
          'intro_body':
              'Hiro היא פלטפורמה למציאת בעלי מקצוע, שליחת בקשות עבודה, ניהול שיחות, מעקב אחרי תגובות, עבודה עם מנויים וכלים כמו חשבוניות, פוסטים ופרופיל עסקי.',
          'highlights_title': 'מה יש באפליקציה',
          'highlight_match_title': 'איתור בעלי מקצוע',
          'highlight_match_body':
              'חיפוש לפי מקצוע, אזור, פרופיל עסקי וזמינות כדי למצוא את ההתאמה הנכונה מהר.',
          'highlight_request_title': 'בקשות עבודה וצ׳אט',
          'highlight_request_body':
              'שליחת בקשות, המשך טיפול דרך צ׳אט, תמונות, קבצים ועדכוני סטטוס במקום אחד.',
          'highlight_community_title': 'קהילה, פוסטים ועדכונים',
          'highlight_community_body':
              'פרסום פוסטים, שיתוף מידע, קבלת תגובות וחיבור לקהילה שסביב השירותים שלך.',
          'highlight_pro_title': 'כלים לבעלי מקצוע',
          'highlight_pro_body':
              'מנוי פעיל פותח גישה לכלי Pro כמו חשבוניות, תגובה לבקשות ונראות מקצועית טובה יותר.',
          'trust_title': 'למה אנשים משתמשים ב-Hiro',
          'trust_1': 'כדי לנהל בקשות, תגובות ושיחות במקום מסודר.',
          'trust_2': 'כדי למצוא בעלי מקצוע רלוונטיים עם פחות חיפוש ידני.',
          'trust_3': 'כדי לעקוב אחרי פרופילים, סטטוסים והודעות בצורה ברורה.',
          'trust_4':
              'כדי לקבל חוויית עבודה שמתאימה גם ללקוחות וגם לבעלי מקצוע.',
          'legal_title': 'קישורים משפטיים',
          'legal_body':
              'תנאי השימוש ומדיניות הפרטיות זמינים בקישורים הרשמיים ומתעדכנים מחוץ לאפליקציה.',
          'terms_title': 'תנאי שימוש',
          'terms_body': 'פתח את תנאי השימוש המעודכנים.',
          'privacy_title': 'מדיניות פרטיות',
          'privacy_body': 'פתח את מדיניות הפרטיות המעודכנת.',
          'open_link': 'פתח קישור',
          'contact_title': 'צור קשר',
          'developer': 'פותח על ידי צוות Hiro',
          'contact': 'support@hiro-services.com',
          'contact_hint':
              'לשאלות, תמיכה, דיווח על בעיה או בירור משפטי, בחרו את דרך הקשר שנוחה לכם.',
          'email_action': 'דוא״ל',
          'whatsapp_action': 'WhatsApp',
          'app_chat_action': 'צ׳אט באפליקציה',
          'whatsapp_number': '0542978614',
          'link_failed': 'לא הצלחנו לפתוח את הקישור כרגע.',
          'email_failed': 'לא הצלחנו לפתוח את אפליקציית האימייל.',
          'whatsapp_failed': 'לא הצלחנו לפתוח את WhatsApp כרגע.',
        };
      case 'ar':
        return {
          'title': 'حول',
          'app_name': 'Hiro',
          'version': 'الإصدار 1.0.0',
          'tagline':
              'ربط العملاء بأصحاب المهن والدردشات وطلبات العمل وأدوات الإدارة في مكان واحد.',
          'intro_title': 'ما هو Hiro؟',
          'intro_body':
              'Hiro منصة تساعدك على العثور على أصحاب المهن، إرسال طلبات العمل، إدارة المحادثات، متابعة الردود، واستخدام الاشتراكات وأدوات مثل الفواتير والمنشورات والملف التجاري.',
          'highlights_title': 'ماذا يوجد في التطبيق',
          'highlight_match_title': 'العثور على أصحاب المهن',
          'highlight_match_body':
              'ابحث حسب المهنة أو المنطقة أو الملف التجاري أو التوفر للوصول إلى الشخص المناسب بسرعة.',
          'highlight_request_title': 'طلبات العمل والدردشة',
          'highlight_request_body':
              'أرسل الطلبات، واصل المتابعة عبر الدردشة، الصور، الملفات وتحديثات الحالة في مكان واحد.',
          'highlight_community_title': 'المجتمع والمنشورات',
          'highlight_community_body':
              'انشر، شارك المعرفة، احصل على ردود، وابقَ متصلاً بالمجتمع حول خدماتك.',
          'highlight_pro_title': 'أدوات أصحاب المهن',
          'highlight_pro_body':
              'الاشتراك النشط يفتح أدوات Pro مثل الفواتير والرد على الطلبات وحضور مهني أقوى.',
          'trust_title': 'لماذا يستخدم الناس Hiro',
          'trust_1': 'لإدارة الطلبات والردود والمحادثات بشكل منظم.',
          'trust_2':
              'للعثور على أصحاب المهن المناسبين بسرعة أقل من البحث اليدوي.',
          'trust_3': 'لمتابعة الملفات الشخصية والحالات والرسائل بوضوح.',
          'trust_4': 'لأن التجربة تناسب العملاء وأصحاب المهن معًا.',
          'legal_title': 'روابط قانونية',
          'legal_body':
              'شروط الخدمة وسياسة الخصوصية متاحتان عبر الروابط الرسمية ويتم تحديثهما خارج التطبيق.',
          'terms_title': 'شروط الخدمة',
          'terms_body': 'افتح أحدث نسخة من شروط الخدمة.',
          'privacy_title': 'سياسة الخصوصية',
          'privacy_body': 'افتح أحدث نسخة من سياسة الخصوصية.',
          'open_link': 'افتح الرابط',
          'contact_title': 'تواصل معنا',
          'developer': 'تم التطوير بواسطة فريق Hiro',
          'contact': 'support@hiro-services.com',
          'contact_hint':
              'للاستفسارات أو الدعم أو الإبلاغ عن مشكلة أو مسألة قانونية، اختر طريقة التواصل المناسبة لك.',
          'email_action': 'البريد',
          'whatsapp_action': 'WhatsApp',
          'app_chat_action': 'دردشة التطبيق',
          'whatsapp_number': '0542978614',
          'link_failed': 'تعذر فتح الرابط حاليًا.',
          'email_failed': 'تعذر فتح تطبيق البريد الإلكتروني.',
          'whatsapp_failed': 'تعذر فتح WhatsApp حاليًا.',
        };
      case 'am':
        return {
          'title': 'ስለ እኛ',
          'app_name': 'Hiro',
          'version': 'ስሪት 1.0.0',
          'tagline':
              'ደንበኞችን ከባለሙያዎች፣ ቻቶች፣ የስራ ጥያቄዎች እና የአስተዳደር መሳሪያዎች ጋር በአንድ ቦታ የሚያገናኝ መተግበሪያ።',
          'intro_title': 'Hiro ምንድን ነው?',
          'intro_body':
              'Hiro ባለሙያዎችን ለማግኘት፣ የስራ ጥያቄዎችን ለመላክ፣ ውይይቶችን ለማስተዳደር፣ ምላሾችን ለመከታተል እና እንደ ደረሰኞች፣ ፖስቶች እና የንግድ ፕሮፋይል ያሉ መሳሪያዎችን ለመጠቀም የሚረዳ ፕላትፎርም ነው።',
          'highlights_title': 'በመተግበሪያው ውስጥ ያለው',
          'highlight_match_title': 'ባለሙያ ማግኘት',
          'highlight_match_body':
              'ተስማሚውን ሰው በፍጥነት ለማግኘት በሙያ፣ በአካባቢ፣ በንግድ ፕሮፋይል እና በተገኝነት ፈልግ።',
          'highlight_request_title': 'የስራ ጥያቄዎች እና ቻት',
          'highlight_request_body':
              'ጥያቄዎችን ላክ፣ በቻት፣ በፎቶዎች፣ በፋይሎች እና በሁኔታ ዝማኔዎች ከተግባር ጋር ቀጥል።',
          'highlight_community_title': 'ማህበረሰብ እና ፖስቶች',
          'highlight_community_body':
              'ፖስት አድርግ፣ እውቀት አጋራ፣ ምላሾችን ተቀበል እና ከማህበረሰቡ ጋር ተገናኝ።',
          'highlight_pro_title': 'ለባለሙያዎች መሳሪያዎች',
          'highlight_pro_body':
              'ንቁ ምዝገባ እንደ ደረሰኞች፣ ለጥያቄዎች ምላሽ መስጠት እና የተሻለ ሙያዊ እይታ ያሉ Pro መሳሪያዎችን ይከፍታል።',
          'trust_title': 'ሰዎች Hiro ለምን ይጠቀማሉ',
          'trust_1': 'ጥያቄዎችን፣ ምላሾችን እና ውይይቶችን በተደራጀ መልኩ ለማስተዳደር።',
          'trust_2': 'ተስማሚ ባለሙያዎችን ከእጅ ፍለጋ ይልቅ በፍጥነት ለማግኘት።',
          'trust_3': 'ፕሮፋይሎችን፣ ሁኔታዎችን እና መልዕክቶችን በግልጽ መልኩ ለመከታተል።',
          'trust_4': 'ልምዱ ለደንበኞችም ለባለሙያዎችም እንዲሰራ ስለሚያደርግ።',
          'legal_title': 'ህጋዊ አገናኞች',
          'legal_body':
              'የአገልግሎት ውሎች እና የግላዊነት ፖሊሲ በኦፊሴላዊ አገናኞች ይገኛሉ እና ከመተግበሪያው ውጭ ይዘምናሉ።',
          'terms_title': 'የአገልግሎት ውል',
          'terms_body': 'የቅርብ ጊዜውን የአገልግሎት ውል ክፈት።',
          'privacy_title': 'የግላዊነት ፖሊሲ',
          'privacy_body': 'የቅርብ ጊዜውን የግላዊነት ፖሊሲ ክፈት።',
          'open_link': 'አገናኝ ክፈት',
          'contact_title': 'አግኙን',
          'developer': 'በ Hiro ቡድን የተገነባ',
          'contact': 'support@hiro-services.com',
          'contact_hint':
              'ለጥያቄ፣ ለድጋፍ፣ ለችግር ሪፖርት ወይም ለህጋዊ ጥያቄ የሚመችዎትን የመገናኛ መንገድ ይምረጡ።',
          'email_action': 'ኢሜይል',
          'whatsapp_action': 'WhatsApp',
          'app_chat_action': 'የመተግበሪያ ቻት',
          'whatsapp_number': '0542978614',
          'link_failed': 'አገናኙን አሁን መክፈት አልተቻለም።',
          'email_failed': 'የኢሜይል መተግበሪያውን መክፈት አልተቻለም።',
          'whatsapp_failed': 'WhatsAppን አሁን መክፈት አልተቻለም።',
        };
      default:
        return {
          'title': 'About',
          'app_name': 'Hiro',
          'version': 'Version 1.0.0',
          'tagline':
              'Connecting clients with professionals, chat, job requests, and management tools in one place.',
          'intro_title': 'What is Hiro?',
          'intro_body':
              'Hiro is a platform for finding professionals, sending job requests, managing conversations, tracking responses, and using tools like invoices, posts, and business profiles.',
          'highlights_title': 'What You Can Do',
          'highlight_match_title': 'Find the right professional',
          'highlight_match_body':
              'Search by profession, area, business profile, and availability to reach the right match faster.',
          'highlight_request_title': 'Handle requests and chat',
          'highlight_request_body':
              'Send requests, continue in chat, and keep photos, files, and status updates in one flow.',
          'highlight_community_title': 'Use posts and community',
          'highlight_community_body':
              'Share posts, learn from the feed, and stay connected to the community around your services.',
          'highlight_pro_title': 'Unlock professional tools',
          'highlight_pro_body':
              'An active subscription unlocks Pro tools like invoices, request replies, and stronger business visibility.',
          'trust_title': 'Why People Use Hiro',
          'trust_1':
              'To manage requests, replies, and conversations in one organized place.',
          'trust_2':
              'To find relevant professionals faster with less manual searching.',
          'trust_3':
              'To track profiles, statuses, and messages with more clarity.',
          'trust_4':
              'Because the experience supports both customers and professionals.',
          'legal_title': 'Legal Links',
          'legal_body':
              'Terms of Service and Privacy Policy are available through the official links and stay updated outside the app.',
          'terms_title': 'Terms of Service',
          'terms_body': 'Open the latest Terms of Service.',
          'privacy_title': 'Privacy Policy',
          'privacy_body': 'Open the latest Privacy Policy.',
          'open_link': 'Open link',
          'contact_title': 'Contact',
          'developer': 'Developed by the Hiro Team',
          'contact': 'support@hiro-services.com',
          'contact_hint':
              'For questions, support, issue reports, or legal requests, choose the contact method that works best for you.',
          'email_action': 'Email',
          'whatsapp_action': 'WhatsApp',
          'app_chat_action': 'App chat',
          'whatsapp_number': '0542978614',
          'link_failed': 'Could not open the link right now.',
          'email_failed': 'Could not open your email app.',
          'whatsapp_failed': 'Could not open WhatsApp right now.',
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
                  _buildAnimatedSection(delay: 0, child: _buildHero(strings)),
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
                    child: _buildTrustCard(strings),
                  ),
                  const SizedBox(height: 20),
                  _buildAnimatedSection(
                    delay: 480,
                    child: _buildLegalLinksCard(strings),
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

  Widget _buildAnimatedSection({required Widget child, required int delay}) {
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
        strings['highlight_community_title']!,
        strings['highlight_community_body']!,
        Icons.forum_outlined,
        const Color(0xFFFEF3C7),
        const Color(0xFFB45309),
      ),
      (
        strings['highlight_pro_title']!,
        strings['highlight_pro_body']!,
        Icons.rocket_launch_outlined,
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

  Widget _buildTrustCard(Map<String, String> strings) {
    final items = [
      strings['trust_1']!,
      strings['trust_2']!,
      strings['trust_3']!,
      strings['trust_4']!,
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.favorite_outline_rounded,
                  color: Color(0xFF7DD3FC),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings['trust_title']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF7DD3FC),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalLinksCard(Map<String, String> strings) {
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
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.policy_rounded,
                  color: Color(0xFF1D4ED8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings['legal_title']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            strings['legal_body']!,
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 16),
          _buildLegalLinkTile(
            title: strings['terms_title']!,
            body: strings['terms_body']!,
            accent: const Color(0xFF0F766E),
            icon: Icons.gavel_rounded,
            actionLabel: strings['open_link']!,
            onTap: () => _openExternalLink(
              AppConstants.termsOfServiceUrl,
              strings['link_failed']!,
            ),
          ),
          const SizedBox(height: 12),
          _buildLegalLinkTile(
            title: strings['privacy_title']!,
            body: strings['privacy_body']!,
            accent: const Color(0xFF1D4ED8),
            icon: Icons.verified_user_outlined,
            actionLabel: strings['open_link']!,
            onTap: () => _openExternalLink(
              AppConstants.privacyPolicyUrl,
              strings['link_failed']!,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalLinkTile({
    required String title,
    required String body,
    required Color accent,
    required IconData icon,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      actionLabel,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF172554), Color(0xFF0C4A6E)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                strings['contact_title']!,
                style: const TextStyle(
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
              color: Color(0xFFBAE6FD),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings['contact_hint']!,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildContactDetail(Icons.email_outlined, strings['contact']!),
              _buildContactDetail(
                Icons.chat_rounded,
                strings['whatsapp_number']!,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildContactAction(
                label: strings['email_action']!,
                icon: Icons.email_outlined,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F5CC0),
                onTap: () => _openEmail(strings['email_failed']!),
              ),
              _buildContactAction(
                label: strings['whatsapp_action']!,
                icon: Icons.chat_rounded,
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                onTap: () => _openWhatsApp(strings['whatsapp_failed']!),
              ),
              _buildContactAction(
                label: strings['app_chat_action']!,
                icon: Icons.support_agent_rounded,
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                onTap: _openAppChat,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactDetail(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF7DD3FC), size: 16),
          const SizedBox(width: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactAction({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Material(
              color: backgroundColor,
              elevation: 3,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Icon(icon, color: foregroundColor, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalLink(String url, String failureMessage) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _openEmail(String failureMessage) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.contactEmail,
      queryParameters: {'subject': 'Hiro Support'},
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _openWhatsApp(String failureMessage) async {
    final ok = await launchUrl(
      Uri.parse('https://wa.me/972542978614'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _openAppChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HelpPage(openSupportChatOnLoad: true),
      ),
    );
  }
}
