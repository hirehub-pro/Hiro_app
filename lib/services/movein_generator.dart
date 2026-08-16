class MoveinAccountingSettings {
  static const accountKeyNames = <String>[
    'generalRegister',
    'creditRegister',
    'cashRegister',
    'checksRegister',
    'transfersRegister',
    'transfersUsdRegister',
    'transfersEurRegister',
    'transfersGbpRegister',
    'transfersJpyRegister',
    'otherRegister',
    'paypalRegister',
    'bitRegister',
    'payboxRegister',
    'pepperRegister',
    'otherCreditRegister',
    'purchasesAccount',
    'inputVatAccount',
    'withholdingTaxAccount',
    'outputVatAccount',
    'incomeAccount',
    'exemptIncomeAccount',
    'casualCustomerAccount',
  ];

  static const defaultAccountKeys = <String, String>{
    'generalRegister': '1000',
    'creditRegister': '1001',
    'cashRegister': '1002',
    'checksRegister': '1003',
    'transfersRegister': '1004',
    'transfersUsdRegister': '0',
    'transfersEurRegister': '0',
    'transfersGbpRegister': '0',
    'transfersJpyRegister': '0',
    'otherRegister': '0',
    'paypalRegister': '0',
    'bitRegister': '0',
    'payboxRegister': '0',
    'pepperRegister': '0',
    'otherCreditRegister': '0',
    'purchasesAccount': '0',
    'inputVatAccount': '0',
    'withholdingTaxAccount': '2000',
    'outputVatAccount': '2001',
    'incomeAccount': '3000',
    'exemptIncomeAccount': '3001',
    'casualCustomerAccount': '4000',
  };

  final Map<String, String> accountKeys;
  final String recipientEmail;

  MoveinAccountingSettings({
    required Map<String, String> accountKeys,
    required this.recipientEmail,
  }) : accountKeys = {
         for (final name in accountKeyNames)
           name: (accountKeys[name] ?? defaultAccountKeys[name]!).trim(),
       };

  factory MoveinAccountingSettings.defaults({String recipientEmail = ''}) {
    return MoveinAccountingSettings(
      accountKeys: defaultAccountKeys,
      recipientEmail: recipientEmail,
    );
  }

  factory MoveinAccountingSettings.fromMap(
    Map<String, dynamic>? value, {
    String fallbackEmail = '',
  }) {
    final rawKeys = value?['accountKeys'];
    final keys = rawKeys is Map
        ? rawKeys.map(
            (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
          )
        : const <String, String>{};
    return MoveinAccountingSettings(
      accountKeys: keys,
      recipientEmail: (value?['recipientEmail'] ?? fallbackEmail).toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'accountKeys': accountKeys,
    'recipientEmail': recipientEmail.trim(),
  };

  String account(String name) => (accountKeys[name] ?? '').trim();
}

class MoveinPayment {
  final String method;
  final double amount;

  const MoveinPayment({required this.method, required this.amount});
}

class MoveinSourceDocument {
  final String documentType;
  final String reference;
  final String issueDate;
  final String dueDate;
  final String clientAccountKey;
  final String clientTaxId;
  final double totalAmount;
  final double vatAmount;
  final String allocationNumber;
  final List<MoveinPayment> payments;

  const MoveinSourceDocument({
    required this.documentType,
    required this.reference,
    required this.issueDate,
    required this.dueDate,
    required this.clientAccountKey,
    required this.clientTaxId,
    required this.totalAmount,
    required this.vatAmount,
    required this.allocationNumber,
    required this.payments,
  });
}

class MoveinGeneratedFiles {
  final List<int> documentBytes;
  final List<int> parameterBytes;
  final int recordCount;

  const MoveinGeneratedFiles({
    required this.documentBytes,
    required this.parameterBytes,
    required this.recordCount,
  });
}

class MoveinGenerationException implements Exception {
  final String message;

  const MoveinGenerationException(this.message);

  @override
  String toString() => message;
}

class MoveinGenerator {
  static const int recordContentLength = 524;
  static const int recordLengthWithCrlf = 526;

  static MoveinGeneratedFiles generate({
    required List<MoveinSourceDocument> documents,
    required MoveinAccountingSettings settings,
  }) {
    _validateSettings(settings);
    final records = <String>[];

    for (final document in documents) {
      switch (document.documentType) {
        case 'invoice':
          records.add(_invoiceRecord(document, settings));
        case 'credit_note':
          records.add(_creditNoteRecord(document, settings));
        case 'invoice_receipt':
          records.add(_invoiceReceiptRecord(document, settings));
          records.addAll(_paymentRecords(document, settings));
        case 'receipt':
          records.addAll(_paymentRecords(document, settings));
      }
    }

    if (records.isEmpty) {
      throw const MoveinGenerationException(
        'No accounting journal records were found for the selected period.',
      );
    }

    final docText = '${records.join('\r\n')}\r\n';
    final prmText = '${_parameterLines.join('\r\n')}\r\n';
    return MoveinGeneratedFiles(
      documentBytes: encodeWindows1255(docText),
      parameterBytes: encodeWindows1255(prmText),
      recordCount: records.length,
    );
  }

  static String _invoiceRecord(
    MoveinSourceDocument document,
    MoveinAccountingSettings settings,
  ) {
    final total = document.totalAmount.abs();
    final vat = document.vatAmount.abs().clamp(0, total).toDouble();
    final income = total - vat;
    return _record(
      transactionType: 'לח',
      document: document,
      description: 'חשבונית מס מכירה',
      debitAccount1: _customerAccount(document, settings),
      creditAccount1: _incomeAccount(vat, settings),
      creditAccount2: vat > 0 ? settings.account('outputVatAccount') : '',
      debitAmount1: total,
      creditAmount1: income,
      creditAmount2: vat,
    );
  }

  static String _invoiceReceiptRecord(
    MoveinSourceDocument document,
    MoveinAccountingSettings settings,
  ) {
    final total = document.totalAmount.abs();
    final vat = document.vatAmount.abs().clamp(0, total).toDouble();
    final income = total - vat;
    return _record(
      transactionType: 'קשח',
      document: document,
      description: 'חשבונית מס קבלה-חיוב לקוח',
      debitAccount1: _customerAccount(document, settings),
      creditAccount1: _incomeAccount(vat, settings),
      creditAccount2: vat > 0 ? settings.account('outputVatAccount') : '',
      debitAmount1: total,
      creditAmount1: income,
      creditAmount2: vat,
    );
  }

  static String _creditNoteRecord(
    MoveinSourceDocument document,
    MoveinAccountingSettings settings,
  ) {
    final total = document.totalAmount.abs();
    final vat = document.vatAmount.abs().clamp(0, total).toDouble();
    final income = total - vat;
    return _record(
      transactionType: 'לז',
      document: document,
      description: 'חשבונית מס זיכוי',
      debitAccount1: _incomeAccount(vat, settings),
      debitAccount2: vat > 0 ? settings.account('outputVatAccount') : '',
      creditAccount1: _customerAccount(document, settings),
      debitAmount1: income,
      debitAmount2: vat,
      creditAmount1: total,
    );
  }

  static List<String> _paymentRecords(
    MoveinSourceDocument document,
    MoveinAccountingSettings settings,
  ) {
    final payments = document.payments
        .where((payment) => payment.amount.abs() >= 0.005)
        .toList();
    if (payments.isEmpty) {
      throw MoveinGenerationException(
        'Document ${document.reference} has no payment amounts.',
      );
    }

    final records = <String>[];
    var paymentTotal = 0.0;
    for (final payment in payments) {
      final amount = payment.amount.abs();
      paymentTotal += amount;
      records.add(
        _record(
          transactionType: '',
          document: document,
          description: _paymentDescription(payment.method),
          debitAccount1: _paymentAccount(payment.method, settings),
          debitAmount1: amount,
        ),
      );
    }
    records.add(
      _record(
        transactionType: '',
        document: document,
        description: 'קבלה-זיכוי לקוח',
        creditAccount1: _customerAccount(document, settings),
        creditAmount1: paymentTotal,
      ),
    );
    return records;
  }

  static String _record({
    required String transactionType,
    required MoveinSourceDocument document,
    required String description,
    String debitAccount1 = '',
    String debitAccount2 = '',
    String creditAccount1 = '',
    String creditAccount2 = '',
    double debitAmount1 = 0,
    double debitAmount2 = 0,
    double creditAmount1 = 0,
    double creditAmount2 = 0,
  }) {
    final chars = List<String>.filled(recordContentLength, ' ');
    void put(int start, int end, String value) {
      final width = end - start + 1;
      final fitted = _fit(value, width);
      for (var index = 0; index < width; index++) {
        chars[start - 1 + index] = fitted[index];
      }
    }

    put(1, 3, transactionType);
    put(5, 13, _digits(document.reference));
    put(15, 23, '');
    put(25, 34, _displayDate(document.issueDate));
    put(36, 45, _displayDate(document.dueDate));
    put(47, 51, '1');
    put(53, 102, _visualHebrew(description));
    put(104, 118, debitAccount1);
    put(120, 134, debitAccount2);
    put(136, 150, creditAccount1);
    put(152, 166, creditAccount2);
    put(168, 178, _amount(debitAmount1));
    put(180, 190, _amount(debitAmount2));
    put(192, 202, _amount(creditAmount1));
    put(204, 214, _amount(creditAmount2));
    put(216, 226, _amount(0));
    put(228, 238, _amount(0));
    put(240, 250, _amount(0));
    put(252, 262, _amount(0));
    put(264, 272, _digits(document.clientTaxId));
    put(274, 523, _digits(document.allocationNumber));
    return chars.join();
  }

  static void _validateSettings(MoveinAccountingSettings settings) {
    for (final key in MoveinAccountingSettings.accountKeyNames) {
      final value = settings.account(key);
      if (value.isEmpty || value.length > 15) {
        throw MoveinGenerationException(
          'Accounting card "$key" must contain 1 to 15 characters.',
        );
      }
    }
  }

  static String _customerAccount(
    MoveinSourceDocument document,
    MoveinAccountingSettings settings,
  ) {
    final value = document.clientAccountKey.trim();
    return value.isNotEmpty ? value : settings.account('casualCustomerAccount');
  }

  static String _incomeAccount(double vat, MoveinAccountingSettings settings) =>
      settings.account(vat > 0 ? 'incomeAccount' : 'exemptIncomeAccount');

  static String _paymentAccount(
    String method,
    MoveinAccountingSettings settings,
  ) {
    final name = switch (method) {
      'cash' => 'cashRegister',
      'credit' => 'creditRegister',
      'check' => 'checksRegister',
      'transfer' => 'transfersRegister',
      'bit' => 'bitRegister',
      'paybox' => 'payboxRegister',
      'withholding_tax' => 'withholdingTaxAccount',
      _ => 'otherRegister',
    };
    final selected = settings.account(name);
    if (selected.isNotEmpty && selected != '0') return selected;
    final fallback = settings.account('generalRegister');
    if (fallback.isEmpty || fallback == '0') {
      throw MoveinGenerationException(
        'No accounting card is configured for payment method "$method".',
      );
    }
    return fallback;
  }

  static String _paymentDescription(String method) => switch (method) {
    'cash' => 'קבלה-מזומן-חובה',
    'credit' => 'קבלה-אשראי-חובה',
    'check' => 'קבלה-המחאות-חובה',
    'transfer' => 'קבלה-העברה-חובה',
    'bit' => 'קבלה-ביט-חובה',
    'paybox' => 'קבלה-פייבוקס-חובה',
    'withholding_tax' => 'קבלה-ניכוי מס-חובה',
    _ => 'קבלה-אחר-חובה',
  };

  static String _fit(String value, int width) {
    final sanitized = _sanitize(value);
    if (sanitized.length > width) return sanitized.substring(0, width);
    return sanitized.padRight(width, ' ');
  }

  static String _sanitize(String value) {
    return value
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .runes
        .map(
          (rune) =>
              _windows1255Byte(rune) == null ? ' ' : String.fromCharCode(rune),
        )
        .join();
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static String _amount(double value) {
    final formatted = value.abs().toStringAsFixed(2);
    if (formatted.length > 11) {
      throw MoveinGenerationException(
        'Amount $formatted exceeds MOVEIN width.',
      );
    }
    return formatted;
  }

  static String _displayDate(String compactDate) {
    final digits = _digits(compactDate);
    if (digits.length != 8) {
      throw MoveinGenerationException('Invalid MOVEIN date "$compactDate".');
    }
    final year = int.tryParse(digits.substring(0, 4));
    final month = int.tryParse(digits.substring(4, 6));
    final day = int.tryParse(digits.substring(6, 8));
    if (year == null || month == null || day == null) {
      throw MoveinGenerationException('Invalid MOVEIN date "$compactDate".');
    }
    final parsed = DateTime.tryParse(
      '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}',
    );
    if (parsed == null ||
        parsed.year != year ||
        parsed.month != month ||
        parsed.day != day) {
      throw MoveinGenerationException('Invalid MOVEIN date "$compactDate".');
    }
    return '${digits.substring(6, 8)}/${digits.substring(4, 6)}/${digits.substring(2, 4)}';
  }

  static String _visualHebrew(String value) => value.runes
      .toList(growable: false)
      .reversed
      .map(String.fromCharCode)
      .join();

  static List<int> encodeWindows1255(String value) {
    return value.runes
        .map((rune) {
          final byte = _windows1255Byte(rune);
          if (byte == null) {
            throw MoveinGenerationException(
              'Character U+${rune.toRadixString(16).toUpperCase()} cannot be encoded in Windows-1255.',
            );
          }
          return byte;
        })
        .toList(growable: false);
  }

  static int? _windows1255Byte(int rune) {
    if (rune <= 0x7f) return rune;
    if (rune >= 0x05d0 && rune <= 0x05ea) return 0xe0 + (rune - 0x05d0);
    return const <int, int>{
      0x00a0: 0xa0,
      0x00b0: 0xb0,
      0x00d7: 0xaa,
      0x00f7: 0xba,
      0x05be: 0xbe,
      0x05f3: 0xd4,
      0x05f4: 0xd5,
      0x20aa: 0xa4,
      0x2013: 0x96,
      0x2014: 0x97,
      0x2018: 0x91,
      0x2019: 0x92,
      0x201c: 0x93,
      0x201d: 0x94,
    }[rune];
  }

  static const _parameterLines = <String>[
    '526 ;גודל הרשומה',
    '1 3 ;קוד סוג תנועה',
    '5 13 ;אסמכתא',
    '15 23 ;אסמכתא 2',
    '25 34 ;תאריך אסמכתא ',
    '36 45 ;תאריך ערך',
    '0 0 ;תמחיר',
    '47 51 ;קוד מטבע',
    '53 102 ;פרוט',
    '104 118 ;מס חשבון חובה 1',
    '120 134 ;מס חשבון חובה 2',
    '136 150 ;מס חשבון זכות 1',
    '152 166 ;מס חשבון זכות 2',
    '168 178 ;סכום חובה 1 בש"ח',
    '180 190 ;סכום חובה 2 בש"ח',
    '192 202 ;סכום זכות 1 בש"ח',
    '204 214 ;סכום זכות 2 בש"ח',
    '216 226 ;סכום חובה 1 מט"ח',
    '228 238 ;סכום חובה 2 מט"ח',
    '240 250 ;סכום זכות 1 מט"ח',
    '252 262 ;סכום זכות 2 מט"ח',
    '0 0 ;תאריך שלישי',
    '0 0 ;אסמכתא 3',
    '0 0 ;כמות',
    '0 0 ;קובץ',
    '0 0 ;הערות נוספות',
    '0 0 ;הערות נוספות 2',
    '0 0 ;סניף',
    '264 272 ;מספר ע.מ.',
    '0 0 ;לא בשימוש',
    '0 0 ;אסמכתא 4',
    '0 0 ;אסמכתא 5',
    '0 0 ;תאריך 4',
    '0 0 ;תאריך 5',
    '274 523 ;מספר הקצאה',
  ];
}
