import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/services/language_provider.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isOpeningSupportChat = false;

  Map<String, String> _strings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'עזרה',
          'hero_title': 'מרכז העזרה של Hiro',
          'hero_subtitle':
              'כאן תמצאו הדרכה על בקשות עבודה, צ׳אט עם בעלי מקצוע, פרופיל העסק, מנויים, קהילה וכלים נוספים באפליקציה.',
          'hero_badge': 'תמיכה והכוונה',
          'contact_admin': 'צור קשר עם מנהל',
          'contact_admin_loading': 'פותח צ׳אט...',
          'contact_admin_hint':
              'אם יש תקלה, שאלה על חשבון, בעיה בבקשת עבודה או צורך בבדיקה ידנית, נפתח לך צ׳אט עם אחד המנהלים.',
          'chat_title': 'תמיכה ישירה בצ׳אט',
          'chat_body':
              'לחיצה על הכפתור תפתח שיחה עם אחד המנהלים הזמינים, כדי שתוכל לקבל מענה אישי בתוך האפליקציה.',
          'quick_title': 'במה אפשר לעזור',
          'quick_requests_title': 'בקשות עבודה',
          'quick_requests_body':
              'פרסום בקשה, בחירת מקצוע, מעקב אחרי סטטוס ותגובות מבעלי מקצוע.',
          'quick_chat_title': 'צ׳אט והודעות',
          'quick_chat_body':
              'פתיחת שיחה עם בעל מקצוע, מעקב אחרי תשובות, קבצים, תמונות והמשך טיפול.',
          'quick_profile_title': 'פרופיל ואימות',
          'quick_profile_body':
              'עדכון פרטים, מקצועות, שעות פעילות, אימות עסק ותצוגת הפרופיל שלך.',
          'quick_subscription_title': 'מנוי וכלים בתשלום',
          'quick_subscription_body':
              'מידע על מנוי פעיל, גישה לחשבוניות, תגובה לבקשות עבודה וכלי פרימיום.',
          'quick_blog_title': 'פוסטים וקהילה',
          'quick_blog_body':
              'שיתוף פוסט, הוספת מדיה, בחירת מקצוע בפוסט וחיפוש מידע מהקהילה.',
          'faq_title': 'שאלות נפוצות',
          'faq_1_q': 'איך מפרסמים בקשת עבודה טובה?',
          'faq_1_a':
              'כתבו כותרת ברורה, תיאור קצר, הוסיפו מיקום ותמונות אם צריך, ובחרו את המקצוע המתאים כדי שבעלי מקצוע רלוונטיים יוכלו להגיב.',
          'faq_2_q': 'איך פותחים שיחה עם בעל מקצוע?',
          'faq_2_a':
              'אפשר לפתוח צ׳אט מתוך הפרופיל של בעל המקצוע, מתוך בקשת עבודה או מתוך ההודעות. כל התמונות והקבצים יישמרו באותה שיחה.',
          'faq_3_q': 'מה נותן מנוי פעיל לבעלי מקצוע?',
          'faq_3_a':
              'מנוי פעיל מאפשר גישה לכלי עבודה מתקדמים כמו תגובה לבקשות, יצירת חשבוניות, נראות מוגברת וגישה לפיצ׳רים מקצועיים נוספים.',
          'faq_4_q': 'מה עושים אם צ׳אט, פוסט או בקשה לא עובדים כמו שצריך?',
          'faq_4_a':
              'פנו דרך כפתור יצירת הקשר כאן בעמוד, ציינו באיזה מסך זה קרה ומה ניסיתם לעשות, ואחד המנהלים יוכל להמשיך מולכם בצ׳אט.',
          'faq_5_q': 'איך משפרים את הסיכוי לקבל תגובות?',
          'faq_5_a':
              'פרטים מדויקים, תמונות טובות, בחירת מקצוע נכונה ותיאור מסודר עוזרים לבעלי מקצוע להבין מהר יותר מה אתם צריכים.',
          'tips_title': 'לפני שפונים לתמיכה',
          'tips_1': 'כתבו מה ניסיתם לעשות ומה קרה בפועל.',
          'tips_2':
              'ציינו אם הבעיה קשורה לבקשה, לצ׳אט, למנוי, לפרופיל או לפוסט.',
          'tips_3': 'אם אפשר, ציינו את שם בעל המקצוע או מספר הבקשה/הדיווח.',
          'tips_4': 'צילום מסך או תיאור מדויק של השלב חוסכים זמן בטיפול.',
          'support_areas_title': 'הצוות יכול לעזור גם עם',
          'support_area_1': 'פתיחת ובדיקת שיחות צ׳אט',
          'support_area_2': 'בדיקת בקשות עבודה ותגובות',
          'support_area_3': 'מנויים, חשבוניות וכלי Pro',
          'support_area_4': 'פרופיל, מקצועות, אימות והגדרות',
          'guest_required': 'צריך להתחבר כדי לפתוח צ׳אט עם מנהל התמיכה.',
          'no_admins': 'לא נמצא כרגע מנהל זמין לצ׳אט.',
          'chat_open_failed': 'לא הצלחנו לפתוח את צ׳אט התמיכה כרגע.',
        };
      case 'ar':
        return {
          'title': 'المساعدة',
          'hero_title': 'مركز مساعدة Hiro',
          'hero_subtitle':
              'ستجد هنا إرشادات حول طلبات العمل، الدردشة مع أصحاب المهن، الملف الشخصي، الاشتراك، المجتمع والأدوات الأخرى داخل التطبيق.',
          'hero_badge': 'الدعم والإرشاد',
          'contact_admin': 'تواصل مع مشرف',
          'contact_admin_loading': 'يتم فتح الدردشة...',
          'contact_admin_hint':
              'إذا كانت لديك مشكلة أو سؤال عن الحساب أو الطلبات أو تحتاج إلى فحص يدوي، سنفتح لك دردشة مع أحد المشرفين.',
          'chat_title': 'دعم مباشر عبر الدردشة',
          'chat_body':
              'الضغط على الزر يفتح محادثة مع أحد المشرفين المتاحين لكي تحصل على مساعدة شخصية داخل التطبيق.',
          'quick_title': 'كيف يمكننا المساعدة',
          'quick_requests_title': 'طلبات العمل',
          'quick_requests_body':
              'نشر طلب، اختيار المهنة، متابعة الحالة وردود أصحاب المهن.',
          'quick_chat_title': 'الدردشة والرسائل',
          'quick_chat_body':
              'بدء محادثة مع صاحب مهنة، متابعة الردود والملفات والصور ومواصلة المتابعة.',
          'quick_profile_title': 'الملف الشخصي والتحقق',
          'quick_profile_body':
              'تحديث البيانات والمهن وساعات العمل والتحقق من النشاط وعرض الملف الشخصي.',
          'quick_subscription_title': 'الاشتراك والأدوات المدفوعة',
          'quick_subscription_body':
              'فهم حالة الاشتراك والوصول إلى الفواتير والرد على الطلبات والأدوات الاحترافية.',
          'quick_blog_title': 'المنشورات والمجتمع',
          'quick_blog_body':
              'مشاركة منشور، إضافة وسائط، اختيار مهنة للمنشور والعثور على معلومات من المجتمع.',
          'faq_title': 'الأسئلة الشائعة',
          'faq_1_q': 'كيف أنشر طلب عمل جيد؟',
          'faq_1_a':
              'اكتب عنوانًا واضحًا ووصفًا مختصرًا، وأضف الموقع والصور عند الحاجة، واختر المهنة المناسبة حتى يتمكن أصحاب المهن المناسبون من الرد.',
          'faq_2_q': 'كيف أفتح محادثة مع صاحب مهنة؟',
          'faq_2_a':
              'يمكنك فتح الدردشة من الملف الشخصي لصاحب المهنة أو من طلب العمل أو من صفحة الرسائل. سيتم حفظ الصور والملفات في نفس المحادثة.',
          'faq_3_q': 'ماذا يمنح الاشتراك النشط لأصحاب المهن؟',
          'faq_3_a':
              'الاشتراك النشط يفتح أدوات متقدمة مثل الرد على الطلبات وإنشاء الفواتير وظهورًا أفضل والوصول إلى مزايا احترافية إضافية.',
          'faq_4_q':
              'ماذا أفعل إذا كانت الدردشة أو المنشور أو الطلب لا يعمل جيدًا؟',
          'faq_4_a':
              'استخدم زر التواصل في هذه الصفحة، واذكر الشاشة التي حدثت فيها المشكلة وما الذي حاولت القيام به، وسيتابع معك أحد المشرفين عبر الدردشة.',
          'faq_5_q': 'كيف أحسّن فرص الحصول على ردود؟',
          'faq_5_a':
              'البيانات الدقيقة والصور الجيدة واختيار المهنة الصحيحة والوصف الواضح تساعد أصحاب المهن على فهم طلبك بسرعة أكبر.',
          'tips_title': 'قبل التواصل مع الدعم',
          'tips_1': 'اكتب ما الذي حاولت القيام به وماذا حدث فعليًا.',
          'tips_2':
              'اذكر إن كانت المشكلة تتعلق بالطلب أو الدردشة أو الاشتراك أو الملف الشخصي أو المنشور.',
          'tips_3': 'إذا أمكن، اذكر اسم صاحب المهنة أو رقم الطلب/البلاغ.',
          'tips_4': 'لقطة شاشة أو وصف دقيق للخطوة يوفر وقتًا أثناء المعالجة.',
          'support_areas_title': 'يمكن للفريق المساعدة أيضًا في',
          'support_area_1': 'فتح وفحص محادثات الدردشة',
          'support_area_2': 'مراجعة طلبات العمل والردود',
          'support_area_3': 'الاشتراكات والفواتير وأدوات Pro',
          'support_area_4': 'الملف الشخصي والمهن والتحقق والإعدادات',
          'guest_required': 'يجب تسجيل الدخول لفتح دردشة مع مشرف الدعم.',
          'no_admins': 'لا يوجد مشرف متاح للدردشة الآن.',
          'chat_open_failed': 'تعذر فتح دردشة الدعم حاليًا.',
        };
      default:
        return {
          'title': 'Help',
          'hero_title': 'Hiro Help Center',
          'hero_subtitle':
              'Get guidance for job requests, chat with professionals, your business profile, subscriptions, community posts, and the rest of the app tools.',
          'hero_badge': 'Support and Guidance',
          'contact_admin': 'Contact an admin',
          'contact_admin_loading': 'Opening chat...',
          'contact_admin_hint':
              'If you hit a bug, need account help, have a request issue, or want manual review, we will open a chat with one of the admins.',
          'chat_title': 'Direct support in chat',
          'chat_body':
              'Tap the button to open a conversation with one of the available admins so you can get personal help inside the app.',
          'quick_title': 'What we can help with',
          'quick_requests_title': 'Job requests',
          'quick_requests_body':
              'Publish a request, choose a profession, track status changes, and follow professional replies.',
          'quick_chat_title': 'Chat and messages',
          'quick_chat_body':
              'Start a conversation with a professional, follow replies, and keep files, photos, and updates in one place.',
          'quick_profile_title': 'Profile and verification',
          'quick_profile_body':
              'Update your details, professions, working hours, business verification, and public profile.',
          'quick_subscription_title': 'Subscription and paid tools',
          'quick_subscription_body':
              'Check your subscription, access invoices, reply to requests, and use Pro features.',
          'quick_blog_title': 'Posts and community',
          'quick_blog_body':
              'Share a post, attach media, choose a profession for the post, and learn from the community feed.',
          'faq_title': 'Frequently Asked Questions',
          'faq_1_q': 'How do I post a good job request?',
          'faq_1_a':
              'Use a clear title, short description, add location and photos when needed, and choose the right profession so relevant professionals can respond.',
          'faq_2_q': 'How do I open a chat with a professional?',
          'faq_2_a':
              'You can start a chat from the professional profile, a request flow, or the messages tab. Photos and files stay in the same conversation.',
          'faq_3_q':
              'What does an active subscription unlock for professionals?',
          'faq_3_a':
              'An active subscription unlocks advanced tools like replying to requests, creating invoices, stronger visibility, and other professional features.',
          'faq_4_q':
              'What if chat, a post, or a request is not working correctly?',
          'faq_4_a':
              'Use the contact button on this page, mention which screen failed and what you were trying to do, and an admin can continue with you in chat.',
          'faq_5_q': 'How can I improve my chances of getting replies?',
          'faq_5_a':
              'Accurate details, good photos, the right profession, and a structured description help professionals understand your need faster.',
          'tips_title': 'Before Contacting Support',
          'tips_1': 'Write what you tried to do and what happened instead.',
          'tips_2':
              'Mention whether the issue is about a request, chat, subscription, profile, or post.',
          'tips_3':
              'If possible, include the professional name or the request/report number.',
          'tips_4': 'A screenshot or a precise step description can save time.',
          'support_areas_title': 'The team can also help with',
          'support_area_1': 'Opening and checking chat conversations',
          'support_area_2': 'Reviewing job requests and replies',
          'support_area_3': 'Subscriptions, invoices, and Pro tools',
          'support_area_4': 'Profile, professions, verification, and settings',
          'guest_required': 'Please sign in to open a support chat.',
          'no_admins': 'No admin is available for chat right now.',
          'chat_open_failed': 'Could not open support chat right now.',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final isRtl = localeCode == 'he' || localeCode == 'ar';

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
              colors: [Color(0xFFEAF4FF), Color(0xFFF6F8FC), Color(0xFFFFFFFF)],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                _buildHero(strings, context),
                const SizedBox(height: 18),
                _buildQuickTopics(strings),
                const SizedBox(height: 18),
                _buildSupportAreasCard(strings),
                const SizedBox(height: 18),
                _buildSectionTitle(strings['faq_title']!),
                const SizedBox(height: 10),
                _buildFaqCard(
                  strings['faq_1_q']!,
                  strings['faq_1_a']!,
                  Icons.post_add_rounded,
                  isRtl,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_2_q']!,
                  strings['faq_2_a']!,
                  Icons.chat_bubble_outline_rounded,
                  isRtl,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_3_q']!,
                  strings['faq_3_a']!,
                  Icons.workspace_premium_outlined,
                  isRtl,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_4_q']!,
                  strings['faq_4_a']!,
                  Icons.support_outlined,
                  isRtl,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_5_q']!,
                  strings['faq_5_a']!,
                  Icons.tips_and_updates_outlined,
                  isRtl,
                ),
                const SizedBox(height: 18),
                _buildTipsCard(strings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(Map<String, String> strings, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F5CC0), Color(0xFF1976D2), Color(0xFF4FC3F7)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x221976D2),
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  strings['hero_badge']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            strings['hero_title']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings['hero_subtitle']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings['chat_title']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  strings['chat_body']!,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isOpeningSupportChat
                        ? null
                        : () => _openSupportChat(strings),
                    icon: _isOpeningSupportChat
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF0F5CC0),
                            ),
                          )
                        : const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(
                      _isOpeningSupportChat
                          ? strings['contact_admin_loading']!
                          : strings['contact_admin']!,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F5CC0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  strings['contact_admin_hint']!,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTopics(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(strings['quick_title']!),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_requests_title']!,
          body: strings['quick_requests_body']!,
          icon: Icons.work_history_outlined,
          accent: const Color(0xFF1D4ED8),
          tint: const Color(0xFFDBEAFE),
        ),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_chat_title']!,
          body: strings['quick_chat_body']!,
          icon: Icons.chat_bubble_outline_rounded,
          accent: const Color(0xFF0F766E),
          tint: const Color(0xFFD1FAE5),
        ),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_profile_title']!,
          body: strings['quick_profile_body']!,
          icon: Icons.verified_user_outlined,
          accent: const Color(0xFF7C3AED),
          tint: const Color(0xFFEDE9FE),
        ),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_subscription_title']!,
          body: strings['quick_subscription_body']!,
          icon: Icons.credit_card_rounded,
          accent: const Color(0xFFBE185D),
          tint: const Color(0xFFFCE7F3),
        ),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_blog_title']!,
          body: strings['quick_blog_body']!,
          icon: Icons.forum_outlined,
          accent: const Color(0xFFB45309),
          tint: const Color(0xFFFEF3C7),
        ),
      ],
    );
  }

  Widget _buildQuickTopicCard({
    required String title,
    required String body,
    required IconData icon,
    required Color accent,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              color: tint,
              borderRadius: BorderRadius.circular(16),
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
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildSupportAreasCard(Map<String, String> strings) {
    final items = [
      strings['support_area_1']!,
      strings['support_area_2']!,
      strings['support_area_3']!,
      strings['support_area_4']!,
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings['support_areas_title']!,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
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
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF475569),
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

  Widget _buildFaqCard(
    String question,
    String answer,
    IconData icon,
    bool isRtl,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: const Color(0xFF1976D2),
        collapsedIconColor: const Color(0xFF64748B),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF1976D2), size: 20),
        ),
        title: Text(
          question,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        children: [
          Align(
            alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(color: Color(0xFF475569), height: 1.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard(Map<String, String> strings) {
    final tips = [
      strings['tips_1']!,
      strings['tips_2']!,
      strings['tips_3']!,
      strings['tips_4']!,
    ];

    return Container(
      padding: const EdgeInsets.all(18),
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
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.tips_and_updates_outlined,
                  color: Color(0xFF7DD3FC),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings['tips_title']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...tips.map(
            (tip) => Padding(
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
                      tip,
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

  Future<void> _openSupportChat(Map<String, String> strings) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      _showSnackBar(strings['guest_required']!);
      return;
    }

    setState(() => _isOpeningSupportChat = true);

    try {
      final admin = await _pickRandomAdmin(currentUser.uid);
      if (!mounted) return;

      if (admin == null) {
        _showSnackBar(strings['no_admins']!);
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            receiverId: admin.id,
            receiverName: _adminDisplayName(admin.data()),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to open support chat: $e');
      if (mounted) {
        _showSnackBar(strings['chat_open_failed']!);
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningSupportChat = false);
      }
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _pickRandomAdmin(
    String currentUserId,
  ) async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    final docs = snapshot.docs;
    if (docs.isEmpty) return null;

    final otherAdmins = docs.where((doc) => doc.id != currentUserId).toList();
    final candidates = otherAdmins.isNotEmpty ? otherAdmins : docs;
    if (candidates.isEmpty) return null;

    return candidates[Random().nextInt(candidates.length)];
  }

  String _adminDisplayName(Map<String, dynamic>? data) {
    if (data == null) return 'Admin';
    final name = (data['name'] ?? data['displayName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final phone = (data['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'Admin';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
