import 'package:untitled1/services/movein_generator.dart';

class HeshinAccount {
  const HeshinAccount({
    required this.accountKey,
    required this.name,
    required this.taxId,
    required this.phone,
    required this.mobile,
    required this.address,
    required this.city,
    required this.zipCode,
    required this.email,
    required this.fax,
    required this.country,
    required this.bankCode,
    required this.bankBranch,
    required this.bankAccountNumber,
  });

  final String accountKey;
  final String name;
  final String taxId;
  final String phone;
  final String mobile;
  final String address;
  final String city;
  final String zipCode;
  final String email;
  final String fax;
  final String country;
  final String bankCode;
  final String bankBranch;
  final String bankAccountNumber;
}

class HeshinGeneratedFiles {
  const HeshinGeneratedFiles({
    required this.dataBytes,
    required this.parameterBytes,
    required this.accountCount,
  });

  final List<int> dataBytes;
  final List<int> parameterBytes;
  final int accountCount;
}

class HeshinGenerationException implements Exception {
  const HeshinGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HeshinGenerator {
  // The PRM maps the fields used by hiro into a compact fixed-width record.
  // Hashavshevet counts the trailing CRLF as part of the record size.
  static const int recordContentLength = 351;
  static const int recordLengthWithCrlf = 353;

  static HeshinGeneratedFiles generate({
    required List<HeshinAccount> accounts,
  }) {
    final records = <String>[];
    final usedKeys = <String>{};
    for (final account in accounts) {
      final key = _fit(account.accountKey, 15).trim();
      if (key.isEmpty) continue;
      if (!usedKeys.add(key)) {
        throw HeshinGenerationException(
          'More than one client uses accounting card "$key".',
        );
      }
      records.add(_record(account, key));
    }

    final dataText = records.isEmpty ? '' : '${records.join('\r\n')}\r\n';
    final prmText = '${_parameterLines.join('\r\n')}\r\n';
    return HeshinGeneratedFiles(
      dataBytes: MoveinGenerator.encodeWindows1255(dataText),
      parameterBytes: MoveinGenerator.encodeWindows1255(prmText),
      accountCount: records.length,
    );
  }

  static String _record(HeshinAccount account, String key) {
    final chars = List<String>.filled(recordContentLength, ' ');
    void put(int start, int end, String value, {bool numeric = false}) {
      final width = end - start + 1;
      final fitted = numeric ? _fitDigits(value, width) : _fit(value, width);
      for (var index = 0; index < width; index++) {
        chars[start - 1 + index] = fitted[index];
      }
    }

    put(1, 15, key);
    final name = _sanitize(account.name).trim();
    put(16, 65, name.isEmpty ? key : _visualHebrew(name));
    put(66, 95, account.phone);
    put(96, 145, _visualHebrew(account.address));
    put(146, 165, _visualHebrew(account.city));
    put(166, 170, account.zipCode, numeric: true);
    put(171, 185, 'Customer');
    put(186, 194, account.taxId, numeric: true);
    put(195, 244, account.email);
    put(245, 274, account.fax);
    put(275, 294, _visualHebrew(account.country));
    put(295, 324, account.mobile);
    put(325, 326, account.bankCode, numeric: true);
    put(327, 331, account.bankBranch, numeric: true);
    put(332, 351, account.bankAccountNumber, numeric: true);
    return chars.join();
  }

  static String _fit(String value, int width) {
    final sanitized = _sanitize(value);
    if (sanitized.length > width) return sanitized.substring(0, width);
    return sanitized.padRight(width, ' ');
  }

  static String _fitDigits(String value, int width) =>
      _fit(value.replaceAll(RegExp(r'\D'), ''), width);

  static String _sanitize(String value) =>
      value.replaceAll('\r', ' ').replaceAll('\n', ' ').runes.map((rune) {
        try {
          MoveinGenerator.encodeWindows1255(String.fromCharCode(rune));
          return String.fromCharCode(rune);
        } on MoveinGenerationException {
          return ' ';
        }
      }).join();

  static String _visualHebrew(String value) {
    final sanitized = _sanitize(value);
    if (!sanitized.runes.any((rune) => rune >= 0x05d0 && rune <= 0x05ea)) {
      return sanitized;
    }
    return sanitized.runes
        .toList(growable: false)
        .reversed
        .map(String.fromCharCode)
        .join();
  }

  // Lines 2-69 follow Hashavshevet's current HESHIN field order. A 0 0 range
  // deliberately omits a field for which hiro has no safe accounting value.
  static const _parameterLines = <String>[
    '353 ;גודל הרשומה',
    '1 15 ;מפתח חשבון',
    '16 65 ;שם חשבון',
    '0 0 ;קוד מיון',
    '0 0 ;חתך',
    '66 95 ;טלפון',
    '96 145 ;כתובת',
    '0 0 ;שכונה',
    '146 165 ;עיר',
    '166 170 ;מיקוד',
    '171 185 ;עיסוק',
    '0 0 ;העברה לרואה חשבון',
    '0 0 ;פרטים',
    '0 0 ;תאריך נוסף 1',
    '0 0 ;תאריך נוסף 2',
    '0 0 ;סכום נוסף 1',
    '0 0 ;סכום נוסף 2',
    '0 0 ;סכום נוסף 3',
    '0 0 ;סכום נוסף 4',
    '0 0 ;מקסימום אשראי',
    '0 0 ;מטבע מקסימום אשראי',
    '0 0 ;מקסימום אובליגו',
    '0 0 ;מטבע מקסימום אובליגו',
    '0 0 ;אחוז הנחה כללית',
    '0 0 ;הודעה ללקוח',
    '0 0 ;חשבון מרכז',
    '0 0 ;סוכן',
    '0 0 ;אחוז ניכוי במקור',
    '0 0 ;בתוקף עד תאריך',
    '186 194 ;מספר עוסק מורשה',
    '325 326 ;קוד בנק',
    '327 331 ;קוד סניף',
    '332 351 ;מספר חשבון בנק',
    '0 0 ;מכירות שנה קודמת',
    '0 0 ;מטבע מכירות שנה קודמת',
    '0 0 ;קניות שנה קודמת',
    '0 0 ;מטבע קניות שנה קודמת',
    '195 244 ;דואר אלקטרוני',
    '245 274 ;פקס',
    '275 294 ;מדינה',
    '0 0 ;קוד פיצול תשלומים',
    '0 0 ;פטור ממעמ',
    '0 0 ;חשבון הפרשים',
    '0 0 ;מטבע התחשבנות',
    '0 0 ;קוד מאזן',
    '0 0 ;איחור תשלומים',
    '0 0 ;קוד חשבון ראשי',
    '0 0 ;קוד תמחיר',
    '0 0 ;קובץ',
    '295 324 ;טלפון סלולרי',
    '0 0 ;אתר',
    '0 0 ;תיק מס הכנסה',
    '0 0 ;קו חלוקה',
    '0 0 ;מסמך סוגר בהפצה',
    '0 0 ;כתובת למסמכי יצוא',
    '0 0 ;מספר כרטיס אשראי',
    '0 0 ;תוקף כרטיס חודש',
    '0 0 ;תוקף כרטיס שנה',
    '0 0 ;תעודת זהות בעל הכרטיס',
    '0 0 ;טלפון בעל הכרטיס',
    '0 0 ;קוד אבטחה',
    '0 0 ;ארבע ספרות אחרונות',
    '0 0 ;קוד סעיף חשבונאי',
    '0 0 ;תעודת זהות או חברה',
    '0 0 ;תעודת זהות או חברה 2',
    '0 0 ;טלפון 1',
    '0 0 ;טלפון 2',
    '0 0 ;שם חשבון ראשי',
    '0 0 ;שם מאזן',
  ];
}
