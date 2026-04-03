import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AveragePricesPage extends StatefulWidget {
  final String? initialProfession;
  final String? proPhoneNumber;
  final String? proName;

  const AveragePricesPage({
    super.key,
    this.initialProfession,
    this.proPhoneNumber,
    this.proName,
  });

  @override
  State<AveragePricesPage> createState() => _AveragePricesPageState();
}

class _AveragePricesPageState extends State<AveragePricesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = "";
  Map<String, dynamic>? _selectedProfession;
  List<Map<String, dynamic>> _allProfessions = [];
  List<Map<String, dynamic>> _filteredProfessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final metadataDoc = await _firestore
          .collection('metadata')
          .doc('professions')
          .get();
      final items = (metadataDoc.data()?['items'] as List?) ?? const [];
      final professions =
          items
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
            ..sort((a, b) {
              final aId = int.tryParse(a['id']?.toString() ?? '') ?? 1 << 30;
              final bId = int.tryParse(b['id']?.toString() ?? '') ?? 1 << 30;
              return aId.compareTo(bId);
            });

      setState(() {
        _allProfessions = professions;
        _filteredProfessions = professions;
        _isLoading = false;

        if (widget.initialProfession != null) {
          _selectedProfession = professions.firstWhere(
            (p) =>
                p['en'].toString().toLowerCase() ==
                widget.initialProfession!.toLowerCase(),
            orElse: () => {},
          );
          if (_selectedProfession?.isEmpty ?? true) _selectedProfession = null;
        }
      });
    } catch (e) {
      debugPrint("Error loading price data: $e");
      setState(() => _isLoading = false);
    }
  }

  void _filterProfessions(String query) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredProfessions = _allProfessions.where((p) {
        final name = (p[locale] ?? p['en']).toString().toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    });
  }

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1976D2);
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) hexColor = "FF$hexColor";
    return Color(int.parse(hexColor, radix: 16));
  }

  List<Map<String, String>> _getTasksForProfession(
    Map<String, dynamic> prof,
    String locale,
  ) {
    final isHe = locale == 'he';
    final isAr = locale == 'ar';
    final isRu = locale == 'ru';
    final isAm = locale == 'am';

    final String enName = prof['en'].toString().toLowerCase();

    // Customized tasks for major professions
    if (enName.contains('plumber')) {
      return [
        {
          'task': isHe
              ? 'פתיחת סתימה'
              : (isAr
                    ? 'تسليك مجاري'
                    : (isRu
                          ? 'Устранение засора'
                          : (isAm ? 'ቧንቧ መክፈት' : 'Unclogging Drain'))),
          'price': '250 - 450 ₪',
          'time': '30-60 min',
        },
        {
          'task': isHe
              ? 'החלפת ברז'
              : (isAr
                    ? 'استبدال صنبور'
                    : (isRu
                          ? 'Замена крана'
                          : (isAm ? 'ቧንቧ መቀየር' : 'Faucet Replacement'))),
          'price': '300 - 550 ₪',
          'time': '45-90 min',
        },
        {
          'task': isHe
              ? 'תיקון ניאגרה'
              : (isAr
                    ? 'إصلاح صندوق الطرد'
                    : (isRu
                          ? 'Ремонт бачка'
                          : (isAm ? 'ፍላሽ ማስተካከል' : 'Toilet Flush Repair'))),
          'price': '250 - 500 ₪',
          'time': '1 hour',
        },
        {
          'task': isHe
              ? 'התקנת דוד שמש'
              : (isAr
                    ? 'تركيب سخان شمسي'
                    : (isRu
                          ? 'Установка бойлера'
                          : (isAm ? 'ሶላር መግጠም' : 'Solar Heater Install'))),
          'price': '2500 - 4500 ₪',
          'time': '3-5 hours',
        },
      ];
    }
    if (enName.contains('electrician')) {
      return [
        {
          'task': isHe
              ? 'התקנת שקע'
              : (isAr
                    ? 'تركيب مقبس'
                    : (isRu
                          ? 'Установка розетки'
                          : (isAm ? 'ሶኬት መግጠም' : 'Socket Installation'))),
          'price': '150 - 300 ₪',
          'time': '30-60 min',
        },
        {
          'task': isHe
              ? 'החלפת מפסק'
              : (isAr
                    ? 'استبدال قاطع'
                    : (isRu
                          ? 'Замена автомата'
                          : (isAm ? 'መቀያየር መቀየር' : 'Breaker Replacement'))),
          'price': '250 - 500 ₪',
          'time': '45-90 min',
        },
        {
          'task': isHe
              ? 'לוח חשמל'
              : (isAr
                    ? 'لوحة كهرباء'
                    : (isRu
                          ? 'Электрощит'
                          : (isAm ? 'የኤሌክትሪክ ሳጥን' : 'Electrical Board'))),
          'price': '2500 - 5000 ₪',
          'time': '1-2 days',
        },
      ];
    }
    if (enName.contains('metalworker') || enName.contains('blacksmith')) {
      return [
        {
          'task': isHe
              ? 'תיקון סורג'
              : (isAr
                    ? 'إصلاح حماية نافذة'
                    : (isRu
                          ? 'Ремонт решетки'
                          : (isAm ? 'ግሪል ማስተካከል' : 'Grille Repair'))),
          'price': '300 - 600 ₪',
          'time': '1-2 hours',
        },
        {
          'task': isHe
              ? 'התקנת שער'
              : (isAr
                    ? 'تركيب بوابة'
                    : (isRu
                          ? 'Установка ворот'
                          : (isAm ? 'በር መግጠም' : 'Gate Installation'))),
          'price': '1500 - 4000 ₪',
          'time': '1-2 days',
        },
      ];
    }

    // Generic tasks for all other professions in the JSON
    return [
      {
        'task': isHe
            ? 'ביקור וייעוץ'
            : (isAr
                  ? 'زيارة واستشارة'
                  : (isRu
                        ? 'Консультация'
                        : (isAm ? 'ምክርና ጉብኝት' : 'Consultation Visit'))),
        'price': '150 - 250 ₪',
        'time': '30 min',
      },
      {
        'task': isHe
            ? 'עבודה בסיסית'
            : (isAr
                  ? 'عمل أساسي'
                  : (isRu
                        ? 'Базовая работа'
                        : (isAm ? 'መሰረታዊ ስራ' : 'Basic Work'))),
        'price': '300 - 600 ₪',
        'time': '1-2 hours',
      },
      {
        'task': isHe
            ? 'פרויקט מורכב'
            : (isAr
                  ? 'مشروع معقد'
                  : (isRu
                        ? 'Сложный проект'
                        : (isAm ? 'ውስብስብ ስራ' : 'Complex Project'))),
        'price': '1000+ ₪',
        'time': '1+ days',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final themeColor = _selectedProfession != null
        ? _getColorFromHex(_selectedProfession!['color'])
        : const Color(0xFF1976D2);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            _selectedProfession != null
                ? (_selectedProfession![locale] ?? _selectedProfession!['en'])
                : (locale == 'he' ? 'מחירון שירותים' : 'Price Guide'),
          ),
          backgroundColor: themeColor,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: _selectedProfession != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => setState(() => _selectedProfession = null),
                )
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_selectedProfession == null)
                    _buildProfessionsList(locale, themeColor)
                  else
                    _buildDetailsView(_selectedProfession!, locale, themeColor),
                ],
              ),
        floatingActionButton:
            widget.proPhoneNumber != null && _selectedProfession != null
            ? FloatingActionButton.extended(
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${widget.proPhoneNumber}')),
                backgroundColor: const Color(0xFF22C55E),
                icon: const Icon(Icons.call, color: Colors.white),
                label: Text(
                  widget.proName ?? (locale == 'he' ? 'התקשר' : 'Call'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildProfessionsList(String locale, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
            ),
            child: TextField(
              onChanged: _filterProfessions,
              decoration: InputDecoration(
                hintText: locale == 'he'
                    ? 'חפש מקצוע...'
                    : 'Search profession...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _filteredProfessions.length,
              itemBuilder: (context, index) {
                final p = _filteredProfessions[index];
                final profColor = _getColorFromHex(p['color']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: profColor.withOpacity(0.1),
                      child: Icon(_getIcon(p['logo']), color: profColor),
                    ),
                    title: Text(
                      p[locale] ?? p['en'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => setState(() => _selectedProfession = p),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsView(
    Map<String, dynamic> prof,
    String locale,
    Color color,
  ) {
    final tasks = _getTasksForProfession(prof, locale);
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final t = tasks[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['task']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _infoPill(
                      Icons.payments_rounded,
                      t['price']!,
                      Colors.green,
                    ),
                    const SizedBox(width: 12),
                    _infoPill(Icons.timer_rounded, t['time']!, Colors.blue),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoPill(IconData icon, String val, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                val,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String? name) {
    switch (name) {
      case 'plumbing':
        return Icons.plumbing;
      case 'electrical_services':
        return Icons.electrical_services;
      case 'carpenter':
        return Icons.carpenter;
      case 'format_paint':
        return Icons.format_paint;
      case 'vpn_key':
        return Icons.vpn_key;
      case 'park':
        return Icons.park;
      case 'ac_unit':
        return Icons.ac_unit;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'build':
        return Icons.build;
      case 'handyman':
        return Icons.handyman;
      case 'foundation':
        return Icons.foundation;
      case 'grid_view':
        return Icons.grid_view;
      case 'settings':
        return Icons.settings;
      case 'home_repair_service':
        return Icons.home_repair_service;
      case 'computer':
        return Icons.computer;
      case 'content_cut':
        return Icons.content_cut;
      case 'checkroom':
        return Icons.checkroom;
      case 'local_shipping':
        return Icons.local_shipping;
      case 'pest_control':
        return Icons.pest_control;
      case 'solar_power':
        return Icons.solar_power;
      case 'chair':
        return Icons.chair;
      case 'format_shapes':
        return Icons.format_shapes;
      case 'architecture':
        return Icons.architecture;
      case 'school':
        return Icons.school;
      case 'child_care':
        return Icons.child_care;
      case 'photo_camera':
        return Icons.photo_camera;
      case 'music_note':
        return Icons.music_note;
      case 'face':
        return Icons.face;
      case 'medical_services':
        return Icons.medical_services;
      case 'self_improvement':
        return Icons.self_improvement;
      case 'window':
        return Icons.window;
      case 'pool':
        return Icons.pool;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'pets':
        return Icons.pets;
      case 'home':
        return Icons.home;
      case 'waves':
        return Icons.waves;
      case 'dry_cleaning':
        return Icons.dry_cleaning;
      case 'event':
        return Icons.event;
      case 'restaurant':
        return Icons.restaurant;
      case 'security':
        return Icons.security;
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'local_car_wash':
        return Icons.local_car_wash;
      case 'spa':
        return Icons.spa;
      case 'restaurant_menu':
        return Icons.restaurant_menu;
      case 'flight':
        return Icons.flight;
      case 'real_estate_agent':
        return Icons.real_estate_agent;
      case 'gavel':
        return Icons.gavel;
      case 'calculate':
        return Icons.calculate;
      case 'translate':
        return Icons.translate;
      case 'format_color_fill':
        return Icons.format_color_fill;
      case 'square_foot':
        return Icons.square_foot;
      case 'videocam':
        return Icons.videocam;
      case 'public':
        return Icons.public;
      case 'psychology':
        return Icons.psychology;
      case 'add_a_photo':
        return Icons.add_a_photo;
      case 'flight_takeoff':
        return Icons.flight_takeoff;
      case 'piano':
        return Icons.piano;
      case 'language':
        return Icons.language;
      case 'functions':
        return Icons.functions;
      case 'science':
        return Icons.science;
      case 'biotech':
        return Icons.biotech;
      case 'eco':
        return Icons.eco;
      case 'history_edu':
        return Icons.history_edu;
      case 'palette':
        return Icons.palette;
      case 'pedal_bike':
        return Icons.pedal_bike;
      case 'engineering':
        return Icons.engineering;
      default:
        return Icons.work_rounded;
    }
  }
}
