import 'package:cloud_functions/cloud_functions.dart';

const taxAuthorityBusinessIdMismatchReason =
    'tax-authority-business-id-mismatch';

const _businessIdMismatchMessages = <String, String>{
  'en':
      'This action was not sent. The connected Tax Authority account belongs to a different business ID than the business verified in Hiro. Disconnect it and reconnect the Tax Authority account for the verified business, then try again on this same invoice. This invoice is still waiting for your decision—do not create a new invoice.',
  'he':
      'הפעולה לא נשלחה. חשבון רשות המסים שמחובר לאפליקציה שייך למספר עסק שונה ממספר העסק שאומת ב-Hiro. נתקו אותו וחברו מחדש את חשבון רשות המסים של העסק המאומת, ואז נסו שוב באותה חשבונית. החשבונית עדיין ממתינה לבחירה שלכם—אין ליצור חשבונית חדשה.',
  'ar':
      'لم يتم إرسال الإجراء. حساب سلطة الضرائب المتصل بالتطبيق مرتبط برقم منشأة مختلف عن رقم المنشأة الذي تم التحقق منه في Hiro. افصل الحساب وأعد ربط حساب سلطة الضرائب الخاص بالمنشأة الموثقة، ثم حاول مرة أخرى في الفاتورة نفسها. ما زالت هذه الفاتورة بانتظار قرارك—لا تنشئ فاتورة جديدة.',
  'ru':
      'Действие не было отправлено. Подключённая учётная запись Налогового управления привязана к другому номеру компании, а не к номеру, подтверждённому в Hiro. Отключите её и заново подключите учётную запись подтверждённой компании, затем повторите действие в этом же счёте. Счёт всё ещё ожидает вашего решения—не создавайте новый.',
  'am':
      'ድርጊቱ አልተላከም። ከመተግበሪያው ጋር የተገናኘው የግብር ባለሥልጣን መለያ በHiro ከተረጋገጠው የንግድ መለያ ቁጥር የተለየ ቁጥር ጋር ተገናኝቷል። መለያውን ያቋርጡ፣ ለተረጋገጠው ንግድ የግብር ባለሥልጣን መለያውን እንደገና ያገናኙ፣ ከዚያ በዚሁ ደረሰኝ ላይ እንደገና ይሞክሩ። ይህ ደረሰኝ አሁንም ውሳኔዎን እየጠበቀ ነው—አዲስ ደረሰኝ አይፍጠሩ።',
};

const _actionFailedMessages = <String, String>{
  'en': 'The action could not be completed. Please try again.',
  'he': 'לא ניתן היה להשלים את הפעולה. יש לנסות שוב.',
  'ar': 'تعذر إكمال الإجراء. حاول مرة أخرى.',
  'ru': 'Не удалось выполнить действие. Попробуйте ещё раз.',
  'am': 'ድርጊቱን ማጠናቀቅ አልተቻለም። እንደገና ይሞክሩ።',
};

String _forLocale(Map<String, String> messages, String languageCode) {
  return messages[languageCode] ?? messages['en']!;
}

String taxAuthorityBusinessIdMismatchMessage(String languageCode) {
  return _forLocale(_businessIdMismatchMessages, languageCode);
}

String taxAuthorityActionFailedMessage(String languageCode) {
  return _forLocale(_actionFailedMessages, languageCode);
}

String? localizedTaxAuthorityConnectionError(
  FirebaseFunctionsException error,
  String languageCode,
) {
  final details = error.details;
  final reason = details is Map ? details['reason']?.toString() : null;
  final message = error.message?.trim() ?? '';
  final isBusinessIdMismatch =
      reason == taxAuthorityBusinessIdMismatchReason ||
      message ==
          'Reconnect the Tax Authority account for your verified business ID.';
  if (!isBusinessIdMismatch) return null;
  return taxAuthorityBusinessIdMismatchMessage(languageCode);
}
