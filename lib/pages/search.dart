import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/average_prices.dart';

class SearchPage extends StatefulWidget {
  final String? initialTrade;
  const SearchPage({super.key, this.initialTrade});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _allWorkers = [];
  List<Map<String, dynamic>> _filteredWorkers = [];
  List<Map<String, dynamic>> _professions = [];
  List<Map<String, dynamic>> _filteredProfessions = [];
  bool _isLoadingWorkers = true;
  bool _isLoadingProfessions = true;

  Map<String, dynamic>? _selectedProfession;
  bool _showWorkerList = false;
  String _sortBy = 'rating';
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadProfessions();
    _fetchWorkers();
  }

  Future<void> _loadProfessions() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/profeissions.json',
      );
      final List<dynamic> data = json.decode(response);
      setState(() {
        _professions = data.cast<Map<String, dynamic>>();
        _filteredProfessions = _professions;
        _isLoadingProfessions = false;

        if (widget.initialTrade != null) {
          final initial = _professions.firstWhere(
            (p) =>
                p['en'].toString().toLowerCase() ==
                widget.initialTrade!.toLowerCase(),
            orElse: () => {},
          );
          if (initial.isNotEmpty) {
            _selectedProfession = initial;
            _showWorkerList = true;
          }
        }
      });
    } catch (e) {
      debugPrint("Error loading professions: $e");
      setState(() => _isLoadingProfessions = false);
    }
  }

  Future<void> _fetchWorkers() async {
    if (!mounted) return;
    setState(() => _isLoadingWorkers = true);
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('userType', isEqualTo: 'worker')
          .get();

      final workers = snapshot.docs.map((doc) {
        final data = doc.data();
        data['uid'] = doc.id;

        if (data['avgRating'] == null) {
          data['avgRating'] = 0.0;
          data['reviewCount'] = 0;
        }

        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _allWorkers = workers;
          _applyFilters();
          _isLoadingWorkers = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWorkers = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are not enabled.
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        return;
      } 

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _sortBy = 'distance';
        _applyFilters();
      });
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;

    setState(() {
      if (_showWorkerList) {
        _filteredWorkers = _allWorkers.where((w) {
          final matchesTrade =
              _selectedProfession == null ||
              _getProfessionsList(w)
                  .map((e) => e.toLowerCase())
                  .contains(
                    _selectedProfession!['en'].toString().toLowerCase(),
                  );
          final matchesSearch =
              query.isEmpty ||
              (w['name'] ?? '').toLowerCase().contains(query) ||
              (w['town'] ?? '').toLowerCase().contains(query);
          return matchesTrade && matchesSearch;
        }).toList();

        if (_sortBy == 'rating') {
<<<<<<< HEAD
          _filteredWorkers.sort(
            (a, b) => (b['avgRating'] as num).compareTo(a['avgRating'] as num),
          );
=======
          _filteredWorkers.sort((a, b) => (b['avgRating'] as num).compareTo(a['avgRating'] as num));
        } else if (_sortBy == 'distance' && _currentPosition != null) {
          _filteredWorkers.sort((a, b) {
            double latA = a['lat'] ?? 0.0;
            double lngA = a['lng'] ?? 0.0;
            double latB = b['lat'] ?? 0.0;
            double lngB = b['lng'] ?? 0.0;
            
            if (latA == 0 && lngA == 0) return 1;
            if (latB == 0 && lngB == 0) return -1;

            double distA = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, latA, lngA);
            double distB = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, latB, lngB);
            return distA.compareTo(distB);
          });
>>>>>>> 7b713a42c7ae1f5bb5a752aedffb0ab40640f752
        } else {
          _filteredWorkers.sort(
            (a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''),
          );
        }
      } else {
        _filteredProfessions = _professions.where((p) {
          final name = (p[locale] ?? p['en']).toString().toLowerCase();
          final enName = p['en'].toString().toLowerCase();
          return name.contains(query) || enName.contains(query);
        }).toList();
      }
    });
  }

  Color _getThemeColor() {
    if (_showWorkerList && _selectedProfession != null) {
      return _getColorFromHex(_selectedProfession!['color']);
    }
    return const Color(0xFF1E3A8A);
  }

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1E3A8A);
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final themeColor = _getThemeColor();

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: themeColor,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: _showWorkerList
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () {
                    setState(() {
                      _showWorkerList = false;
                      _selectedProfession = null;
                      _searchController.clear();
                      _applyFilters();
                    });
                  },
                )
              : null,
          title: Text(
            _showWorkerList
                ? (_selectedProfession![locale] ?? _selectedProfession!['en'])
                : (locale == 'he' ? 'בחר מקצוע' : 'Choose Profession'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          actions: [
            if (_showWorkerList)
              IconButton(
                icon: const Icon(Icons.price_change_outlined),
                tooltip: locale == 'he' ? 'מחירון' : 'Price Guide',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AveragePricesPage(
                      initialProfession: _selectedProfession!['en'],
                    ),
                  ),
                ),
              ),
            if (_showWorkerList)
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => _showSortOptions(locale, themeColor),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchHeader(locale, themeColor),
            Expanded(
              child: _showWorkerList
                  ? (_isLoadingWorkers
                        ? const Center(child: CircularProgressIndicator())
                        : _buildWorkerList(locale, themeColor))
                  : (_isLoadingProfessions
                        ? const Center(child: CircularProgressIndicator())
                        : _buildProfessionGrid(locale)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader(String locale, Color themeColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      decoration: BoxDecoration(
        color: themeColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => _applyFilters(),
        decoration: InputDecoration(
          hintText: _showWorkerList
              ? (locale == 'he'
                    ? 'חפש לפי שם או עיר...'
                    : 'Search by name or city...')
              : (locale == 'he' ? 'חפש מקצוע...' : 'Search profession...'),
          prefixIcon: Icon(Icons.search_rounded, color: themeColor),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildProfessionGrid(String locale) {
    if (_filteredProfessions.isEmpty) {
      return Center(
        child: Text(
          locale == 'he' ? 'לא נמצאו מקצועות' : 'No professions found',
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: _filteredProfessions.length,
      itemBuilder: (context, index) {
        final p = _filteredProfessions[index];
        final color = _getColorFromHex(p['color']);

        return InkWell(
          onTap: () {
            setState(() {
              _selectedProfession = p;
              _showWorkerList = true;
              _searchController.clear();
              _applyFilters();
            });
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getIcon(p['logo']), color: color, size: 32),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    p[locale] ?? p['en'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkerList(String locale, Color themeColor) {
    if (_filteredWorkers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              locale == 'he'
                  ? 'אין עובדים זמינים כרגע'
                  : 'No available workers at the moment',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredWorkers.length,
      itemBuilder: (context, index) {
        final w = _filteredWorkers[index];
        
        String distanceStr = "";
        if (_sortBy == 'distance' && _currentPosition != null && w['lat'] != null && w['lng'] != null) {
          double distance = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, w['lat'], w['lng']);
          if (distance < 1000) {
            distanceStr = "${distance.toStringAsFixed(0)}m";
          } else {
            distanceStr = "${(distance / 1000).toStringAsFixed(1)}km";
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Hero(
              tag: w['uid'],
              child: CircleAvatar(
                radius: 30,
                backgroundImage:
                    w['profileImageUrl'] != null &&
                        w['profileImageUrl'].toString().isNotEmpty
                    ? NetworkImage(w['profileImageUrl'])
                    : null,
                backgroundColor: const Color(0xFFF1F5F9),
                child:
                    w['profileImageUrl'] == null ||
                        w['profileImageUrl'].toString().isEmpty
                    ? Icon(Icons.person, color: themeColor)
                    : null,
              ),
            ),
            title: Text(
              w['name'] ?? 'Worker',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
<<<<<<< HEAD
                    Text(
                      w['town'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
=======
                    Text(w['town'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    if (distanceStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(distanceStr, style: TextStyle(color: themeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ]
>>>>>>> 7b713a42c7ae1f5bb5a752aedffb0ab40640f752
                  ],
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        w['avgRating'].toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
<<<<<<< HEAD
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => profile(userId: w['uid']),
              ),
            ),
=======
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => Profile(userId: w['uid']))),
>>>>>>> 7b713a42c7ae1f5bb5a752aedffb0ab40640f752
          ),
        );
      },
    );
  }

  void _showSortOptions(String locale, Color themeColor) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_rounded, color: Colors.amber),
              title: Text(locale == 'he' ? 'דירוג' : 'Rating'),
              trailing: _sortBy == 'rating'
                  ? Icon(Icons.check_circle, color: themeColor)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'rating');
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.my_location, color: themeColor),
              title: Text(locale == 'he' ? 'הכי קרוב אלי' : 'Nearest to Me'),
              trailing: _sortBy == 'distance' ? Icon(Icons.check_circle, color: themeColor) : null,
              onTap: () {
                Navigator.pop(context);
                _getCurrentLocation();
              },
            ),
            ListTile(
              leading: Icon(Icons.sort_by_alpha_rounded, color: themeColor),
              title: Text(locale == 'he' ? 'שם' : 'Name'),
              trailing: _sortBy == 'name'
                  ? Icon(Icons.check_circle, color: themeColor)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'name');
                _applyFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getProfessionsList(Map<String, dynamic> worker) {
    if (worker['professions'] is List)
      return (worker['professions'] as List).cast<String>();
    if (worker['profession'] != null) return [worker['profession'].toString()];
    return [];
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
