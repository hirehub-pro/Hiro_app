class ProfessionLocalization {
  static const List<String> canonicalProfessions = [
    'Plumber',
    'Carpenter',
    'Electrician',
    'Painter',
    'Cleaner',
    'Handyman',
    'Landscaper',
    'HVAC',
    'Locksmith',
    'Gardener',
    'Mechanic',
    'Photographer',
    'Tutor',
    'Tailor',
    'Mover',
    'Interior Designer',
    'Beautician',
    'Pet Groomer',
    'Welder',
    'Roofer',
    'Flooring Expert',
    'AC Technician',
    'Pest Control',
  ];

  static const Map<String, Map<String, String>> _labels = {
    'en': {
      'Plumber': 'Plumber',
      'Carpenter': 'Carpenter',
      'Electrician': 'Electrician',
      'Painter': 'Painter',
      'Cleaner': 'Cleaner',
      'Handyman': 'Handyman',
      'Landscaper': 'Landscaper',
      'HVAC': 'HVAC',
      'Locksmith': 'Locksmith',
      'Gardener': 'Gardener',
      'Mechanic': 'Mechanic',
      'Photographer': 'Photographer',
      'Tutor': 'Tutor',
      'Tailor': 'Tailor',
      'Mover': 'Mover',
      'Interior Designer': 'Interior Designer',
      'Beautician': 'Beautician',
      'Pet Groomer': 'Pet Groomer',
      'Welder': 'Welder',
      'Roofer': 'Roofer',
      'Flooring Expert': 'Flooring Expert',
      'AC Technician': 'AC Technician',
      'Pest Control': 'Pest Control',
    },
    'he': {
      'Plumber': 'אינסטלטור',
      'Carpenter': 'נגר',
      'Electrician': 'חשמלאי',
      'Painter': 'צבעי',
      'Cleaner': 'מנקה',
      'Handyman': 'הנדימן',
      'Landscaper': 'גנן נוף',
      'HVAC': 'טכנאי מיזוג אוויר',
      'Locksmith': 'מנעולן',
      'Gardener': 'גנן',
      'Mechanic': 'מכונאי',
      'Photographer': 'צלם',
      'Tutor': 'מורה פרטי',
      'Tailor': 'חייט',
      'Mover': 'מוביל',
      'Interior Designer': 'מעצב פנים',
      'Beautician': 'קוסמטיקאית',
      'Pet Groomer': 'ספר חיות מחמד',
      'Welder': 'רתך',
      'Roofer': 'גגן',
      'Flooring Expert': 'מומחה ריצוף',
      'AC Technician': 'טכנאי מזגנים',
      'Pest Control': 'מדביר',
    },
    'ar': {
      'Plumber': 'سباك',
      'Carpenter': 'نجار',
      'Electrician': 'كهربائي',
      'Painter': 'دهان',
      'Cleaner': 'عامل تنظيف',
      'Handyman': 'فني صيانة',
      'Landscaper': 'منسق حدائق',
      'HVAC': 'فني تكييف وتدفئة',
      'Locksmith': 'حداد أقفال',
      'Gardener': 'بستاني',
      'Mechanic': 'ميكانيكي',
      'Photographer': 'مصور',
      'Tutor': 'مدرس خصوصي',
      'Tailor': 'خياط',
      'Mover': 'عامل نقل',
      'Interior Designer': 'مصمم داخلي',
      'Beautician': 'خبيرة تجميل',
      'Pet Groomer': 'مصفف حيوانات أليفة',
      'Welder': 'لحام',
      'Roofer': 'عامل أسقف',
      'Flooring Expert': 'خبير أرضيات',
      'AC Technician': 'فني تكييف',
      'Pest Control': 'مكافحة آفات',
    },
  };

  static String _normalizeLocale(String localeCode) {
    if (_labels.containsKey(localeCode)) return localeCode;
    return 'en';
  }

  static String toCanonical(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;

    for (final canonical in canonicalProfessions) {
      if (canonical.toLowerCase() == trimmed.toLowerCase()) {
        return canonical;
      }
    }

    for (final localeLabels in _labels.values) {
      for (final entry in localeLabels.entries) {
        if (entry.value.toLowerCase() == trimmed.toLowerCase()) {
          return entry.key;
        }
      }
    }

    return trimmed;
  }

  static String toLocalized(String value, String localeCode) {
    final canonical = toCanonical(value);
    final locale = _normalizeLocale(localeCode);
    return _labels[locale]?[canonical] ?? canonical;
  }

  static List<String> localizedOptions(String localeCode) {
    final locale = _normalizeLocale(localeCode);
    final labels = _labels[locale] ?? _labels['en']!;
    return canonicalProfessions
        .map((canonical) => labels[canonical] ?? canonical)
        .toList(growable: false);
  }
}
