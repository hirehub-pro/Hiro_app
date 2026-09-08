import 'package:intl/intl.dart';

/// One business-wide insight, independent of the analytics profession filter.
class GrowthRecommendation {
  final String scope;
  final String summary;
  final String actionLabel;
  final String action;

  const GrowthRecommendation({
    required this.scope,
    required this.summary,
    required this.actionLabel,
    required this.action,
  });
}

GrowthRecommendation buildGrowthRecommendation({
  required String locale,
  required List<String> professions,
  required Map<String, dynamic> overallRatings,
  required int weeklyViews,
  required int totalViews,
  required double? totalEarnings,
}) {
  final strings = _copy[locale] ?? _copy['en']!;
  String t(String key, [Map<String, String> params = const {}]) {
    var result = strings[key]!;
    params.forEach((key, value) => result = result.replaceAll('{$key}', value));
    return result;
  }

  double number(String key) {
    final value = overallRatings[key];
    return value is num && value.isFinite ? value.toDouble() : 0;
  }

  final count = number('reviewCount').toInt().clamp(0, 1 << 31);
  final rating = number('avgOverallRating');
  final hasRating = count > 0 && rating >= 1 && rating <= 10;
  final listed = professions
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();
  final earnings = totalEarnings != null && totalEarnings.isFinite
      ? totalEarnings
      : null;
  final format = NumberFormat('#,##0.##');
  // Isolate numeric runs so punctuation and currency stay readable in RTL text.
  String isolate(String value) => '\u2068$value\u2069';
  final parts = <String>[
    hasRating
        ? t('rating', {
            'rating': isolate('${rating.toStringAsFixed(1)}/10'),
            'count': '$count',
          })
        : t('no_reviews'),
    if (hasRating && count < 5) t('few_reviews'),
    t('views', {
      'week': '${weeklyViews.clamp(0, 1 << 31)}',
      'total': '${totalViews.clamp(0, 1 << 31)}',
    }),
    if (earnings == null)
      t('unknown_earnings')
    else if (earnings == 0)
      t('zero_earnings')
    else
      t('earnings', {'amount': isolate('₪${format.format(earnings)}')}),
  ];

  // Conservative editorial rules, not market benchmarks or growth predictions.
  // Require several reviews before prioritizing a quality issue over discovery.
  final metrics =
      <String, double>{
            'improve_price': number('avgPriceRating'),
            'improve_service': number('avgServiceRating'),
            'improve_timing': number('avgTimingRating'),
            'improve_work': number('avgWorkQualityRating'),
          }.entries
          .where((entry) => entry.value >= 1 && entry.value <= 10)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
  final qualityIssue =
      hasRating &&
      count >= 5 &&
      (rating < 8 || (metrics.isNotEmpty && metrics.first.value < 8));
  String actionKey;
  if (listed.isEmpty) {
    actionKey = 'add_professions';
  } else if (qualityIssue) {
    final weakest = metrics.where((m) => m.value == metrics.first.value);
    actionKey =
        metrics.isNotEmpty && metrics.first.value < 8 && weakest.length == 1
        ? metrics.first.key
        : 'improve_overall';
  } else if (weeklyViews <= 0) {
    actionKey = 'share';
  } else if (earnings == null) {
    actionKey = 'record';
  } else if (earnings <= 0) {
    actionKey = listed.length > 1 ? 'describe_many' : 'describe_one';
  } else if (!hasRating || count < 5) {
    actionKey = 'ask_review';
  } else {
    actionKey = 'retain';
  }

  return GrowthRecommendation(
    scope: listed.isEmpty
        ? t('no_professions')
        : t('scope', {'count': '${listed.length}'}),
    summary: parts.join(' '),
    actionLabel: t('next_step'),
    action: t(actionKey),
  );
}

const _copy = <String, Map<String, String>>{
  'en': {
    'scope': 'Across your listed professions ({count})',
    'no_professions': 'No professions are listed yet.',
    'no_reviews': 'There are no customer ratings yet.',
    'rating': 'Your average rating is {rating}. Customer reviews: {count}.',
    'few_reviews':
        'The review sample is still small, so it is too early to judge consistent performance.',
    'views': 'Profile views: {week} this week so far; {total} in total.',
    'earnings': 'Total recorded earnings: {amount}.',
    'zero_earnings':
        'Recorded earnings total zero; this alone does not tell us whether visitors became customers.',
    'unknown_earnings': 'Earnings data is not available yet.',
    'next_step': 'Your next step',
    'add_professions':
        'Add the professions you currently offer and explain what customers can book.',
    'improve_price':
        'Price is your lowest-rated area. Before the next job, agree on a clear quote and explain what it includes.',
    'improve_service':
        'Service is your lowest-rated area. For the next job, confirm the customer’s expectations and keep them updated.',
    'improve_timing':
        'Timing is your lowest-rated area. Agree on a realistic arrival and completion time, and communicate any changes early.',
    'improve_work':
        'Work quality is your lowest-rated area. Check the finished work with the customer and address any concerns before closing the job.',
    'improve_overall':
        'Read recent feedback and choose one recurring issue to address on your next job.',
    'share':
        'Share your profile with relevant potential customers and check next week’s views to see whether interest changes.',
    'describe_one':
        'Add a recent work example and a clear description of what customers can book, including your availability.',
    'describe_many':
        'Make each listed service easy to understand: explain what is included and add a relevant work example.',
    'ask_review':
        'Ask your next completed-job customer for an honest review to build a more reliable picture of your service.',
    'record':
        'Keep completed-job earnings up to date so you can assess results alongside views and reviews.',
    'retain':
        'Follow up with a past customer about future needs and keep your service details and availability current.',
  },
  'he': {
    'scope': 'תמונה כוללת לכל המקצועות שלך ({count})',
    'no_professions': 'עדיין לא נוספו מקצועות לפרופיל.',
    'no_reviews': 'עדיין אין דירוגים מלקוחות.',
    'rating': 'הדירוג הממוצע שלך הוא {rating}, על בסיס {count} ביקורות.',
    'few_reviews':
        'מספר הביקורות עדיין קטן, ולכן מוקדם להסיק על ביצועים לאורך זמן.',
    'views': 'צפיות בפרופיל: {week} מתחילת השבוע; {total} בסך הכול.',
    'earnings': 'סך ההכנסות המתועדות: {amount}.',
    'zero_earnings':
        'סך ההכנסות המתועדות הוא אפס; נתון זה לבדו לא מעיד אם צפיות הפכו ללקוחות.',
    'unknown_earnings': 'נתוני הכנסות עדיין אינם זמינים.',
    'next_step': 'הצעד הבא שלך',
    'add_professions':
        'הוסף את המקצועות שבהם אתה מציע שירות והסבר מה ניתן להזמין.',
    'improve_price':
        'המחיר הוא התחום עם הדירוג הנמוך ביותר שלך. לפני העבודה הבאה, סכם הצעת מחיר ברורה והסבר מה היא כוללת.',
    'improve_service':
        'השירות הוא התחום עם הדירוג הנמוך ביותר שלך. בעבודה הבאה, תאם ציפיות עם הלקוח ועדכן אותו לאורך הדרך.',
    'improve_timing':
        'עמידה בזמנים היא התחום עם הדירוג הנמוך ביותר שלך. סכם זמני הגעה וסיום מציאותיים ועדכן מראש על שינויים.',
    'improve_work':
        'איכות העבודה היא התחום עם הדירוג הנמוך ביותר שלך. בדוק את התוצאה עם הלקוח וטפל בהערות לפני סיום העבודה.',
    'improve_overall':
        'קרא את המשוב האחרון ובחר נושא חוזר אחד לשיפור בעבודה הבאה.',
    'share':
        'שתף את הפרופיל עם לקוחות פוטנציאליים רלוונטיים ובדוק בשבוע הבא אם חל שינוי במספר הצפיות.',
    'describe_one':
        'הוסף דוגמה מעבודה אחרונה ותיאור ברור של השירות שניתן להזמין, כולל הזמינות שלך.',
    'describe_many':
        'הבהר מה כולל כל שירות ברשימת המקצועות שלך והוסף דוגמת עבודה מתאימה.',
    'ask_review':
        'בקש מהלקוח הבא שעבורו תסיים עבודה ביקורת כנה, כדי לבנות תמונה אמינה יותר של השירות שלך.',
    'record':
        'עדכן את ההכנסות מעבודות שהושלמו כדי לבחון את התוצאות לצד הצפיות והביקורות.',
    'retain':
        'צור קשר עם לקוח קודם לגבי צרכים עתידיים, והקפד לעדכן את פרטי השירות והזמינות שלך.',
  },
  'ar': {
    'scope': 'نظرة شاملة على المهن المدرجة ({count})',
    'no_professions': 'لم تُضف أي مهن بعد.',
    'no_reviews': 'لا توجد تقييمات من العملاء بعد.',
    'rating': 'متوسط تقييمك {rating}، بناءً على {count} مراجعات.',
    'few_reviews':
        'عدد المراجعات ما زال صغيراً، لذا من المبكر الحكم على استمرارية الأداء.',
    'views': 'مشاهدات الملف: {week} منذ بداية الأسبوع؛ {total} إجمالاً.',
    'earnings': 'إجمالي الأرباح المسجلة: {amount}.',
    'zero_earnings':
        'إجمالي الأرباح المسجلة صفر؛ هذا وحده لا يوضح ما إذا كان الزوار قد أصبحوا عملاء.',
    'unknown_earnings': 'بيانات الأرباح غير متاحة بعد.',
    'next_step': 'خطوتك التالية',
    'add_professions':
        'أضف المهن التي تقدمها حالياً ووضّح الخدمات التي يمكن حجزها.',
    'improve_price':
        'السعر هو الجانب الأقل تقييماً لديك. اتفق على عرض سعر واضح قبل العمل القادم واشرح ما يشمله.',
    'improve_service':
        'الخدمة هي الجانب الأقل تقييماً لديك. اتفق مع العميل على توقعاته وأطلعه على المستجدات.',
    'improve_timing':
        'الالتزام بالمواعيد هو الجانب الأقل تقييماً لديك. حدّد أوقات وصول وإنجاز واقعية وأبلغ العميل مبكراً بأي تغيير.',
    'improve_work':
        'جودة العمل هي الجانب الأقل تقييماً لديك. راجع النتيجة مع العميل وعالج ملاحظاته قبل إنهاء العمل.',
    'improve_overall':
        'اقرأ الملاحظات الأخيرة واختر مشكلة متكررة واحدة لمعالجتها في العمل القادم.',
    'share':
        'شارك ملفك مع عملاء محتملين مناسبين وراجع المشاهدات الأسبوع القادم لمعرفة إن تغيّر الاهتمام.',
    'describe_one':
        'أضف مثالاً حديثاً لعملك ووصفاً واضحاً للخدمة المتاحة للحجز ومواعيد توفرك.',
    'describe_many':
        'وضّح ما تشمل كل خدمة في قائمة مهنك وأضف مثال عمل مناسباً.',
    'ask_review':
        'اطلب مراجعة صادقة من العميل القادم بعد إتمام العمل لبناء صورة أدق عن خدمتك.',
    'record':
        'حدّث أرباح الأعمال المكتملة لتقييم النتائج إلى جانب المشاهدات والمراجعات.',
    'retain':
        'تواصل مع عميل سابق بشأن احتياجاته المستقبلية وحدّث تفاصيل خدماتك ومواعيد توفرك.',
  },
  'ru': {
    'scope': 'Обзор всех указанных профессий ({count})',
    'no_professions': 'Профессии пока не указаны.',
    'no_reviews': 'Оценок клиентов пока нет.',
    'rating': 'Средняя оценка — {rating}, количество отзывов — {count}.',
    'few_reviews':
        'Отзывов пока мало, поэтому рано судить о стабильности результатов.',
    'views': 'Просмотры профиля: {week} с начала недели; {total} за всё время.',
    'earnings': 'Общий учтённый доход: {amount}.',
    'zero_earnings':
        'Учтённый доход равен нулю; это само по себе не показывает, стали ли посетители клиентами.',
    'unknown_earnings': 'Данные о доходах пока недоступны.',
    'next_step': 'Следующий шаг',
    'add_professions':
        'Добавьте профессии, по которым сейчас работаете, и объясните, какие услуги можно заказать.',
    'improve_price':
        'Цена получила самую низкую оценку. До следующей работы согласуйте понятную смету и объясните, что в неё входит.',
    'improve_service':
        'Сервис получил самую низкую оценку. Уточните ожидания клиента и сообщайте о ходе следующей работы.',
    'improve_timing':
        'Соблюдение сроков получило самую низкую оценку. Согласуйте реалистичное время прибытия и завершения и заранее сообщайте об изменениях.',
    'improve_work':
        'Качество работы получило самую низкую оценку. Проверьте результат вместе с клиентом и устраните замечания до завершения работы.',
    'improve_overall':
        'Прочитайте последние отзывы и выберите одну повторяющуюся проблему для решения в следующей работе.',
    'share':
        'Поделитесь профилем с подходящими потенциальными клиентами и проверьте просмотры на следующей неделе, чтобы оценить изменение интереса.',
    'describe_one':
        'Добавьте свежий пример работы и понятное описание доступной услуги с указанием вашей занятости.',
    'describe_many':
        'Объясните, что входит в каждую услугу по указанным профессиям, и добавьте подходящие примеры работ.',
    'ask_review':
        'После следующей выполненной работы попросите клиента оставить честный отзыв, чтобы получить более надёжную оценку сервиса.',
    'record':
        'Обновляйте доходы от завершённых работ, чтобы оценивать результаты вместе с просмотрами и отзывами.',
    'retain':
        'Свяжитесь с прежним клиентом по поводу будущих задач и обновите описание услуг и доступное время.',
  },
  'am': {
    'scope': 'የተዘረዘሩ ሙያዎችዎ አጠቃላይ እይታ ({count})',
    'no_professions': 'እስካሁን ሙያዎች አልተጨመሩም።',
    'no_reviews': 'እስካሁን የደንበኛ ደረጃዎች የሉም።',
    'rating': 'አማካይ ደረጃዎ {rating} ነው፣ በ{count} ግምገማዎች ላይ የተመሠረተ።',
    'few_reviews': 'የግምገማዎች ብዛት ገና አነስተኛ ነው፤ ስለ ቀጣይነት ያለው አፈጻጸም ለመወሰን ገና ነው።',
    'views': 'የፕሮፋይል እይታዎች፦ ከሳምንቱ መጀመሪያ {week}፤ በአጠቃላይ {total}።',
    'earnings': 'ጠቅላላ የተመዘገበ ገቢ፦ {amount}።',
    'zero_earnings': 'የተመዘገበው ገቢ ዜሮ ነው፤ ይህ ብቻውን ጎብኚዎች ደንበኞች መሆናቸውን አያሳይም።',
    'unknown_earnings': 'የገቢ መረጃ ገና አይገኝም።',
    'next_step': 'ቀጣዩ እርምጃዎ',
    'add_professions': 'አሁን የሚሰሩባቸውን ሙያዎች ያክሉ እና ደንበኞች ምን ማዘዝ እንደሚችሉ ያብራሩ።',
    'improve_price':
        'ዋጋ ዝቅተኛውን ደረጃ አግኝቷል። ከቀጣዩ ስራ በፊት ግልጽ የዋጋ ስምምነት ያድርጉ እና ምን እንደሚያካትት ያብራሩ።',
    'improve_service':
        'አገልግሎት ዝቅተኛውን ደረጃ አግኝቷል። በቀጣዩ ስራ የደንበኛውን ግምት ያረጋግጡ እና ስለ ሂደቱ ያሳውቁ።',
    'improve_timing':
        'ሰዓት ማክበር ዝቅተኛውን ደረጃ አግኝቷል። ተጨባጭ የመድረሻና የማጠናቀቂያ ጊዜ ይስማሙ እና ለውጦችን ቀድመው ያሳውቁ።',
    'improve_work':
        'የስራ ጥራት ዝቅተኛውን ደረጃ አግኝቷል። ውጤቱን ከደንበኛው ጋር ይፈትሹ እና ከመጨረስ በፊት ችግሮችን ያስተካክሉ።',
    'improve_overall':
        'የቅርብ ጊዜ አስተያየቶችን ያንብቡ እና በቀጣዩ ስራ ለማሻሻል አንድ ተደጋጋሚ ጉዳይ ይምረጡ።',
    'share':
        'ፕሮፋይልዎን ለሚመለከታቸው ደንበኞች ያጋሩ እና ፍላጎት መቀየሩን ለማየት በሚቀጥለው ሳምንት እይታዎችን ይፈትሹ።',
    'describe_one':
        'የቅርብ ጊዜ የስራ ምሳሌ እና የሚሰጡትን አገልግሎት ግልጽ መግለጫ ከሚገኙበት ጊዜ ጋር ያክሉ።',
    'describe_many':
        'በሙያ ዝርዝርዎ ውስጥ እያንዳንዱ አገልግሎት ምን እንደሚያካትት ያብራሩ እና ተዛማጅ የስራ ምሳሌ ያክሉ።',
    'ask_review':
        'የቀጣዩን ስራ ካጠናቀቁ በኋላ ከደንበኛው ቅን ግምገማ ይጠይቁ፣ ስለ አገልግሎትዎ የበለጠ አስተማማኝ እይታ ለማግኘት።',
    'record': 'ውጤቶችን ከእይታዎችና ግምገማዎች ጋር ለመገምገም የተጠናቀቁ ስራዎችን ገቢ ያዘምኑ።',
    'retain':
        'ስለ ወደፊት ፍላጎቶች ከቀድሞ ደንበኛ ጋር ይነጋገሩ እና የአገልግሎት ዝርዝርዎንና የሚገኙበትን ጊዜ ያዘምኑ።',
  },
};
