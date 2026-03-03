import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/ptofile.dart';

class SearchPage extends StatefulWidget {
  final String? initialTrade;
  const SearchPage({super.key, this.initialTrade});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  
  static const String _dbUrl = 'https://profis-60aaa-default-rtdb.europe-west1.firebasedatabase.app';
  late final DatabaseReference _dbRef;

  List<Map<String, dynamic>> _allWorkers = [];
  List<Map<String, dynamic>> _filteredWorkers = [];
  bool _isLoading = true;
  String? _selectedTrade;
  String? _selectedSortBy;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instanceFor(
      app: FirebaseAuth.instance.app,
      databaseURL: _dbUrl
    ).ref();
    
    _selectedTrade = widget.initialTrade;
    _fetchWorkers();
  }

  Future<void> _fetchWorkers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      debugPrint("DB_LOG: Fetching users from $_dbUrl/users");
      final snapshot = await _dbRef.child('users').get();
      
      if (snapshot.exists && snapshot.value != null) {
        final dynamic rawData = snapshot.value;
        List<Map<String, dynamic>> workers = [];
        
        void processUser(String key, dynamic value) {
          if (value is Map) {
            final Map<String, dynamic> userData = {};
            value.forEach((k, v) => userData[k.toString()] = v);

            final String userType = userData['userType']?.toString() ?? '';
            final bool isSubscribed = userData['isSubscribed'] == true;

            // ONLY include users with userType: "worker" AND isSubscribed: true
            if (userType == 'worker' && isSubscribed) {
              userData['uid'] = key;
              workers.add(userData);
            }
          }
        }

        if (rawData is Map) {
          rawData.forEach((key, value) => processUser(key.toString(), value));
        } else if (rawData is List) {
          for (int i = 0; i < rawData.length; i++) {
            if (rawData[i] != null) processUser(i.toString(), rawData[i]);
          }
        }

        if (mounted) {
          setState(() {
            _allWorkers = workers;
            _applyFilters();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("FETCH ERROR: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching workers: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredWorkers = _allWorkers.where((worker) {
        bool matchesTrade = true;
        if (_selectedTrade != null) {
          // Check both 'professions' (List) and 'profession' (String)
          List<String> workerProfessions = [];
          if (worker['professions'] is List) {
            workerProfessions = (worker['professions'] as List).map((e) => e.toString().toLowerCase()).toList();
          } else if (worker['profession'] != null) {
            workerProfessions = [worker['profession'].toString().toLowerCase()];
          }
          
          matchesTrade = workerProfessions.contains(_selectedTrade!.toLowerCase());
        }

        bool matchesSearch = true;
        if (_searchController.text.isNotEmpty) {
          final name = (worker['name'] ?? '').toString().toLowerCase();
          matchesSearch = name.contains(_searchController.text.toLowerCase());
        }

        return matchesTrade && matchesSearch;
      }).toList();
    });
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final tradeNames = {
      'Plumber': locale == 'he' ? 'אינסטלטור' : (locale == 'ar' ? 'سباك' : 'Plumber'),
      'Carpenter': locale == 'he' ? 'נגר' : (locale == 'ar' ? 'نجار' : 'Carpenter'),
      'Electrician': locale == 'he' ? 'חשמלאי' : (locale == 'ar' ? 'كهربائي' : 'Electrician'),
      'Painter': locale == 'he' ? 'צבע' : (locale == 'ar' ? 'دهאן' : 'Painter'),
      'Cleaner': locale == 'he' ? 'מנקה' : (locale == 'ar' ? 'עامل نظافة' : 'Cleaner'),
      'Handyman': locale == 'he' ? 'שיפוצניק' : (locale == 'ar' ? 'עامل صيانة' : 'Handyman'),
      'Landscaper': locale == 'he' ? 'גנן' : (locale == 'ar' ? 'منסק حدائق' : 'Landscaper'),
      'HVAC': locale == 'he' ? 'מיזוג אוויר' : (locale == 'ar' ? 'تكييف ותברייד' : 'HVAC'),
    };

    switch (locale) {
      case 'he':
        return {
          'hints': {'search': 'חפש עובדים לפי שם...'},
          'labels': {'trade': 'מקצוע', 'sort_by': 'מיין לפי', 'clear_all': 'נקה הכל', 'workers_found': '${_filteredWorkers.length} עובדים נמצאו', 'no_workers': 'לא נמצאו עובדים'},
          'trades': tradeNames,
          'sort_options': ['הכי מדורג', 'המחיר הכי נמוך', 'המחיר הכי גבוה', 'הכי הרבה עבודות']
        };
      case 'ar':
        return {
          'hints': {'search': 'بحث عن عامل بالاسم...'},
          'labels': {'trade': 'مهنة', 'sort_by': 'صنف حسب', 'clear_all': 'امسح الكل', 'workers_found': 'تم العثور على ${_filteredWorkers.length} عامل', 'no_workers': 'لم يتم العثور على عمال'},
          'trades': tradeNames,
          'sort_options': ['الأعلى تقييماً', 'أقل سعر', 'أعلى سعر', 'الأكثر عملاً']
        };
      default:
        return {
          'hints': {'search': 'Search workers by name...'},
          'labels': {'trade': 'TRADE', 'sort_by': 'SORT BY', 'clear_all': 'Clear all', 'workers_found': '${_filteredWorkers.length} workers found', 'no_workers': 'No workers found'},
          'trades': tradeNames,
          'sort_options': ['Highest Rated', 'Lowest Price', 'Highest Price', 'Most Jobs']
        };
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localized = _getLocalizedStrings(context);
    final tradeNames = localized['trades'] as Map<String, String>;
    final sortOptions = localized['sort_options'] as List<String>;
    final labels = localized['labels'] as Map<String, String>;
    final hints = localized['hints'] as Map<String, String>;
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.initialTrade != null ? AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(tradeNames[_selectedTrade] ?? "", style: const TextStyle(color: Colors.black)),
      ) : null,
      body: SafeArea(
        child: Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildSearchBar(hints['search']!, isRtl),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    if (_showFilters)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFilterSection(labels['trade']!, tradeNames, _selectedTrade, (value) {
                                setState(() {
                                  _selectedTrade = (_selectedTrade == value) ? null : value;
                                  _applyFilters();
                                });
                              }),
                              const SizedBox(height: 24),
                              _buildSortSection(labels['sort_by']!, sortOptions, _selectedSortBy, (value) {
                                setState(() {
                                  _selectedSortBy = (_selectedSortBy == value) ? null : value;
                                  _applyFilters();
                                });
                              }),
                              const SizedBox(height: 16),
                              _buildClearAllButton(labels['clear_all']!),
                              const Divider(height: 32),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(labels['workers_found']!, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                    _isLoading
                      ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                      : _filteredWorkers.isEmpty
                        ? SliverFillRemaining(child: _buildEmptyState(labels['no_workers']!))
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final worker = _filteredWorkers[index];
                                return _buildWorkerCard(worker);
                              },
                              childCount: _filteredWorkers.length,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(String hint, bool isRtl) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            onChanged: (v) => _applyFilters(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: _showFilters ? const Color(0xFFEEF2FF) : const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _showFilters ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB)),
          ),
          child: IconButton(
            icon: Icon(
              _showFilters ? Icons.filter_list_off : Icons.filter_list,
              color: _showFilters ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF),
            ),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection(String title, Map<String, String> options, String? selectedValue, Function(String) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.entries.map((entry) {
              final isSelected = entry.key == selectedValue;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  onSelected: (selected) => onSelected(entry.key),
                  selectedColor: const Color(0xFF2563EB),
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSortSection(String title, List<String> options, String? selectedValue, Function(String) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((option) {
              final isSelected = option == selectedValue;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (selected) => onSelected(option),
                  selectedColor: const Color(0xFF2563EB),
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildClearAllButton(String label) {
    return TextButton.icon(
      onPressed: () {
        setState(() {
          _selectedTrade = null;
          _selectedSortBy = null;
          _searchController.clear();
          _applyFilters();
        });
      },
      icon: const Icon(Icons.close, size: 16),
      label: Text(label),
    );
  }

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: Colors.blue[100],
          child: const Icon(Icons.person, size: 30, color: Colors.blue),
        ),
        title: Text(worker['name'] ?? 'Worker', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(worker['town'] ?? '', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: _getProfessionsList(worker)
                  .map((p) => Chip(
                        label: Text(p, style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final uid = worker['uid'] ?? '';
          if (uid.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => profile(userId: uid)),
            );
          }
        },
      ),
    );
  }

  List<String> _getProfessionsList(Map<String, dynamic> worker) {
    if (worker['professions'] is List) {
      return (worker['professions'] as List).map((e) => e.toString()).toList();
    } else if (worker['profession'] != null) {
      return [worker['profession'].toString()];
    }
    return [];
  }

  Widget _buildEmptyState(String emptyLabel) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(emptyLabel, style: const TextStyle(color: Colors.grey, fontSize: 18)),
        ],
      ),
    );
  }
}
