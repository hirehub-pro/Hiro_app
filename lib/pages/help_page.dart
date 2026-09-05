import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/pages/chat_page.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.openSupportChatOnLoad = false});

  final bool openSupportChatOnLoad;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isOpeningSupportChat = false;

  @override
  void initState() {
    super.initState();
    if (widget.openSupportChatOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSupportChat(_strings(context));
      });
    }
  }

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
          'contact_options_title': 'צרו קשר בדרך שנוחה לכם',
          'contact_email': 'דוא״ל',
          'contact_whatsapp': 'WhatsApp',
          'contact_chat': 'צ׳אט באפליקציה',
          'email_open_failed': 'לא הצלחנו לפתוח את אפליקציית הדוא״ל כרגע.',
          'whatsapp_open_failed': 'לא הצלחנו לפתוח את WhatsApp כרגע.',
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
          'faq_1_q': 'איך מוצאים בעל מקצוע לפי מקצוע, שם או אזור?',
          'faq_1_a':
              'פתחו את חיפוש בעלי המקצוע ממסך הבית. בחרו קטגוריה או חפשו מקצוע, שם או עיר. אפשר לסנן לפי רדיוס שירות ולמיין לפי דירוג, מרחק או שם. לחצו על תוצאה כדי לפתוח את הפרופיל המלא.',
          'faq_2_q': 'איך שולחים בקשת עבודה מתוך לוח הזמנים?',
          'faq_2_a':
              'פתחו את פרופיל בעל המקצוע ואת לוח הזמנים שלו, בחרו תאריך עתידי שאינו חופשה או יום חופש קבוע ולחצו על בקשת עבודה. בחרו שעות, כתבו תיאור, הוסיפו תמונות ומיקום כשנדרש, ואז לחצו שלח עכשיו.',
          'faq_3_q': 'למה לפעמים הבקשה מבקשת מיקום ולפעמים לא?',
          'faq_3_a':
              'הטופס מתאים את עצמו לאופן השירות של בעל המקצוע: בשירות שמגיע ללקוח אפשר להשתמש במיקום הנוכחי או לבחור במפה; בתור אצל בעל המקצוע מוצג מיקום העסק; ובפגישה אונליין אין צורך במיקום.',
          'faq_4_q': 'מה ההבדל בין בקשת עבודה לבקשת הצעת מחיר?',
          'faq_4_a':
              'בקשת עבודה מיועדת לתאריך ולשעות שבהם תרצו לבצע עבודה או לקבוע תור. בקשת הצעת מחיר מיועדת לקבלת מחיר ופרטי ביצוע לפני קביעה. שני הסוגים נשלחים לבעל המקצוע ונשמרים בבקשות שלי.',
          'faq_5_q': 'איפה רואים בקשות ששלחתי ואיך מבטלים אותן?',
          'faq_5_a':
              'פתחו את הבקשות שלי כדי לראות בקשות שממתינות, התקבלו, נדחו, בוטלו או פג תוקפן. לחיצה על בקשה מציגה את התאריך, השעות, התיאור, התמונות והסטטוס. כל עוד היא ממתינה אפשר לפתוח אותה ולבטל.',
          'faq_6_q': 'איך מתחילים צ׳אט ושולחים תמונות או קבצים?',
          'faq_6_a':
              'אפשר לפתוח שיחה מפרופיל בעל המקצוע, מתהליך בקשה או ממסך ההודעות. השיחה שומרת את ההודעות והמדיה באותו מקום. לצ׳אט תמיכה השתמשו בכפתור צור קשר עם מנהל בראש העמוד הזה.',
          'faq_7_q': 'איך שומרים בעל מקצוע, משאירים ביקורת או מדווחים?',
          'faq_7_a':
              'בפרופיל ניתן להוסיף בעל מקצוע למועדפים ולפתוח את רשימת בעלי המקצוע שאהבתי. כאשר אפשרות הביקורת זמינה, פתחו אותה מהפרופיל והוסיפו דירוג ותוכן. לדיווח על משתמש, שיחה או תוכן השתמשו בפעולת הדיווח במסך המתאים ועקבו אחר הטיפול בדוחות שבהגדרות.',
          'faq_8_q': 'איך משתמשים בקהילה ובפוסטים?',
          'faq_8_a':
              'בקהילה אפשר לפרסם פוסט עם טקסט ומדיה, לשייך מקצוע, לחפש ולסנן לפי מקצוע, מרחק, פוסטים שאהבתם או הפוסטים שלכם. אפשר לפתוח פוסט לפרטים, להגיב, לשתף, להסתיר, לדווח או לחסום משתמש לפי הפעולות הזמינות.',
          'faq_9_q': 'איך בעל מקצוע מעדכן פרופיל ולוח זמנים?',
          'faq_9_a':
              'בפרופיל העסק אפשר לעדכן שם, טלפונים, דוא״ל, תיאור, מקצועות, שפות, אזור ורדיוס עבודה, תמונות ופרויקטים. בלוח הזמנים אפשר לסמן ימי עבודה, להגדיר כמה טווחי שעות, חופשות, יום חופש קבוע, תזכורות והערות, וגם לבחור אם להסתיר את הלוח מאחרים.',
          'faq_10_q': 'מה נפתח עם מנוי Pro פעיל?',
          'faq_10_a':
              'מנוי Pro מיועד לבעלי מקצוע ופותח כלים מקצועיים שמוגנים במנוי, כולל יצירת מסמכים וחשבוניות ויכולות מתקדמות נוספות. את מצב המנוי, התאריך והתוקף אפשר לבדוק במסך המנוי. אם המנוי אינו פעיל, מסכים מוגנים יציגו מעבר לחידוש.',
          'faq_11_q': 'למה צריך לאמת את העסק לפני יצירת מסמכים?',
          'faq_11_a':
              'כלי המסמכים משתמש בפרטי העסק החוקיים. במסך אימות העסק מזינים שם עסק, מספר עוסק או חברה, כתובת, סיווג כעוסק פטור, מורשה או חברה, מסמכים והצהרות. הסיווג קובע אילו סוגי מסמכים אפשר להפיק, והבקשה עוברת לבדיקה.',
          'faq_12_q': 'איך יוצרים חשבונית, קבלה או מסמך אחר?',
          'faq_12_a':
              'בכלי העסק לחצו יצירת מסמך. לאחר אימות הזהות בחרו סוג מסמך: הצעת מחיר, הזמנת עבודה, חשבון עסקה, חשבונית, חשבונית/קבלה, חשבונית מס זיכוי או קבלה, לפי סיווג העסק. בחרו או הוסיפו לקוח, הוסיפו פריטים, מחירים, מע״מ או תשלומים, עברו לתצוגה מקדימה ושמרו.',
          'faq_13_q': 'מתי צריך מספר הקצאה ואיך מקבלים אותו?',
          'faq_13_a':
              'האפליקציה דורשת מספר הקצאה רק לחשבונית מס או חשבונית/קבלה החייבת במע״מ, כאשר סכום העסקה לפני מע״מ גבוה מהסף שהוגדר במערכת ויש מספר זיהוי ללקוח. יש למלא את מספרי העוסק של העסק והלקוח ולהתחבר לרשות המסים. בעת השמירה Hiro מבקש את ההקצאה; אם לא מתקבל מספר, המסמך לא נשמר.',
          'faq_14_q': 'מהו מספר הפתיחה של מסמך ולמה חשוב לבחור נכון?',
          'faq_14_a':
              'בפעם הראשונה שמפיקים סוג מסמך ממוספר, האפליקציה מבקשת מספר פתיחה ושומרת ממנו מונה רציף לאותו סוג. יש להזין את המספר הנכון לפי רצף הנהלת החשבונות, כי לאחר אישורו לא ניתן לשנות אותו מתוך האפליקציה.',
          'faq_15_q': 'מה אפשר לעשות במסמכים שמורים?',
          'faq_15_a':
              'במסמכים שמורים אפשר לעבור בין מסמכים שיצרתם למסמכים שנשלחו אליכם, לסנן לפי סוג, תאריך וסטטוס ולפתוח PDF. אפשר לשלוח מסמך לאיש קשר, לשלוח הצעת מחיר או הזמנת עבודה לחתימה, ליצור קבלה מלאה או חלקית מחשבונית, ליצור חשבונית מס זיכוי, ליצור קבלה מבטלת ולעקוב אחר מצב תשלום והקצאה.',
          'faq_16_q': 'איך מנהלים לקוחות ושומרים את הפרטים לחשבונית הבאה?',
          'faq_16_a':
              'פתחו לקוחות מכלי העסק. אפשר לשמור שם, מספר עוסק, מספר לקוח חיצוני, כתובת, אנשי קשר, טלפונים, דוא״ל ופרטי הנהלת חשבונות. בעת יצירת מסמך חפשו ובחרו לקוח שמור כדי למלא את הפרטים אוטומטית, או הוסיפו לקוח חדש מתוך הבונה.',
          'faq_17_q': 'איך מייצאים מסמכים לחשבשבת?',
          'faq_17_a':
              'בהגדרות פתחו ייצוא להנה״ח חיצונית, הגדירו את מספרי הקופות וכרטיסי הנהלת החשבונות, בחרו טווח תאריכים וכתובת דוא״ל. האפליקציה יוצרת את קובצי MOVEIN ו-HESHIN הנתמכים ושולחת אותם למייל באופן מאובטח.',
          'faq_18_q': 'איפה רואים נתונים עסקיים, התראות ודוחות?',
          'faq_18_a':
              'בעלי מקצוע יכולים לפתוח אנליטיקה מכלי העסק. במסך ההתראות מופיעים עדכונים על בקשות, צ׳אטים ופעילות רלוונטית. בהגדרות אפשר לפתוח את הדוחות ששלחתם ולעקוב אחר הסטטוס והתשובות.',
          'faq_19_q': 'איך משנים פרטי חשבון או מקבלים תמיכה?',
          'faq_19_a':
              'בהגדרות החשבון אפשר לשנות דוא״ל או סיסמה ולבקש מחיקת חשבון; פעולות רגישות עשויות לדרוש אימות מחדש בטלפון, סיסמה או דוא״ל. לתמיכה פתחו צ׳אט עם מנהל או WhatsApp בעמוד הזה, וצרפו את המסך, מספר הבקשה או המסמך ותיאור מדויק של הבעיה.',
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
          'contact_options_title': 'تواصل بالطريقة المناسبة لك',
          'contact_email': 'البريد',
          'contact_whatsapp': 'WhatsApp',
          'contact_chat': 'دردشة التطبيق',
          'email_open_failed': 'تعذر فتح تطبيق البريد حاليًا.',
          'whatsapp_open_failed': 'تعذر فتح WhatsApp حاليًا.',
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
          'faq_1_q': 'كيف أجد صاحب مهنة حسب المهنة أو الاسم أو المنطقة؟',
          'faq_1_a':
              'افتح البحث عن أصحاب المهن من الصفحة الرئيسية. اختر فئة أو ابحث بالمهنة أو الاسم أو المدينة. يمكنك التصفية حسب نطاق الخدمة والترتيب حسب التقييم أو القرب أو الاسم، ثم اضغط على النتيجة لفتح الملف الكامل.',
          'faq_2_q': 'كيف أرسل طلب عمل من صفحة الجدول؟',
          'faq_2_a':
              'افتح ملف صاحب المهنة ثم جدوله، واختر تاريخًا مستقبليًا ليس إجازة أو يوم عطلة ثابتًا واضغط طلب عمل. اختر الوقت، واكتب الوصف، وأضف الصور والموقع عند الحاجة، ثم اضغط إرسال الآن.',
          'faq_3_q': 'لماذا يطلب النموذج موقعًا في بعض الطلبات فقط؟',
          'faq_3_a':
              'يتغير النموذج حسب طريقة خدمة صاحب المهنة: إذا كان يأتي إلى العميل يمكنك استخدام موقعك الحالي أو الاختيار من الخريطة؛ وإذا كان العميل يذهب إليه يظهر موقع النشاط؛ أما الجلسة الأونلاين فلا تحتاج إلى موقع.',
          'faq_4_q': 'ما الفرق بين طلب العمل وطلب عرض السعر؟',
          'faq_4_a':
              'طلب العمل مخصص لتاريخ ووقت تريد فيه تنفيذ العمل أو حجز موعد. طلب عرض السعر مخصص للحصول على السعر وتفاصيل التنفيذ قبل الحجز. كلاهما يُرسل إلى صاحب المهنة ويظهر في طلباتي.',
          'faq_5_q': 'أين أرى الطلبات التي أرسلتها وكيف ألغيها؟',
          'faq_5_a':
              'افتح طلباتي لرؤية الطلبات المنتظرة أو المقبولة أو المرفوضة أو الملغاة أو المنتهية. اضغط على الطلب لرؤية التاريخ والوقت والوصف والصور والحالة. يمكن إلغاء الطلب أثناء انتظاره للرد.',
          'faq_6_q': 'كيف أبدأ محادثة وأرسل صورًا أو ملفات؟',
          'faq_6_a':
              'يمكن بدء المحادثة من ملف صاحب المهنة أو من مسار الطلب أو صفحة الرسائل، وتبقى الرسائل والوسائط في المحادثة نفسها. لدردشة الدعم استخدم زر التواصل مع مشرف أعلى هذه الصفحة.',
          'faq_7_q': 'كيف أحفظ صاحب مهنة أو أضيف تقييمًا أو أرسل بلاغًا؟',
          'faq_7_a':
              'من الملف الشخصي يمكنك إضافة صاحب المهنة إلى المفضلة ثم الوصول إليه من قائمة المفضلة. عندما تكون المراجعة متاحة افتحها من الملف وأضف التقييم والنص. للإبلاغ عن مستخدم أو محادثة أو محتوى استخدم إجراء الإبلاغ في الشاشة المناسبة وتابع البلاغ من الإعدادات.',
          'faq_8_q': 'كيف أستخدم المجتمع والمنشورات؟',
          'faq_8_a':
              'يمكنك نشر نص ووسائط وربط المنشور بمهنة، ثم البحث والتصفية حسب المهنة أو المسافة أو المنشورات التي أعجبتك أو منشوراتك. افتح المنشور للتفاصيل والتعليقات والمشاركة، واستخدم الإخفاء أو الإبلاغ أو الحظر عند توفرها.',
          'faq_9_q': 'كيف يحدّث صاحب المهنة ملفه وجدوله؟',
          'faq_9_a':
              'من ملف النشاط يمكن تحديث الاسم والهواتف والبريد والوصف والمهن واللغات والمنطقة ونطاق العمل والصور والمشاريع. في الجدول يمكن تحديد أيام العمل وعدة فترات زمنية والإجازات ويوم العطلة الثابت والتذكيرات والملاحظات، واختيار إخفاء الجدول عن الآخرين.',
          'faq_10_q': 'ما الذي يفتحه اشتراك Pro النشط؟',
          'faq_10_a':
              'اشتراك Pro مخصص لأصحاب المهن ويفتح الأدوات المهنية المحمية بالاشتراك، ومنها إنشاء المستندات والفواتير وميزات متقدمة أخرى. افحص حالة الاشتراك وتاريخه وانتهاءه في صفحة الاشتراك؛ وإذا كان غير نشط ستعرض الأدوات المحمية خيار التجديد.',
          'faq_11_q': 'لماذا يجب التحقق من النشاط قبل إنشاء المستندات؟',
          'faq_11_a':
              'تعتمد أداة المستندات على بيانات النشاط القانونية. أدخل اسم النشاط ورقم المصلحة أو الشركة والعنوان، واختر التصنيف الضريبي المعفى أو المرخص أو الشركة، وارفع المستندات ووافق على الإقرارات. يحدد التصنيف أنواع المستندات المتاحة ويُرسل الطلب للمراجعة.',
          'faq_12_q': 'كيف أنشئ فاتورة أو إيصالًا أو مستندًا آخر؟',
          'faq_12_a':
              'من أدوات النشاط اضغط إنشاء مستند. بعد التحقق من الهوية اختر عرض سعر أو أمر عمل أو فاتورة أولية أو فاتورة أو فاتورة/إيصال أو فاتورة ضريبية دائنة أو إيصال حسب تصنيف النشاط. اختر عميلًا، وأضف البنود والأسعار والضريبة أو الدفعات، ثم عاين المستند واحفظه.',
          'faq_13_q': 'متى أحتاج إلى رقم تخصيص وكيف أحصل عليه؟',
          'faq_13_a':
              'يُطلب رقم التخصيص فقط لفاتورة ضريبية أو فاتورة/إيصال خاضعة لضريبة القيمة المضافة عندما يتجاوز المبلغ قبل الضريبة الحد المضبوط في النظام ويوجد رقم تعريف للعميل. أدخل رقمي النشاط والعميل واتصل بسلطة الضرائب. يطلب Hiro الرقم عند الحفظ، وإذا لم يصل فلن يُحفظ المستند.',
          'faq_14_q': 'ما رقم بداية المستند ولماذا يجب اختياره بدقة؟',
          'faq_14_a':
              'عند إنشاء أول مستند من نوع مرقّم يطلب التطبيق رقم البداية، ثم يتابع تسلسلًا مستقلًا لذلك النوع. أدخل الرقم الصحيح حسب تسلسل المحاسبة لأن التطبيق لا يسمح بتغييره بعد تأكيده.',
          'faq_15_q': 'ماذا يمكنني أن أفعل في المستندات المحفوظة؟',
          'faq_15_a':
              'يمكن التبديل بين المستندات التي أنشأتها والتي أُرسلت إليك، والتصفية حسب النوع والتاريخ والحالة وفتح PDF. يمكنك إرسال مستند، وإرسال عرض سعر أو أمر عمل للتوقيع، وإنشاء إيصال كامل أو جزئي من فاتورة، وإنشاء فاتورة ضريبية دائنة أو إيصال إلغاء، ومتابعة حالة الدفع والتخصيص.',
          'faq_16_q': 'كيف أدير العملاء وأعيد استخدام بياناتهم؟',
          'faq_16_a':
              'افتح العملاء من أدوات النشاط. احفظ الاسم ورقم المصلحة ورقم العميل الخارجي والعنوان وجهات الاتصال والهواتف والبريد وبيانات المحاسبة. عند إنشاء مستند ابحث عن عميل محفوظ لملء البيانات تلقائيًا، أو أضف عميلًا جديدًا من أداة الإنشاء.',
          'faq_17_q': 'كيف أصدّر المستندات إلى Hashavshevet؟',
          'faq_17_a':
              'من الإعدادات افتح التصدير إلى محاسبة خارجية، واضبط أرقام الصناديق والحسابات، واختر نطاق تواريخ وبريد المستلم. ينشئ التطبيق ملفات MOVEIN وHESHIN المدعومة ويرسلها بأمان إلى البريد.',
          'faq_18_q': 'أين أرى التحليلات والإشعارات والبلاغات؟',
          'faq_18_a':
              'يمكن لأصحاب المهن فتح التحليلات من أدوات النشاط. تعرض صفحة الإشعارات تحديثات الطلبات والدردشة والنشاط المرتبط. ومن الإعدادات يمكن فتح البلاغات التي أرسلتها ومتابعة حالتها وردود الإدارة.',
          'faq_19_q': 'كيف أغيّر بيانات الحساب أو أتواصل مع الدعم؟',
          'faq_19_a':
              'في إعدادات الحساب يمكنك تغيير البريد أو كلمة المرور وطلب حذف الحساب. قد تتطلب الإجراءات الحساسة إعادة التحقق بالهاتف أو كلمة المرور أو البريد. للدعم افتح دردشة مع مشرف أو WhatsApp من هذه الصفحة وأرفق اسم الشاشة ورقم الطلب أو المستند ووصف المشكلة.',
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
          'contact_options_title': 'Contact us your preferred way',
          'contact_email': 'Email',
          'contact_whatsapp': 'WhatsApp',
          'contact_chat': 'App chat',
          'email_open_failed': 'Could not open your email app right now.',
          'whatsapp_open_failed': 'Could not open WhatsApp right now.',
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
          'faq_1_q': 'How do I find a professional by trade, name, or area?',
          'faq_1_a':
              'Open professional search from Home. Choose a category or search by profession, name, or city. You can filter by service radius and sort by rating, distance, or name. Tap a result to open the full profile.',
          'faq_2_q': 'How do I send a job request from the Schedule page?',
          'faq_2_a':
              'Open the professional’s profile and Schedule, choose a future date that is not a vacation or permanent day off, and tap Request Work. Choose the time, write a description, add photos and a location when required, then tap Send Now.',
          'faq_3_q':
              'Why do some requests ask for a location and others do not?',
          'faq_3_a':
              'The form follows the professional’s service mode. For service at your location, use your current location or choose one on the map. For an appointment at the professional, the business location is shown. Online meetings do not require a location.',
          'faq_4_q':
              'What is the difference between a job request and a quote request?',
          'faq_4_a':
              'A job request is for a date and time when you want work performed or an appointment booked. A quote request asks for price and scope details before booking. Both are sent to the professional and saved under My Requests.',
          'faq_5_q': 'Where can I track or cancel requests I sent?',
          'faq_5_a':
              'Open My Requests to see requests that are waiting, accepted, rejected, cancelled, or expired. Tap one to view its date, time, description, photos, and status. A request can be cancelled while it is still waiting for a response.',
          'faq_6_q': 'How do I start a chat and send photos or files?',
          'faq_6_a':
              'Start a conversation from a professional profile, a request flow, or Messages. Messages and media remain together in that conversation. For support chat, use Contact an admin at the top of this page.',
          'faq_7_q': 'How do I save, review, or report a professional?',
          'faq_7_a':
              'Use the professional profile to add someone to Favorites, then find them in Liked Professionals. When the review action is available, open it from the profile to add a rating and text. To report a user, chat, or content, use the report action on that screen and follow the report under Settings.',
          'faq_8_q': 'How do Community posts work?',
          'faq_8_a':
              'You can publish text and media, assign a profession, and search or filter by profession, distance, liked posts, or your own posts. Open a post for details, comments, and sharing. Hide, report, or block actions are available where applicable.',
          'faq_9_q':
              'How does a professional update their profile and schedule?',
          'faq_9_a':
              'The business profile lets you update your name, phones, email, description, professions, languages, area, work radius, photos, and projects. In Schedule you can set working days, multiple time ranges, vacations, a permanent day off, reminders, and notes, and choose whether others can see the schedule.',
          'faq_10_q': 'What does an active Pro subscription unlock?',
          'faq_10_a':
              'Pro is for professionals and unlocks subscription-protected business tools, including document and invoice creation and other advanced features. Check the status, dates, and expiry on the Subscription page. If Pro is inactive, protected tools show a renewal path.',
          'faq_11_q':
              'Why must I verify my business before creating documents?',
          'faq_11_a':
              'The document tools use legal business details. Enter the registered name, business or VAT ID, address, tax classification (exempt, licensed, or company), supporting documents, and declarations. The classification controls which document types are available, and the submission is reviewed.',
          'faq_12_q':
              'How do I create an invoice, receipt, or another document?',
          'faq_12_a':
              'Under Business Tools, tap Create Document. After identity verification, choose Quote, Work Order, Proforma Invoice, Invoice, Invoice/Receipt, Tax Invoice Credit, or Receipt as allowed for your business type. Select or add a client, enter items, prices, VAT or payments, preview, and save.',
          'faq_13_q':
              'When is an allocation number required, and how do I get one?',
          'faq_13_a':
              'Hiro requires an allocation number only for a VAT Tax Invoice or Invoice/Receipt when the subtotal before VAT exceeds the system threshold and the client has an ID. Enter both business and client tax IDs and connect to the Israel Tax Authority. Hiro requests the allocation during save; if no number is received, the document is not saved.',
          'faq_14_q':
              'What is a starting document number, and why must it be correct?',
          'faq_14_a':
              'The first time you create a numbered document type, Hiro asks for its starting number and maintains a separate sequential counter for that type. Enter the number that matches your accounting sequence because it cannot be changed in the app after confirmation.',
          'faq_15_q': 'What can I do from Saved Documents?',
          'faq_15_a':
              'Switch between documents you created and documents sent to you, filter by type, date, and status, and open the PDF. You can send a document, send a Quote or Work Order for signature, create a full or partial Receipt from an Invoice, create a Tax Invoice Credit or cancellation Receipt, and track payment and allocation status.',
          'faq_16_q': 'How do I manage clients and reuse their details?',
          'faq_16_a':
              'Open Clients from Business Tools. Save the name, tax ID, external client number, address, contacts, phones, emails, and accounting details. In the document builder, search for a saved client to fill those fields automatically, or add a new client there.',
          'faq_17_q': 'How do I export documents to Hashavshevet?',
          'faq_17_a':
              'Open External Accounting Export in Settings. Configure register and account numbers, select a document date range and recipient email, then create the export. Hiro generates the supported MOVEIN and HESHIN files and sends them securely by email.',
          'faq_18_q': 'Where can I see analytics, notifications, and reports?',
          'faq_18_a':
              'Professionals can open Analytics from Business Tools. Notifications shows updates about requests, chats, and relevant activity. In Settings, open Reports to review reports you submitted and follow their status and admin replies.',
          'faq_19_q': 'How do I change account details or contact support?',
          'faq_19_a':
              'Account Settings lets you change your email or password and request account deletion. Sensitive actions may require phone, password, or email verification again. For help, open an admin chat or WhatsApp on this page and include the screen name, request or document number, and a precise description.',
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
    final faqItems = <(String, String, IconData)>[
      (strings['faq_1_q']!, strings['faq_1_a']!, Icons.search_rounded),
      (strings['faq_2_q']!, strings['faq_2_a']!, Icons.event_available_rounded),
      (strings['faq_3_q']!, strings['faq_3_a']!, Icons.location_on_outlined),
      (strings['faq_4_q']!, strings['faq_4_a']!, Icons.request_quote_outlined),
      (strings['faq_5_q']!, strings['faq_5_a']!, Icons.fact_check_outlined),
      (
        strings['faq_6_q']!,
        strings['faq_6_a']!,
        Icons.chat_bubble_outline_rounded,
      ),
      (strings['faq_7_q']!, strings['faq_7_a']!, Icons.star_outline_rounded),
      (strings['faq_8_q']!, strings['faq_8_a']!, Icons.groups_outlined),
      (strings['faq_9_q']!, strings['faq_9_a']!, Icons.calendar_month_outlined),
      (
        strings['faq_10_q']!,
        strings['faq_10_a']!,
        Icons.workspace_premium_outlined,
      ),
      (
        strings['faq_11_q']!,
        strings['faq_11_a']!,
        Icons.verified_user_outlined,
      ),
      (strings['faq_12_q']!, strings['faq_12_a']!, Icons.receipt_long_outlined),
      (strings['faq_13_q']!, strings['faq_13_a']!, Icons.numbers_rounded),
      (
        strings['faq_14_q']!,
        strings['faq_14_a']!,
        Icons.format_list_numbered_rounded,
      ),
      (strings['faq_15_q']!, strings['faq_15_a']!, Icons.folder_copy_outlined),
      (
        strings['faq_16_q']!,
        strings['faq_16_a']!,
        Icons.people_outline_rounded,
      ),
      (
        strings['faq_17_q']!,
        strings['faq_17_a']!,
        Icons.account_balance_outlined,
      ),
      (strings['faq_18_q']!, strings['faq_18_a']!, Icons.analytics_outlined),
      (
        strings['faq_19_q']!,
        strings['faq_19_a']!,
        Icons.manage_accounts_outlined,
      ),
    ];

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
                for (var index = 0; index < faqItems.length; index++) ...[
                  _buildFaqCard(
                    faqItems[index].$1,
                    faqItems[index].$2,
                    faqItems[index].$3,
                    isRtl,
                  ),
                  if (index != faqItems.length - 1) const SizedBox(height: 12),
                ],
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
          Text(
            strings['contact_options_title']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildContactCircle(
                label: strings['contact_email']!,
                icon: Icons.email_outlined,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F5CC0),
                onTap: () => _openEmail(strings),
              ),
              _buildContactCircle(
                label: strings['contact_whatsapp']!,
                icon: Icons.chat_rounded,
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                onTap: () => _openWhatsApp(strings),
              ),
              _buildContactCircle(
                label: strings['contact_chat']!,
                icon: Icons.support_agent_rounded,
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                isLoading: _isOpeningSupportChat,
                onTap: _isOpeningSupportChat
                    ? null
                    : () => _openSupportChat(strings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactCircle({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: Material(
              color: backgroundColor,
              elevation: 3,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Center(
                  child: isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: foregroundColor,
                          ),
                        )
                      : Icon(icon, color: foregroundColor, size: 29),
                ),
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

  Future<void> _openWhatsApp(Map<String, String> strings) async {
    final opened = await launchUrl(
      Uri.parse('https://wa.me/972542978614'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showSnackBar(strings['whatsapp_open_failed']!);
    }
  }

  Future<void> _openEmail(Map<String, String> strings) async {
    final opened = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: 'support@hiro-services.com',
        queryParameters: {'subject': 'Hiro Support'},
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showSnackBar(strings['email_open_failed']!);
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
