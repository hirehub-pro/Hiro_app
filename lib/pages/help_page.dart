import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/support_bot_page.dart';
import 'package:untitled1/services/language_provider.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Map<String, String> _strings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'עזרה',
          'hero_title': 'איך אפשר לעזור לך היום?',
          'hero_subtitle':
              'מצא תשובות מהר, פתח צ\'אט תמיכה וקבל הכוונה ברורה בנושאי חשבון, בקשות ותשלומים.',
          'hero_badge': 'מרכז תמיכה',
          'chat_title': 'צ\'אט תמיכה',
          'chat_body':
              'דבר עם עוזר התמיכה של Hiro וקבל תשובות מהירות בנושאי חשבון, בקשות עבודה, מעקב ותשלומים.',
          'open_chat': 'פתח תמיכה',
          'faq_title': 'שאלות נפוצות',
          'quick_title': 'פעולות מהירות',
          'quick_requests_title': 'בקשות עבודה',
          'quick_requests_body': 'עקוב אחרי בקשות, סטטוסים ותגובות של בעלי מקצוע.',
          'quick_account_title': 'חשבון ופרופיל',
          'quick_account_body': 'עדכון פרטים, תמונה, טלפון והגדרות חשבון.',
          'quick_payments_title': 'תשלומים ומנויים',
          'quick_payments_body': 'הבנה של רכישות, מנוי וגישה לכלים בתשלום.',
          'faq_1_q': 'איך מוצאים בעל מקצוע?',
          'faq_1_a':
              'חפש לפי תחום, מיקום או קטגוריה, היכנס לפרופיל המתאים ושלח בקשת עבודה או בקשת הצעת מחיר.',
          'faq_2_q': 'איך עוקבים אחרי בקשה?',
          'faq_2_a':
              'אפשר לעקוב דרך ההתראות, עמוד הבקשות והצ\'אט עם בעל המקצוע. כל שינוי סטטוס מופיע שם.',
          'faq_3_q': 'איך משנים פרטי חשבון?',
          'faq_3_a':
              'דרך הגדרות החשבון אפשר לעדכן פרטים אישיים, טלפון, תמונת פרופיל והעדפות נוספות.',
          'faq_4_q': 'מה עושים אם יש בעיה?',
          'faq_4_a':
              'פתח את צ\'אט התמיכה ותאר בקצרה מה קרה, באיזה עמוד זה קרה ומה ציפית שיקרה.',
          'tips_title': 'לפני שפונים לתמיכה',
          'tips_1': 'כתוב תיאור קצר וברור של הבעיה.',
          'tips_2': 'אם אפשר, ציין באיזה מסך או שלב זה קרה.',
          'tips_3': 'בבקשות עבודה, תמונות טובות עוזרות לקבל תשובות מדויקות יותר.',
        };
      case 'ar':
        return {
          'title': 'المساعدة',
          'hero_title': 'كيف يمكننا مساعدتك اليوم؟',
          'hero_subtitle':
              'اعثر على الإجابات بسرعة، وافتح دردشة الدعم، واحصل على إرشاد واضح بخصوص الحساب والطلبات والمدفوعات.',
          'hero_badge': 'مركز الدعم',
          'chat_title': 'دردشة الدعم',
          'chat_body':
              'تحدث مع مساعد Hiro للحصول على مساعدة سريعة حول الحساب وطلبات العمل والمتابعة والمدفوعات.',
          'open_chat': 'فتح الدعم',
          'faq_title': 'الأسئلة الشائعة',
          'quick_title': 'إجراءات سريعة',
          'quick_requests_title': 'طلبات العمل',
          'quick_requests_body': 'تابع الطلبات والحالات وردود أصحاب المهن.',
          'quick_account_title': 'الحساب والملف الشخصي',
          'quick_account_body': 'تحديث البيانات والصورة والهاتف وإعدادات الحساب.',
          'quick_payments_title': 'المدفوعات والاشتراك',
          'quick_payments_body': 'فهم المشتريات والاشتراك والوصول إلى الأدوات المدفوعة.',
          'faq_1_q': 'كيف أجد محترفاً؟',
          'faq_1_a':
              'ابحث حسب المجال أو الموقع أو الفئة، ثم افتح الملف الشخصي المناسب وأرسل طلب عمل أو طلب عرض سعر.',
          'faq_2_q': 'كيف أتابع الطلب؟',
          'faq_2_a':
              'يمكنك المتابعة من خلال الإشعارات وصفحة الطلبات والدردشة مع المهني. أي تغيير في الحالة سيظهر هناك.',
          'faq_3_q': 'كيف أغير بيانات الحساب؟',
          'faq_3_a':
              'من إعدادات الحساب يمكنك تحديث البيانات الشخصية والهاتف والصورة الشخصية وتفضيلات أخرى.',
          'faq_4_q': 'ماذا أفعل إذا كانت هناك مشكلة؟',
          'faq_4_a':
              'افتح دردشة الدعم واشرح باختصار ما الذي حدث، وفي أي صفحة حدث، وما الذي كنت تتوقعه.',
          'tips_title': 'قبل التواصل مع الدعم',
          'tips_1': 'اكتب وصفاً قصيراً وواضحاً للمشكلة.',
          'tips_2': 'إذا أمكن، اذكر الشاشة أو الخطوة التي حدثت فيها المشكلة.',
          'tips_3': 'في طلبات العمل، تساعد الصور الجيدة في الحصول على ردود أدق.',
        };
      default:
        return {
          'title': 'Help',
          'hero_title': 'How can we help today?',
          'hero_subtitle':
              'Find answers quickly, open support chat, and get clear guidance for account, requests, and payments.',
          'hero_badge': 'Support Hub',
          'chat_title': 'Support Chat',
          'chat_body':
              'Talk to the Hiro support assistant for quick help with your account, work requests, tracking, and payments.',
          'open_chat': 'Open Support',
          'faq_title': 'Frequently Asked Questions',
          'quick_title': 'Quick Topics',
          'quick_requests_title': 'Job requests',
          'quick_requests_body':
              'Track requests, statuses, and professional responses.',
          'quick_account_title': 'Account and profile',
          'quick_account_body':
              'Update details, profile photo, phone number, and settings.',
          'quick_payments_title': 'Payments and subscription',
          'quick_payments_body':
              'Understand purchases, subscription state, and access to paid tools.',
          'faq_1_q': 'How do I find a professional?',
          'faq_1_a':
              'Search by service, category, or location, then open the right profile and send a work request or quote request.',
          'faq_2_q': 'How do I track a request?',
          'faq_2_a':
              'You can follow updates from notifications, the requests page, and your chat with the professional.',
          'faq_3_q': 'How do I update account details?',
          'faq_3_a':
              'Open account settings to update personal details, phone number, profile photo, and other preferences.',
          'faq_4_q': 'What should I do if something goes wrong?',
          'faq_4_a':
              'Open support chat and briefly explain what happened, where it happened, and what you expected instead.',
          'tips_title': 'Before Contacting Support',
          'tips_1': 'Write a short and clear description of the issue.',
          'tips_2': 'If possible, mention which screen or step caused the problem.',
          'tips_3':
              'For job requests, clear photos usually lead to better responses.',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final localeCode = Provider.of<LanguageProvider>(context).locale.languageCode;
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
                _buildSectionTitle(strings['faq_title']!),
                const SizedBox(height: 10),
                _buildFaqCard(
                  strings['faq_1_q']!,
                  strings['faq_1_a']!,
                  Icons.search_rounded,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_2_q']!,
                  strings['faq_2_a']!,
                  Icons.notifications_active_outlined,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_3_q']!,
                  strings['faq_3_a']!,
                  Icons.manage_accounts_outlined,
                ),
                const SizedBox(height: 12),
                _buildFaqCard(
                  strings['faq_4_q']!,
                  strings['faq_4_a']!,
                  Icons.support_outlined,
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
            child: Row(
              children: [
                Expanded(
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
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportBotPage()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1976D2),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(
              strings['open_chat']!,
              style: const TextStyle(fontWeight: FontWeight.w800),
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
          title: strings['quick_account_title']!,
          body: strings['quick_account_body']!,
          icon: Icons.manage_accounts_outlined,
          accent: const Color(0xFF0F766E),
          tint: const Color(0xFFD1FAE5),
        ),
        const SizedBox(height: 10),
        _buildQuickTopicCard(
          title: strings['quick_payments_title']!,
          body: strings['quick_payments_body']!,
          icon: Icons.credit_card_rounded,
          accent: const Color(0xFFBE185D),
          tint: const Color(0xFFFCE7F3),
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

  Widget _buildFaqCard(String question, String answer, IconData icon) {
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
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                color: Color(0xFF475569),
                height: 1.65,
              ),
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
}
