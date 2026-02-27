import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';

class SearchPage extends StatefulWidget {
  final String? initialTrade;
  const SearchPage({super.key, this.initialTrade});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    // Listen to LanguageProvider for updates
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'hints': {'search': 'חפש עובדים, מקצועות...'},
          'labels': {'trade': 'מקצוע', 'sort_by': 'מיין לפי', 'clear_all': 'נקה הכל', 'workers_found': '0 עובדים נמצאו', 'no_workers': 'לא נמצאו עובדים'},
          'trades': ['אינסטלטור', 'נגר', 'חשמלאי', 'צבע', 'מנקה', 'שיפוצניק', 'גנן', 'מיזוג אוויר'],
          'sort_options': ['הכי מדורג', 'המחיר הכי נמוך', 'המחיר הכי גבוה', 'הכי הרבה עבודות']
        };
      case 'ar':
        return {
          'hints': {'search': 'البحث عن عمال، مهن...'},
          'labels': {'trade': 'مهنة', 'sort_by': 'صنف حسب', 'clear_all': 'امسح الكل', 'workers_found': 'تم العثور على 0 عمال', 'no_workers': 'لم يتم العثور على عمال'},
          'trades': ['سباك', 'نجار', 'كهربائي', 'دهان', 'عامل نظافة', 'عامل صيانة', 'منسق حدائق', 'تكييف وتبريد'],
          'sort_options': ['الأعلى تقييماً', 'أقل سعر', 'أعلى سعر', 'الأكثر عملاً']
        };
      case 'ru':
        return {
          'hints': {'search': 'Поиск рабочих, профессий...'},
          'labels': {'trade': 'ПРОФЕССИЯ', 'sort_by': 'СОРТИРОВАТЬ ПО', 'clear_all': 'Очистить все', 'workers_found': 'Найдено 0 рабочих', 'no_workers': 'Рабочие не найдены'},
          'trades': ['Сантехник', 'Плотник', 'Электрик', 'Маляр', 'Уборщик', 'Разнорабочий', 'Ландшафтный дизайнер', 'Кондиционеры'],
          'sort_options': ['Самый высокий рейтинг', 'Самая низкая цена', 'Самая высокая цена', 'Больше всего работ']
        };
      default: // en
        return {
          'hints': {'search': 'Search workers, trades...'},
          'labels': {'trade': 'TRADE', 'sort_by': 'SORT BY', 'clear_all': 'Clear all', 'workers_found': '0 workers found', 'no_workers': 'No workers found'},
          'trades': ['Plumber', 'Carpenter', 'Electrician', 'Painter', 'Cleaner', 'Handyman', 'Landscaper', 'HVAC'],
          'sort_options': ['Highest Rated', 'Lowest Price', 'Highest Price', 'Most Jobs']
        };
    }
  }

  String? _selectedTrade;
  String? _selectedSortBy;
  bool _showFilters = true;

  @override
  void initState() {
    super.initState();
    _selectedTrade = widget.initialTrade;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localized = _getLocalizedStrings(context);
    final trades = localized['trades'] as List<String>;
    final sortOptions = localized['sort_options'] as List<String>;
    final labels = localized['labels'] as Map<String, String>;
    final hints = localized['hints'] as Map<String, String>;
    
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    // If initialTrade was passed but it doesn't match current language list, 
    // or if no trade is selected yet, use default.
    if (_selectedTrade == null || !trades.contains(_selectedTrade)) {
       // Only default if we don't have a valid selection
       if (widget.initialTrade == null || !trades.contains(widget.initialTrade)) {
          _selectedTrade = trades[4];
       } else {
          _selectedTrade = widget.initialTrade;
       }
    }
    
    _selectedSortBy ??= sortOptions[0];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.initialTrade != null ? AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ) : null,
      body: SafeArea(
        child: Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(hints['search']!, isRtl),
                if (_showFilters) ...[
                  const SizedBox(height: 24),
                  _buildFilterSection(labels['trade']!, trades, _selectedTrade, (value) {
                    setState(() => _selectedTrade = value);
                  }),
                  const SizedBox(height: 24),
                  _buildFilterSection(labels['sort_by']!, sortOptions, _selectedSortBy, (value) {
                    setState(() => _selectedSortBy = value);
                  }),
                  const SizedBox(height: 24),
                  _buildClearAllButton(labels['clear_all']!),
                ],
                const SizedBox(height: 32),
                const Divider(color: Color(0xFFF0F0F0), thickness: 1),
                const SizedBox(height: 24),
                _buildEmptyState(labels['workers_found']!, labels['no_workers']!),
              ],
            ),
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
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _showFilters ? const Color(0xFFEEF2FF) : const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _showFilters ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB),
            ),
          ),
          child: IconButton(
            icon: Icon(
              Icons.tune,
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

  Widget _buildFilterSection(String title, List<String> options, String? selectedValue, Function(String) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF9CA3AF),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return GestureDetector(
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2563EB) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected ? null : Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF4B5563),
                    fontSize: 14,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildClearAllButton(String label) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTrade = null;
          _selectedSortBy = null;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close, size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF4B5563), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String countLabel, String emptyLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(countLabel, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 14)),
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                child: const Icon(Icons.search, size: 48, color: Color(0xFFD1D5DB)),
              ),
              const SizedBox(height: 16),
              Text(
                emptyLabel,
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
