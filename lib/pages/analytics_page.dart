import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

class AnalyticsPage extends StatefulWidget {
  final String userId;
  final Map<String, String> strings;

  const AnalyticsPage({super.key, required this.userId, required this.strings});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  static const String _allProfessionsKey = '__all_professions__';
  static const String _vpdDocId = 'currentWeek';
  static const List<String> _weekDayKeys = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];

  bool _isLoading = true;
  int _totalJobs = 0;
  int _profileViews = 0;
  double _totalEarnings = 0.0;
  double _avgRating = 0.0;
  double _overallAvgRating = 0.0;

  double _avgPrice = 0.0;
  double _avgService = 0.0;
  double _avgTiming = 0.0;
  double _avgWorkQuality = 0.0;

  List<FlSpot> _earningsSpots = [];
  List<BarChartGroupData> _viewGroups = [];

  String _performanceOverview = '';
  String _topServices = '';
  double _conversionRate = 0.0;

  List<String> _professionOptions = [];
  String _selectedProfession = _allProfessionsKey;
  Map<String, Map<String, dynamic>> _professionRatingStats = {};
  Map<String, Map<String, int>> _professionWeeklyViews = {};
  List<int> _weeklyViewCounts = List.filled(7, 0);
  int _lifetimeProfileViews = 0;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return fallback;
  }

  DateTime _startOfWeek(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final offsetToSunday = dayStart.weekday % 7;
    return dayStart.subtract(Duration(days: offsetToSunday));
  }

  bool _isCurrentWeek(dynamic rawWeekStart) {
    DateTime? saved;
    if (rawWeekStart is Timestamp) {
      saved = rawWeekStart.toDate();
    } else if (rawWeekStart is String) {
      saved = DateTime.tryParse(rawWeekStart);
    }

    if (saved == null) return false;

    final currentWeek = _startOfWeek(DateTime.now());
    final savedWeek = _startOfWeek(saved);
    return savedWeek.isAtSameMomentAs(currentWeek);
  }

  Map<String, int> _emptyWeekMap() {
    return {
      'sunday': 0,
      'monday': 0,
      'tuesday': 0,
      'wednesday': 0,
      'thursday': 0,
      'friday': 0,
      'saturday': 0,
      'TVTW': 0,
    };
  }

  List<int> _extractWeekCounts(Map<String, int> map) {
    return _weekDayKeys.map((day) => map[day] ?? 0).toList();
  }

  int _sumWeekCounts(List<int> counts) {
    return counts.fold<int>(0, (sum, value) => sum + value);
  }

  Map<String, int> _normalizeWeekData(Map<String, dynamic> data) {
    final normalized = _emptyWeekMap();

    if (_isCurrentWeek(data['weekStart'])) {
      for (final day in _weekDayKeys) {
        normalized[day] = _asInt(data[day]);
      }
      normalized['TVTW'] = _asInt(data['TVTW']);
      if (normalized['TVTW'] == 0) {
        normalized['TVTW'] = _sumWeekCounts(_extractWeekCounts(normalized));
      }
    }

    return normalized;
  }

  Future<Map<String, Map<String, int>>> _fetchProfessionWeeklyViews(
    QuerySnapshot<Map<String, dynamic>> proRatingSnapshot,
  ) async {
    final result = <String, Map<String, int>>{};

    for (final proDoc in proRatingSnapshot.docs) {
      final data = proDoc.data();
      final profession = (data['profession'] ?? proDoc.id).toString();

      final vpdDoc = await proDoc.reference
          .collection('VPD')
          .doc(_vpdDocId)
          .get();

      if (!vpdDoc.exists) continue;
      result[profession] = _normalizeWeekData(vpdDoc.data() ?? {});
    }

    return result;
  }

  String _buildGrowthRecommendation() {
    final noData = widget.strings['no_reviews'] ?? 'No data';

    if (_profileViews == 0 && _totalJobs == 0) {
      return 'You are just getting started. Complete your first jobs and ask clients for reviews to unlock better insights.';
    }

    final parts = <String>[];
    final scope = _selectedProfession == _allProfessionsKey
        ? 'across all professions'
        : 'for $_selectedProfession';

    if (_profileViews < 20) {
      parts.add(
        'Your visibility is still low $scope. Update your profile photo, title, and service description to attract more views.',
      );
    } else if (_conversionRate < 5) {
      parts.add(
        'You are getting views but few bookings $scope. Improve your profile headline, add clear prices, and highlight recent results.',
      );
    } else if (_conversionRate >= 20) {
      parts.add(
        'Great conversion $scope. Keep response time fast and continue asking happy clients for new reviews.',
      );
    }

    if (_avgRating >= 4.5) {
      parts.add(
        'Your rating is excellent. Use this as social proof near the top of your profile to win more jobs.',
      );
    } else if (_avgRating > 0 && _avgRating < 4.0) {
      final weakestMetric = _getWeakestMetricLabel();
      parts.add(
        'Your rating can improve. Focus on better $weakestMetric in your next jobs and ask clients for detailed feedback.',
      );
    }

    if (_topServices.isNotEmpty && _topServices != noData) {
      parts.add(
        'Your strongest profession is $_topServices. Feature it first in your profile and portfolio.',
      );
    }

    if (parts.isEmpty) {
      return 'Performance looks stable $scope. Keep completing jobs consistently and collect more reviews to grow faster.';
    }

    return parts.join(' ');
  }

  String _getWeakestMetricLabel() {
    final metrics = <MapEntry<String, double>>[
      MapEntry(widget.strings['price'] ?? 'price', _avgPrice),
      MapEntry(widget.strings['service'] ?? 'service', _avgService),
      MapEntry(widget.strings['timing'] ?? 'timing', _avgTiming),
      MapEntry(
        widget.strings['work_quality'] ?? 'work quality',
        _avgWorkQuality,
      ),
    ];

    metrics.sort((a, b) => a.value.compareTo(b.value));
    return metrics.first.key;
  }

  Future<void> _fetchAnalytics() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final workerRef = firestore.collection('users').doc(widget.userId);

      final userDoc = await workerRef.get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        _totalJobs = data['totalJobs'] ?? 0;
        _lifetimeProfileViews = data['profileViews'] ?? 0;
        _profileViews = _lifetimeProfileViews;
        _totalEarnings = _asDouble(data['totalEarnings']);
        _overallAvgRating = _asDouble(data['avgRating']);
        _avgRating = _overallAvgRating;
      }

      final reviewsSnapshot = await workerRef.collection('reviews').get();
      final proRatingSnapshot = await workerRef.collection('ProRating').get();

      if (_totalJobs == 0) {
        _totalJobs = reviewsSnapshot.docs.length;
      }

      _professionRatingStats = _buildProfessionStats(
        proRatingSnapshot,
        reviewsSnapshot,
      );

      _professionOptions = _professionRatingStats.keys.toList()..sort();
      if (_professionOptions.isEmpty) {
        _selectedProfession = _allProfessionsKey;
      } else if (_selectedProfession != _allProfessionsKey &&
          !_professionOptions.contains(_selectedProfession)) {
        _selectedProfession = _allProfessionsKey;
      }

      _professionWeeklyViews = await _fetchProfessionWeeklyViews(
        proRatingSnapshot,
      );

      _applyProfessionSelection();

      _conversionRate = _profileViews > 0
          ? (_totalJobs / _profileViews) * 100
          : 0.0;

      _performanceOverview = _buildGrowthRecommendation();

      _generateChartData();
    } catch (e) {
      debugPrint('Analytics Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, Map<String, dynamic>> _buildProfessionStats(
    QuerySnapshot<Map<String, dynamic>> proRatingSnapshot,
    QuerySnapshot<Map<String, dynamic>> reviewsSnapshot,
  ) {
    final result = <String, Map<String, dynamic>>{};

    if (proRatingSnapshot.docs.isNotEmpty) {
      for (final doc in proRatingSnapshot.docs) {
        final data = doc.data();
        final profession = (data['profession'] ?? doc.id).toString();
        result[profession] = {
          'reviewCount': data['reviewCount'] ?? 0,
          'avgOverallRating': _asDouble(data['avgOverallRating']),
          'avgPriceRating': _asDouble(data['avgPriceRating']),
          'avgServiceRating': _asDouble(data['avgServiceRating']),
          'avgTimingRating': _asDouble(data['avgTimingRating']),
          'avgWorkQualityRating': _asDouble(data['avgWorkQualityRating']),
        };
      }
      return result;
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final doc in reviewsSnapshot.docs) {
      final data = doc.data();
      final profession = (data['profession'] ?? '').toString().trim();
      if (profession.isEmpty) continue;
      grouped.putIfAbsent(profession, () => []).add(data);
    }

    grouped.forEach((profession, reviews) {
      double overallSum = 0;
      double priceSum = 0;
      double serviceSum = 0;
      double timingSum = 0;
      double workQualitySum = 0;

      for (final review in reviews) {
        final overall = _asDouble(review['rating']);
        final price = _asDouble(
          review['priceRating'] ?? review['starsPrice'],
          fallback: overall,
        );
        final service = _asDouble(
          review['serviceRating'] ??
              review['professionalismRating'] ??
              review['starsService'],
          fallback: overall,
        );
        final timing = _asDouble(
          review['timingRating'] ?? review['starsTiming'],
          fallback: overall,
        );
        final workQuality = _asDouble(
          review['workQualityRating'] ?? review['workRating'],
          fallback: overall,
        );

        overallSum += overall;
        priceSum += price;
        serviceSum += service;
        timingSum += timing;
        workQualitySum += workQuality;
      }

      final count = reviews.length;
      if (count == 0) return;

      result[profession] = {
        'reviewCount': count,
        'avgOverallRating': overallSum / count,
        'avgPriceRating': priceSum / count,
        'avgServiceRating': serviceSum / count,
        'avgTimingRating': timingSum / count,
        'avgWorkQualityRating': workQualitySum / count,
      };
    });

    return result;
  }

  void _applyProfessionSelection() {
    _weeklyViewCounts = List.filled(7, 0);

    if (_selectedProfession != _allProfessionsKey &&
        _professionWeeklyViews.containsKey(_selectedProfession)) {
      final selectedViews = _professionWeeklyViews[_selectedProfession]!;
      _weeklyViewCounts = _extractWeekCounts(selectedViews);
      _profileViews =
          selectedViews['TVTW'] ?? _sumWeekCounts(_weeklyViewCounts);
    } else if (_professionWeeklyViews.isNotEmpty) {
      for (final map in _professionWeeklyViews.values) {
        final dayCounts = _extractWeekCounts(map);
        for (int i = 0; i < _weeklyViewCounts.length; i++) {
          _weeklyViewCounts[i] += dayCounts[i];
        }
      }
      _profileViews = _sumWeekCounts(_weeklyViewCounts);
    } else {
      _profileViews = _lifetimeProfileViews;
    }

    if (_professionRatingStats.isEmpty) {
      _avgRating = _overallAvgRating;
      _avgPrice = 0.0;
      _avgService = 0.0;
      _avgTiming = 0.0;
      _avgWorkQuality = 0.0;
      _topServices = widget.strings['no_reviews'] ?? 'No data';
      return;
    }

    if (_selectedProfession != _allProfessionsKey &&
        _professionRatingStats.containsKey(_selectedProfession)) {
      final selected = _professionRatingStats[_selectedProfession]!;
      _avgRating = _asDouble(selected['avgOverallRating']);
      _avgPrice = _asDouble(selected['avgPriceRating']);
      _avgService = _asDouble(selected['avgServiceRating']);
      _avgTiming = _asDouble(selected['avgTimingRating']);
      _avgWorkQuality = _asDouble(selected['avgWorkQualityRating']);
      _topServices = _getHighestRatedProfession();
      return;
    }

    int totalCount = 0;
    double overallWeighted = 0.0;
    double priceWeighted = 0.0;
    double serviceWeighted = 0.0;
    double timingWeighted = 0.0;
    double workQualityWeighted = 0.0;

    _professionRatingStats.forEach((profession, stats) {
      final count = (stats['reviewCount'] ?? 0) as int;
      totalCount += count;
      overallWeighted += _asDouble(stats['avgOverallRating']) * count;
      priceWeighted += _asDouble(stats['avgPriceRating']) * count;
      serviceWeighted += _asDouble(stats['avgServiceRating']) * count;
      timingWeighted += _asDouble(stats['avgTimingRating']) * count;
      workQualityWeighted += _asDouble(stats['avgWorkQualityRating']) * count;
    });

    if (totalCount > 0) {
      _avgRating = overallWeighted / totalCount;
      _avgPrice = priceWeighted / totalCount;
      _avgService = serviceWeighted / totalCount;
      _avgTiming = timingWeighted / totalCount;
      _avgWorkQuality = workQualityWeighted / totalCount;
      _topServices = _getHighestRatedProfession();
    }
  }

  String _getHighestRatedProfession() {
    if (_professionRatingStats.isEmpty) {
      return widget.strings['no_reviews'] ?? 'No data';
    }

    String bestProfession = '';
    double bestRating = -1.0;
    int bestCount = -1;

    _professionRatingStats.forEach((profession, stats) {
      final rating = _asDouble(stats['avgOverallRating']);
      final count = (stats['reviewCount'] ?? 0) as int;

      final isBetterRating = rating > bestRating;
      final isTieButMoreReviews = rating == bestRating && count > bestCount;

      if (isBetterRating || isTieButMoreReviews) {
        bestRating = rating;
        bestCount = count;
        bestProfession = profession;
      }
    });

    return bestProfession.isEmpty
        ? (widget.strings['no_reviews'] ?? 'No data')
        : bestProfession;
  }

  void _generateChartData() {
    final base = _totalEarnings / 7;
    _earningsSpots = List.generate(7, (i) {
      final y = (base * (i + 0.5) * (0.8 + (i % 3) * 0.1)).clamp(
        0,
        _totalEarnings * 1.5,
      );
      return FlSpot(i.toDouble(), y.toDouble());
    });

    _viewGroups = List.generate(7, (i) {
      final toY = _weeklyViewCounts[i].toDouble();
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: toY,
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            ),
            width: 14,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _totalJobs == 0) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.strings['analytics_title'] ?? 'Business Dashboard',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAnalytics,
        color: const Color(0xFF1976D2),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMainBalanceCard(),
              const SizedBox(height: 24),
              _buildProfessionSelector(),
              const SizedBox(height: 24),
              _buildMetricsGrid(),
              const SizedBox(height: 32),
              _buildChartCard(
                'Earnings Trend (Last 7 Days)',
                _buildEarningsChart(),
              ),
              const SizedBox(height: 24),
              _buildChartCard('Profile Reach', _buildViewsChart()),
              const SizedBox(height: 32),
              _buildSectionHeader('Service Quality Breakdown'),
              const SizedBox(height: 16),
              _buildRatingsSection(),
              const SizedBox(height: 32),
              _buildAITipCard(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionSelector() {
    if (_professionOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedProfession,
          items: [
            DropdownMenuItem(
              value: _allProfessionsKey,
              child: Text(
                widget.strings['all_professions'] ?? 'All professions',
              ),
            ),
            ..._professionOptions.map(
              (p) => DropdownMenuItem(value: p, child: Text(p)),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedProfession = value;
              _applyProfessionSelection();
              _performanceOverview = _buildGrowthRecommendation();
            });
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildMainBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.strings['total_earnings'] ?? 'Estimated Earnings',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white30,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₪${intl.NumberFormat('#,###').format(_totalEarnings)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildQuickStat(
                widget.strings['total_jobs'] ?? 'Jobs',
                _totalJobs.toString(),
                Icons.check_circle_outline,
              ),
              _buildQuickStat(
                'Rating',
                _avgRating.toStringAsFixed(1),
                Icons.star_border_rounded,
              ),
              _buildQuickStat(
                'Views',
                _profileViews.toString(),
                Icons.bar_chart_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blueAccent, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoTile(
            'Conversion',
            '${_conversionRate.toStringAsFixed(1)}%',
            Icons.swap_calls_rounded,
            Colors.teal,
            helpText:
                'Conversion is the percentage of profile viewers who became jobs. Formula: jobs ÷ views × 100.',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildInfoTile(
            'Top Skill',
            _topServices,
            Icons.auto_graph_rounded,
            Colors.indigo,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? helpText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (helpText != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: helpText,
                  triggerMode: TooltipTriggerMode.tap,
                  waitDuration: Duration.zero,
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(String title, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(height: 180, child: chart),
        ],
      ),
    );
  }

  Widget _buildRatingsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          _buildRatingProgress(
            widget.strings['price'] ?? 'Price',
            _avgPrice,
            Colors.amber,
          ),
          const SizedBox(height: 20),
          _buildRatingProgress(
            widget.strings['service'] ?? 'Service',
            _avgService,
            Colors.blueAccent,
          ),
          const SizedBox(height: 20),
          _buildRatingProgress(
            widget.strings['timing'] ?? 'Timing',
            _avgTiming,
            Colors.greenAccent,
          ),
          const SizedBox(height: 20),
          _buildRatingProgress(
            widget.strings['work_quality'] ?? 'Work Quality',
            _avgWorkQuality,
            Colors.deepPurpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildRatingProgress(String label, double value, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            Text(
              value.toStringAsFixed(1),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (value / 5.0).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildAITipCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tips_and_updates_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Growth Recommendation',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _performanceOverview,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _earningsSpots,
            isCurved: true,
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
            ),
            barWidth: 6,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withOpacity(0.3),
                  const Color(0xFF3B82F6).withOpacity(0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dayLabel(int index) {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    if (index < 0 || index >= labels.length) return '';
    return labels[index];
  }

  Widget _buildViewsChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _dayLabel(index),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: _viewGroups,
      ),
    );
  }
}
