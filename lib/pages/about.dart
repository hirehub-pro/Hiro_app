import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'אודות ומשפטי',
          'app_name': 'hiro',
          'version': 'גרסה 1.0.0',
          'terms_title': 'תנאי שימוש',
          'privacy_title': 'מדיניות פרטיות',
          'terms_content': 'ברוכים הבאים ל-הירו. בשימוש באפליקציה, הנך מסכים לתנאים הבאים:\n1. hiro היא פלטפורמת תיווך בלבד.\n2. האחראיות על איכות העבודה והתשלום היא בין הלקוח לבעל המקצוע.\n3. חל איסור על פרסום תוכן פוגעני או כוזב.\n4. המערכת רשאית להשעות משתמשים המפרים את הכללים.',
          'privacy_content': 'הפרטיות שלך חשובה לנו:\n1. אנו אוספים מידע בסיסי (שם, טלפון, עיר) כדי לאפשר את פעילות השירות.\n2. מיקום המכשיר משמש למציאת בעלי מקצוע קרובים אליך.\n3. המידע שלך אינו מועבר לצד ג\' למטרות פרסום.\n4. ניתן לבקש את מחיקת החשבון והמידע בכל עת דרך ההגדרות.',
          'developer': 'פותח על ידי צוות הירו',
          'contact': 'צור קשר: support@hiro.com',
        };
      case 'ar':
        return {
          'title': 'حول والقانونية',
          'app_name': 'هايرو',
          'version': 'الإصدار 1.0.0',
          'terms_title': 'شروط الخدمة',
          'privacy_title': 'سياسة الخصوصية',
          'terms_content': 'مرحباً بكم في هايرو. باستخدام التطبيق، فإنك توافق على الشروط التالية:\n1. هايرو هي منصة وساطة فقط.\n2. المسؤولیة عن جودة العمل والدفع تقع على عاتق العميل والمحترف.\n3. يمنع نشر محتوى مسيء أو كاذب.\n4. يحق للمنصة تعليق حسابات المستخدمين الذين ينتهكون القواعد.',
          'privacy_content': 'خصوصيتك تهمنا:\n1. نجمع معلومات أساسية (الاسم، الهاتف، المدينة) لتشغيل الخدمة.\n2. نستخدم الموقع الجغرافي للعثور على المحترفين القريبين منك.\n3. لا يتم بيع بياناتك لأطراف ثالثة لأغراض إعلانية.\n4. يمكنك طلب حذف حسابك وبياناتك في أي وقت من خلال الإعدادات.',
          'developer': 'تم التطوير بواسطة فريق هايرو',
          'contact': 'اتصل بنا: support@hiro.com',
        };
      case 'am':
        return {
          'title': 'ስለ እኛ እና ህጋዊ',
          'app_name': 'ሂሮ',
          'version': 'ስሪት 1.0.0',
          'terms_title': 'የአጠቃቀም ደንቦች',
          'privacy_title': 'የግላዊነት ፖሊሲ',
          'terms_content': 'ወደ ሂሮ እንኳን ደህና መጡ። መተግበሪያውን ሲጠቀሙ በሚከተሉት ደንቦች ይስማማሉ፡\n1. ሂሮ አገናኝ መድረክ ብቻ ነው።\n2. ለስራው ጥራት እና ለክፍያ ኃላፊነቱ በደንበኛው እና በባለሙያው መካከል ነው።\n3. አፀያፊ ወይም የሐሰት ይዘት መለጠፍ የተከለከለ ነው።\n4. ደንቦችን የሚጥሱ ተጠቃሚዎችን የማገድ መብታችን የተጠበቀ ነው።',
          'privacy_content': 'የእርስዎ ግላዊነት ለእኛ አስፈላጊ ነው፡\n1. መሰረታዊ መረጃዎችን (ስም፣ ስልክ፣ ከተማ) ለአገልግሎቱ እንሰበስባለን።\n2. በአቅራቢያዎ ያሉ ባለሙያዎችን ለማግኘት የእርስዎን አካባቢ እንጠቀማለን።\n3. የእርስዎ መረጃ ለሶስተኛ ወገን ለንግድ ማስታወቂያ አይተላለፍም።\n4. በማንኛውም ጊዜ አካውንትዎን እና መረጃዎን እንዲሰረዝ መጠየቅ ይችላሉ።',
          'developer': 'በ ሂሮ ቡድን የተገነባ',
          'contact': 'ያግኙን: support@hiro.com',
        };
      default:
        return {
          'title': 'About & Legal',
          'app_name': 'hiro',
          'version': 'Version 1.0.0',
          'terms_title': 'Terms of Service',
          'privacy_title': 'Privacy Policy',
          'terms_content': 'Welcome to hiro. By using this app, you agree to the following:\n1. hiro is a matching platform only.\n2. Quality of work and payments are strictly between the client and the professional.\n3. Posting offensive or false content is prohibited.\n4. We reserve the right to suspend accounts that violate these rules.',
          'privacy_content': 'Your privacy matters:\n1. We collect basic info (name, phone, city) to enable our services.\n2. Location data is used to find pros near you.\n3. Your data is never sold to third parties for advertising.\n4. You can request account and data deletion at any time via settings.',
          'developer': 'Developed by hiro Team',
          'contact': 'Contact Us: support@hiro.com',
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
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(strings['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildHero(strings),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _buildSection(strings['terms_title']!, strings['terms_content']!, Icons.gavel_rounded),
                    const SizedBox(height: 20),
                    _buildSection(strings['privacy_title']!, strings['privacy_content']!, Icons.lock_outline_rounded),
                    const SizedBox(height: 40),
                    const Divider(),
                    const SizedBox(height: 20),
                    Text(strings['developer']!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    Text(strings['contact']!, style: const TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(Map<String, String> strings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: const BoxDecoration(
        color: Color(0xFF1976D2),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.hub_rounded, size: 60, color: Color(0xFF1976D2)),
          ),
          const SizedBox(height: 16),
          Text(strings['app_name']!, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1)),
          Text(strings['version']!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black, blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1976D2), size: 24),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 16),
          Text(content, style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF475569))),
        ],
      ),
    );
  }
}
