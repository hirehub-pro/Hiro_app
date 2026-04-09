import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/ptofile.dart';
import 'package:path_provider/path_provider.dart';

class AdminPanel extends StatefulWidget {
  final bool showAppBar;
  const AdminPanel({super.key, this.showAppBar = true});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _formatCompactDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}$month$day';
  }

  String _formatDashedDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<DateTimeRange?> _pickExportDateRange() async {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
    );
  }

  Future<Directory> _getBkmvExportDirectory() async {
    final downloadsDir =
        await getApplicationDocumentsDirectory();
    final directory = Directory('${downloadsDir.path}${Platform.pathSeparator}BKMVDATA');
    await directory.create(recursive: true);
    return directory;
  }

  late final Map<String, IconData> _availableIcons = _buildProfessionIcons();

  List<String> get _pickerIconKeys => _deduplicateIconKeys(_availableIcons);

  static Map<String, IconData> _buildProfessionIcons() {
    return {
      'engineering': Icons.engineering,
      'plumbing': Icons.plumbing,
      'electrical_services': Icons.electrical_services,
      'electric_bolt': Icons.electric_bolt,
      'lightbulb': Icons.lightbulb,
      'carpenter': Icons.carpenter,
      'handyman': Icons.handyman,
      'home_repair_service': Icons.home_repair_service,
      'construction': Icons.construction,
      'foundation': Icons.foundation,
      'roofing': Icons.roofing,
      'hardware': Icons.hardware,
      'build': Icons.build,
      'format_paint': Icons.format_paint,
      'format_color_fill': Icons.format_color_fill,
      'architecture': Icons.architecture,
      'design_services': Icons.design_services,
      'straighten': Icons.straighten,
      'square_foot': Icons.square_foot,
      'chair': Icons.chair,
      'table_restaurant': Icons.table_restaurant,
      'window': Icons.window,
      'door_front_door': Icons.door_front_door,
      'blinds': Icons.blinds,
      'shower': Icons.shower,
      'water_drop': Icons.water_drop,
      'water_damage': Icons.water_damage,
      'ac_unit': Icons.ac_unit,
      'air': Icons.air,
      'cleaning_services': Icons.cleaning_services,
      'dry_cleaning': Icons.dry_cleaning,
      'clean_hands': Icons.clean_hands,
      'pest_control': Icons.pest_control,
      'bug_report': Icons.bug_report,
      'solar_power': Icons.solar_power,
      'computer': Icons.computer,
      'devices': Icons.devices,
      'memory': Icons.memory,
      'router': Icons.router,
      'wifi': Icons.wifi,
      'phone_android': Icons.phone_android,
      'print': Icons.print,
      'camera_indoor': Icons.camera_indoor,
      'security': Icons.security,
      'shield': Icons.shield,
      'support_agent': Icons.support_agent,
      'medical_services': Icons.medical_services,
      'local_hospital': Icons.local_hospital,
      'monitor_heart': Icons.monitor_heart,
      'healing': Icons.healing,
      'psychology': Icons.psychology,
      'fitness_center': Icons.fitness_center,
      'spa': Icons.spa,
      'child_care': Icons.child_care,
      'elderly': Icons.elderly,
      'school': Icons.school,
      'translate': Icons.translate,
      'calculate': Icons.calculate,
      'gavel': Icons.gavel,
      'real_estate_agent': Icons.real_estate_agent,
      'storefront': Icons.storefront,
      'shopping_bag': Icons.shopping_bag,
      'badge': Icons.badge,
      'restaurant': Icons.restaurant,
      'restaurant_menu': Icons.restaurant_menu,
      'lunch_dining': Icons.lunch_dining,
      'bakery_dining': Icons.bakery_dining,
      'cake': Icons.cake,
      'celebration': Icons.celebration,
      'event': Icons.event,
      'photo_camera': Icons.photo_camera,
      'camera_alt': Icons.camera_alt,
      'add_a_photo': Icons.add_a_photo,
      'videocam': Icons.videocam,
      'movie_creation': Icons.movie_creation,
      'music_note': Icons.music_note,
      'graphic_eq': Icons.graphic_eq,
      'piano': Icons.piano,
      'palette': Icons.palette,
      'brush': Icons.brush,
      'face': Icons.face,
      'checkroom': Icons.checkroom,
      'content_cut': Icons.content_cut,
      'iron': Icons.iron,
      'local_shipping': Icons.local_shipping,
      'local_moving': Icons.moving,
      'inventory_2': Icons.inventory_2,
      'delivery_dining': Icons.delivery_dining,
      'local_car_wash': Icons.local_car_wash,
      'directions_car': Icons.directions_car,
      'car_repair': Icons.car_repair,
      'airport_shuttle': Icons.airport_shuttle,
      'two_wheeler': Icons.two_wheeler,
      'moped': Icons.moped,
      'pedal_bike': Icons.pedal_bike,
      'fire_truck': Icons.fire_truck,
      'park': Icons.park,
      'pets': Icons.pets,
      'pool': Icons.pool,
      'waves': Icons.waves,
      'home': Icons.home,
      'house': Icons.house,
      'apartment': Icons.apartment,
      'cabin': Icons.cabin,
      'garage': Icons.garage,
      'public': Icons.public,
      'language': Icons.language,
      'science': Icons.science,
      'biotech': Icons.biotech,
      'eco': Icons.eco,
      'history_edu': Icons.history_edu,
      'bolt': Icons.bolt,
      'vpn_key': Icons.vpn_key,
      'locksmith': Icons.lock_open,
      'man': Icons.man,
      'woman': Icons.woman,
      'weekend': Icons.weekend,
      'paint_rounded': Icons.format_paint_rounded,
      'construction_rounded': Icons.construction_rounded,
      'plumbing_rounded': Icons.plumbing_rounded,
      'engineering_outlined': Icons.engineering_outlined,
    };
  }

  static List<String> _deduplicateIconKeys(Map<String, IconData> icons) {
    final uniqueKeys = <String>[];
    final seenSignatures = <String>{};
    for (final entry in icons.entries) {
      final icon = entry.value;
      final signature =
          '${icon.fontFamily}|${icon.fontPackage}|${icon.codePoint}|${icon.matchTextDirection}';
      if (seenSignatures.add(signature)) {
        uniqueKeys.add(entry.key);
      }
    }
    return uniqueKeys;
  }

  static const List<String> _availableProfessionColors = [
    '#1976D2',
    '#1565C0',
    '#0D47A1',
    '#1D4ED8',
    '#2563EB',
    '#3B82F6',
    '#42A5F5',
    '#60A5FA',
    '#0284C7',
    '#0EA5E9',
    '#0369A1',
    '#26C6DA',
    '#06B6D4',
    '#00897B',
    '#0F766E',
    '#14B8A6',
    '#14B86A',
    '#2E7D32',
    '#43A047',
    '#16A34A',
    '#22C55E',
    '#7CB342',
    '#AFB42B',
    '#84CC16',
    '#65A30D',
    '#4D7C0F',
    '#F9A825',
    '#FFB300',
    '#F59E0B',
    '#FBBF24',
    '#FB8C00',
    '#F57C00',
    '#EA580C',
    '#F97316',
    '#E64A19',
    '#D84315',
    '#D32F2F',
    '#C62828',
    '#EF4444',
    '#DC2626',
    '#B91C1C',
    '#AD1457',
    '#C2185B',
    '#DB2777',
    '#EC4899',
    '#8E24AA',
    '#7B1FA2',
    '#9333EA',
    '#A855F7',
    '#5E35B1',
    '#4527A0',
    '#6366F1',
    '#4F46E5',
    '#6D4C41',
    '#5D4037',
    '#8D6E63',
    '#A1887F',
    '#546E7A',
    '#455A64',
    '#37474F',
    '#475569',
    '#334155',
    '#1F2937',
    '#111827',
    '#64748B',
    '#9CA3AF',
    '#6B7280',
    '#78716C',
    '#00838F',
    '#00695C',
    '#283593',
    '#1E88E5',
    '#039BE5',
    '#00ACC1',
    '#7C3AED',
    '#C2410C',
    '#15803D',
    '#BE123C',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Admin System Control'),
              backgroundColor: Colors.red[900],
              foregroundColor: Colors.white,
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('User Management'),
            _buildAdminTile(
              context,
              icon: Icons.people_alt_rounded,
              title: 'Normal Users',
              subtitle: 'View and manage client accounts',
              onTap: () => _showUserList(context, 'customer', 'Normal Users'),
            ),
            _buildAdminTile(
              context,
              icon: Icons.engineering_rounded,
              title: 'All Workers',
              subtitle: 'Manage all professional worker accounts',
              onTap: () =>
                  _showUserList(context, 'worker', 'Professional Workers'),
            ),
            _buildAdminTile(
              context,
              icon: Icons.verified_rounded,
              title: 'Professional Verifications',
              subtitle: 'Approve or reject business documents',
              onTap: () => _showVerifications(context),
            ),
            _buildAdminTile(
              context,
              icon: Icons.description,
              title: 'Generate BKMVDATA.txt',
              subtitle: 'Export BKMVDATA.txt and INI.txt',
              onTap: _generateBkmvDataFile,
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('Content Moderation'),
            _buildAdminTile(
              context,
              icon: Icons.report_rounded,
              title: 'Reports Queue',
              subtitle: 'Handle user and project reports',
              onTap: () => _showReports(context),
            ),
            const SizedBox(height: 20),
            _buildSectionTitle('System Configuration'),
            _buildAdminTile(
              context,
              icon: Icons.category_rounded,
              title: 'Profession Categories',
              subtitle: 'Add, remove or edit system professions',
              onTap: () => _showCategoriesEditor(context),
            ),
            _buildAdminTile(
              context,
              icon: Icons.campaign_rounded,
              title: 'System Broadcast / Ads',
              subtitle: 'Send ads with images and popups to all users',
              onTap: () => _showMarketingBroadcastDialog(context),
            ),
            const Divider(),
            _buildAdminTile(
              context,
              icon: Icons.sync_rounded,
              title: 'Normalize Professions',
              subtitle: 'Rebuild metadata/professions list from items',
              onTap: () => _syncProfessionsFromJson(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.red[900],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildAdminTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.red[900]),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Future<void> _syncProfessionsFromJson() async {
    try {
      final metadataRef = _firestore.collection('metadata').doc('professions');
      final metadataSnap = await metadataRef.get();
      final existingItems =
          ((metadataSnap.data()?['items'] as List?) ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
            ..sort((a, b) {
              final aId = int.tryParse(a['id']?.toString() ?? '') ?? 1 << 30;
              final bId = int.tryParse(b['id']?.toString() ?? '') ?? 1 << 30;
              return aId.compareTo(bId);
            });

      await metadataRef.set({
        'list': existingItems
            .map((item) => item['en']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList(),
        'items': existingItems,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('metadata/professions normalized')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUserList(BuildContext context, String role, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserManagementSheet(
        title: title,
        role: role,
        firestore: _firestore,
        onDelete: (uid, name) => _confirmDeleteUser(uid, name),
        onBan: (uid, name, isCurrentlyBanned) =>
            _confirmBanUser(uid, name, isCurrentlyBanned),
      ),
    );
  }

  void _showVerifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdminBottomSheet(
        title: 'Business Verifications',
        stream: _firestore
            .collection('verifications')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        itemBuilder: (context, doc) {
          final data = doc.data() as Map<String, dynamic>;
          final String uid = data['userId'] ?? doc.id;
          final String dealerType = data['dealerType'] ?? 'exempt';
          final String businessName = data['businessName'] ?? 'Business';

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ExpansionTile(
              title: Text(businessName),
              subtitle: Text('ID: ${data['businessId']} • $dealerType'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoRow('Address', data['address']),
                      _buildInfoRow('Tax Branch', data['taxBranch']),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildViewDocButton('ID Card', data['idCardUrl']),
                          _buildViewDocButton(
                            'Certificate',
                            data['businessCertUrl'],
                          ),
                          if (data['insuranceUrl'] != null)
                            _buildViewDocButton(
                              'Insurance',
                              data['insuranceUrl'],
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _handleVerification(
                                doc.id,
                                uid,
                                true,
                                dealerType,
                                businessName,
                              ),
                              child: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              onPressed: () => _showRejectDialog(
                                doc.id,
                                uid,
                                dealerType,
                                businessName,
                              ),
                              child: const Text('Reject'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showReports(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AdminBottomSheet(
        title: 'Active Reports',
        stream: _firestore
            .collection('reports')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        itemBuilder: (context, doc) {
          final report = doc.data() as Map<String, dynamic>;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text('Reason: ${report['reason']}'),
              subtitle: Text('Reported ID: ${report['reportedId']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.visibility_outlined,
                      color: Colors.blue,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Profile(userId: report['reportedId']),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    onPressed: () =>
                        _firestore.collection('reports').doc(doc.id).delete(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCategoriesEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProfessionCategoriesSheet(
        firestore: _firestore,
        availableIcons: _availableIcons,
        onAddSingle: () => _addCategoryDialog(context),
      ),
    );
  }

  void _showMarketingBroadcastDialog(BuildContext context) {
    final titleController = TextEditingController();
    final msgController = TextEditingController();
    final linkController = TextEditingController();
    final btnTextController = TextEditingController(text: 'Learn More');
    final badgeController = TextEditingController(text: 'Featured');
    final imageFiles = <File>[];
    bool isUploading = false;
    bool showPopup = true;
    bool showBanner = true;
    final now = DateTime.now();
    DateTimeRange selectedDateRange = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day + 7),
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          title: const Row(
            children: [
              Icon(Icons.campaign, color: Colors.red),
              SizedBox(width: 10),
              Text('Marketing Ads / Popup'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.72,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Title',
                    hintText: 'Summer campaign',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Message',
                    hintText: 'Describe the offer or update you want users to see.',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: badgeController,
                  decoration: const InputDecoration(
                    labelText: 'Badge',
                    hintText: 'Featured / Update / Limited Time',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(
                    labelText: 'Action Link (Optional)',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: btnTextController,
                  decoration: const InputDecoration(
                    labelText: 'Button Label',
                    hintText: 'e.g. Visit Website',
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show as popup'),
                  subtitle: const Text('Display immediately in a dialog'),
                  value: showPopup,
                  onChanged: (value) => setState(() => showPopup = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show as banner'),
                  subtitle: const Text('Keep the ad visible in the home feed'),
                  value: showBanner,
                  onChanged: (value) => setState(() => showBanner = value),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                      initialDateRange: selectedDateRange,
                    );
                    if (picked != null && context.mounted) {
                      setState(() => selectedDateRange = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ad start and end date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.date_range_rounded),
                    ),
                    child: Text(
                      '${selectedDateRange.start.year}-${selectedDateRange.start.month.toString().padLeft(2, '0')}-${selectedDateRange.start.day.toString().padLeft(2, '0')}  ->  ${selectedDateRange.end.year}-${selectedDateRange.end.month.toString().padLeft(2, '0')}-${selectedDateRange.end.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          imageFiles.isEmpty
                              ? 'Choose Photos'
                              : 'Add More Photos',
                        ),
                        onPressed: () async {
                          final picked = await ImagePicker().pickMultiImage(
                            maxWidth: 1600,
                            maxHeight: 1600,
                            imageQuality: 85,
                          );
                          if (picked.isNotEmpty && context.mounted) {
                            setState(() {
                              imageFiles.addAll(
                                picked.map((file) => File(file.path)),
                              );
                            });
                          }
                        },
                      ),
                    ),
                    if (imageFiles.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => setState(() => imageFiles.clear()),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                if (imageFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 148,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: imageFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final file = imageFiles[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                file,
                                width: 196,
                                height: 148,
                                fit: BoxFit.cover,
                                cacheWidth: 900,
                                filterQuality: FilterQuality.low,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 196,
                                    height: 148,
                                    color: const Color(0xFFF1F5F9),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.broken_image_outlined),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.55),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 16,
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => setState(
                                    () => imageFiles.removeAt(index),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preview',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (badgeController.text.trim().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeController.text.trim(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (badgeController.text.trim().isNotEmpty)
                        const SizedBox(height: 12),
                      if (imageFiles.isNotEmpty)
                        SizedBox(
                          height: 260,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: imageFiles.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) => ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Image.file(
                                  imageFiles[index],
                                  fit: BoxFit.cover,
                                  cacheWidth: 1000,
                                  filterQuality: FilterQuality.low,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (imageFiles.isNotEmpty) const SizedBox(height: 16),
                      Text(
                        titleController.text.trim().isEmpty
                            ? 'Your ad title'
                            : titleController.text.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        msgController.text.trim().isEmpty
                            ? 'Your message preview will appear here.'
                            : msgController.text.trim(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.86),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final title = titleController.text.trim();
                      final message = msgController.text.trim();
                      final link = linkController.text.trim();
                      final buttonText = btnTextController.text.trim();
                      final badge = badgeController.text.trim();

                      if (title.isEmpty || message.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Title and message are required.'),
                          ),
                        );
                        return;
                      }
                      if (!showPopup && !showBanner) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Choose at least popup or banner before publishing.',
                            ),
                          ),
                        );
                        return;
                      }
                      if (link.isNotEmpty) {
                        final parsed = Uri.tryParse(link);
                        final isValidHttp =
                            parsed != null &&
                            (parsed.scheme == 'http' || parsed.scheme == 'https');
                        if (!isValidHttp) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Link must start with http:// or https://',
                              ),
                            ),
                          );
                          return;
                        }
                      }

                      setState(() => isUploading = true);

                      try {
                        final startsAt = Timestamp.fromDate(
                          DateTime(
                            selectedDateRange.start.year,
                            selectedDateRange.start.month,
                            selectedDateRange.start.day,
                          ),
                        );
                        final expiresAt = Timestamp.fromDate(
                          DateTime(
                            selectedDateRange.end.year,
                            selectedDateRange.end.month,
                            selectedDateRange.end.day,
                            23,
                            59,
                            59,
                          ),
                        );
                        final imageUrls = <String>[];
                        for (var i = 0; i < imageFiles.length; i++) {
                          final ref = FirebaseStorage.instance.ref().child(
                            'ads/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
                          );
                          await ref.putFile(imageFiles[i]);
                          imageUrls.add(await ref.getDownloadURL());
                        }

                        await _firestore.collection('system_announcements').add({
                          'title': title,
                          'message': message,
                          'badge': badge,
                          'imageUrl': imageUrls.isEmpty ? null : imageUrls.first,
                          'imageUrls': imageUrls,
                          'link': link,
                          'buttonText': buttonText.isEmpty
                              ? 'Learn More'
                              : buttonText,
                          'timestamp': FieldValue.serverTimestamp(),
                          'startsAt': startsAt,
                          'expiresAt': expiresAt,
                          'isPopup': showPopup,
                          'showBanner': showBanner,
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Broadcast published successfully.'),
                            ),
                          );
                        }
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to publish broadcast: $e'),
                          ),
                        );
                      } finally {
                        if (context.mounted) {
                          setState(() => isUploading = false);
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Broadcast Now'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRejectDialog(
    String docId,
    String uid,
    String dealerType,
    String businessName,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Verification'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter reason for rejection',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              _handleVerification(
                docId,
                uid,
                false,
                dealerType,
                businessName,
                reason: controller.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleVerification(
    String docId,
    String uid,
    bool approve,
    String dealerType,
    String businessName, {
    String? reason,
  }) async {
    // Immediate feedback to show button click worked
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Approving verification...' : 'Rejecting verification...',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    try {
      final vDoc = await _firestore
          .collection('verifications')
          .doc(docId)
          .get();
      final vData = vDoc.data();
      if (vData == null) return;

      if (approve) {
        // Use set with merge: true to ensure the document exists and updates the requested fields
        await _firestore.collection('users').doc(uid).set({
          'role': 'worker',
          'isapproved': true, // As per request
          'dealertype': dealerType, // As per request
          'isVerified': true,
          'isPro': true,
          'verifiedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Add verification info collection to user collection (as a subcollection)
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('verification_info')
            .doc('latest')
            .set({
              ...vData,
              'approvedAt': FieldValue.serverTimestamp(),
              'status': 'approved',
            });
      } else {
        final String adminUid =
            FirebaseAuth.instance.currentUser?.uid ?? 'admin';

        if (reason != null && reason.isNotEmpty) {
          // Send message to worker in chat room
          final List<String> ids = [adminUid, uid];
          ids.sort();
          final String roomId = ids.join('_');

          await _firestore
              .collection('chat_rooms')
              .doc(roomId)
              .collection('messages')
              .add({
                'senderId': adminUid,
                'receiverId': uid,
                'message':
                    'Your business verification has been rejected. Reason: $reason',
                'type': 'text',
                'timestamp': FieldValue.serverTimestamp(),
              });

          await _firestore.collection('chat_rooms').doc(roomId).set({
            'lastMessage': 'Verification rejected: $reason',
            'lastTimestamp': FieldValue.serverTimestamp(),
            'users': [adminUid, uid],
            'user_names': {adminUid: 'Admin', uid: businessName},
          }, SetOptions(merge: true));

          // Send notification to user collection
          await _firestore
              .collection('users')
              .doc(uid)
              .collection('notifications')
              .add({
                'title': 'Verification Rejected',
                'body': 'Your business verification was rejected: $reason',
                'timestamp': FieldValue.serverTimestamp(),
              });
        }
      }

      // In BOTH cases (Approve/Reject), remove the request from the pending queue
      await _firestore.collection('verifications').doc(docId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Worker Verified Successfully!'
                  : 'Verification Rejected',
            ),
            backgroundColor: approve ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Verification handle error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDeleteUser(String uid, String? name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to permanently delete ${name ?? "this user"}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _firestore.collection('users').doc(uid).delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmBanUser(String uid, String? name, bool currentlyBanned) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(currentlyBanned ? 'Unban User' : 'Ban User'),
        content: Text(
          'Are you sure you want to ${currentlyBanned ? "unban" : "ban"} ${name ?? "this user"}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _firestore.collection('users').doc(uid).update({
                'isBanned': !currentlyBanned,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(
              currentlyBanned ? 'UNBAN' : 'BAN',
              style: TextStyle(
                color: currentlyBanned ? Colors.green : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _removeCategory(String cat) async {
    final metadataRef = _firestore.collection('metadata').doc('professions');
    final snapshot = await metadataRef.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final items = ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    items.removeWhere((item) => item['en']?.toString() == cat);

    await metadataRef.set({
      'list': items.map((item) => item['en'].toString()).toList(),
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _addCategoryDialog(BuildContext context) {
    final enController = TextEditingController();
    final heController = TextEditingController();
    final arController = TextEditingController();
    final ruController = TextEditingController();
    final amController = TextEditingController();
    String selectedIcon = 'engineering';
    String selectedColor = '#1976D2';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Profession'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: enController,
                  decoration: const InputDecoration(
                    labelText: 'Name (English)',
                  ),
                ),
                TextField(
                  controller: heController,
                  decoration: const InputDecoration(labelText: 'Name (Hebrew)'),
                ),
                TextField(
                  controller: arController,
                  decoration: const InputDecoration(labelText: 'Name (Arabic)'),
                ),
                TextField(
                  controller: ruController,
                  decoration: const InputDecoration(
                    labelText: 'Name (Russian)',
                  ),
                ),
                TextField(
                  controller: amController,
                  decoration: const InputDecoration(
                    labelText: 'Name (Amharic)',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Select Icon:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 150,
                  width: double.maxFinite,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                        ),
                    itemCount: _pickerIconKeys.length,
                    itemBuilder: (context, index) {
                      final key = _pickerIconKeys[index];
                      bool isSelected = selectedIcon == key;
                      return IconButton(
                        icon: Icon(
                          _availableIcons[key],
                          color: isSelected ? Colors.red[900] : Colors.grey,
                        ),
                        onPressed: () =>
                            setDialogState(() => selectedIcon = key),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Select Color:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _availableProfessionColors.map((color) {
                        bool isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = color),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(color.replaceFirst('#', '0xFF')),
                              ),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 2)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (enController.text.isEmpty) return;

                final metadataRef = _firestore
                    .collection('metadata')
                    .doc('professions');
                final snapshot = await metadataRef.get();
                final metadata = snapshot.data() ?? <String, dynamic>{};
                final items = ((metadata['items'] as List?) ?? const [])
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList();

                final nextId =
                    items.fold<int>(0, (maxId, item) {
                      final id =
                          int.tryParse(item['id']?.toString() ?? '') ?? 0;
                      return id > maxId ? id : maxId;
                    }) +
                    1;

                final professionData = {
                  'id': nextId,
                  'en': enController.text.trim(),
                  'he': heController.text.trim(),
                  'ar': arController.text.trim(),
                  'ru': ruController.text.trim(),
                  'am': amController.text.trim(),
                  'logo': selectedIcon,
                  'color': selectedColor,
                  'updatedAt': Timestamp.now(),
                };

                items.add(professionData);
                items.sort((a, b) {
                  final aId =
                      int.tryParse(a['id']?.toString() ?? '') ?? 1 << 30;
                  final bId =
                      int.tryParse(b['id']?.toString() ?? '') ?? 1 << 30;
                  return aId.compareTo(bId);
                });

                await metadataRef.set({
                  'list': items.map((item) => item['en'].toString()).toList(),
                  'items': items,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value?.toString() ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildViewDocButton(String label, String? url) {
    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.file_present_rounded, color: Colors.red),
          onPressed: () async {
            if (url != null && url.isNotEmpty) {
              final Uri uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
        ),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  //BkmvData.txt + INI.txt generation functions
  Future<void> _generateBkmvDataFile() async {
    try {
      final selectedRange = await _pickExportDateRange();
      if (selectedRange == null) return;

      final fromDate = _formatCompactDate(selectedRange.start);
      final toDate = _formatCompactDate(selectedRange.end);
      final systemSettings =
          await _firestore.collection('metadata').doc('system').get();
      final settingsData = systemSettings.data() ?? <String, dynamic>{};
      final businessNumber = (settingsData['businessNumber'] ?? '').toString();
      final businessName = (settingsData['businessName'] ?? '').toString();
      final softwareName = (settingsData['appName'] ?? 'hiro').toString();
      final appVersion =
          (settingsData['minRequiredVersion'] ?? '1.0.0').toString();
      final bucketNames = ['invoices', 'receipts', 'credit_notes'];
      final snapshots = await Future.wait(
        bucketNames.map(
          (bucket) => _firestore
              .collection('logs')
              .doc(bucket)
              .collection('files')
              .where('date', isGreaterThanOrEqualTo: fromDate)
              .where('date', isLessThanOrEqualTo: toDate)
              .orderBy('date')
              .orderBy('timestamp')
              .get(),
        ),
      );

      final allDocs = snapshots.expand((snap) => snap.docs).toList()
        ..sort((a, b) {
          final aData = a.data();
          final bData = b.data();
          final dateCompare = (aData['date'] ?? '')
              .toString()
              .compareTo((bData['date'] ?? '').toString());
          if (dateCompare != 0) return dateCompare;

          final aTs = aData['timestamp'] as Timestamp?;
          final bTs = bData['timestamp'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return -1;
          if (bTs == null) return 1;
          return aTs.compareTo(bTs);
        });

      final lines = <String>[
        'Z900|$businessNumber|$businessName|$fromDate|$toDate|',
      ];
      for (final doc in allDocs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString();
        final documentNumber = (data['documentNumber'] ?? '').toString();
        final date = (data['date'] ?? '').toString();
        final amount = ((data['amount'] as num?) ?? 0).toStringAsFixed(2);
        final vatAmount = ((data['vatAmount'] as num?) ?? 0).toStringAsFixed(2);
        final customerId = (data['customerId'] ?? '').toString();
        lines.add(
          '$type|$documentNumber|$date|$amount|$vatAmount|$customerId',
        );
      }
      lines.add('FOOTER|END');

      final bkmvContent = lines.join('\n');
      final iniContent = '''
[General]
COMPANY=$businessName
ID=$businessNumber
FROMDATE=$fromDate
TODATE=$toDate
SOFTWARE=$softwareName
VERSION=$appVersion
''';

      final directory = await _getBkmvExportDirectory();
      final bkmvFile = File('${directory.path}${Platform.pathSeparator}BKMVDATA.txt');
      final iniFile = File('${directory.path}${Platform.pathSeparator}INI.txt');
      await bkmvFile.writeAsString(bkmvContent);
      await iniFile.writeAsString(iniContent);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(bkmvFile.path),
            XFile(iniFile.path),
          ],
          text: 'BKMVDATA export files',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'BKMVDATA exports prepared in: ${directory.path}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _UserManagementSheet extends StatefulWidget {
  final String title;
  final String role;
  final FirebaseFirestore firestore;
  final Function(String, String?) onDelete;
  final Function(String, String?, bool) onBan;

  const _UserManagementSheet({
    required this.title,
    required this.role,
    required this.firestore,
    required this.onDelete,
    required this.onBan,
  });

  @override
  State<_UserManagementSheet> createState() => _UserManagementSheetState();
}

class _UserManagementSheetState extends State<_UserManagementSheet> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.firestore
                  .collection('users')
                  .where('role', isEqualTo: widget.role)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData)
                  return const Center(child: Text('No data found'));

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? "").toString().toLowerCase();
                  final phone = (data['phone'] ?? "").toString().toLowerCase();
                  return name.contains(_searchQuery) ||
                      phone.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty)
                  return const Center(child: Text('No matching entries found'));

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final user = docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;
                    final bool isBanned = user['isBanned'] ?? false;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            (user['profileImageUrl'] != null &&
                                user['profileImageUrl'].toString().isNotEmpty)
                            ? NetworkImage(user['profileImageUrl'])
                            : null,
                        child:
                            (user['profileImageUrl'] == null ||
                                user['profileImageUrl'].toString().isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(user['name'] ?? 'No Name')),
                          if (isBanned)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'BANNED',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${user['phone'] ?? 'No Phone'}${widget.role == 'worker' ? ' • ${user['profession'] ?? "Worker"}' : ""}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.visibility_outlined,
                              color: Colors.blue,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Profile(userId: uid),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isBanned
                                  ? Icons.gavel_rounded
                                  : Icons.block_flipped,
                              color: isBanned ? Colors.green : Colors.orange,
                            ),
                            onPressed: () =>
                                widget.onBan(uid, user['name'], isBanned),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => widget.onDelete(uid, user['name']),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfessionCategoriesSheet extends StatefulWidget {
  final FirebaseFirestore firestore;
  final Map<String, IconData> availableIcons;
  final VoidCallback onAddSingle;

  const _ProfessionCategoriesSheet({
    required this.firestore,
    required this.availableIcons,
    required this.onAddSingle,
  });

  @override
  State<_ProfessionCategoriesSheet> createState() =>
      _ProfessionCategoriesSheetState();
}

class _ProfessionCategoriesSheetState extends State<_ProfessionCategoriesSheet> {
  bool _isUploadingImport = false;
  List<Map<String, dynamic>> _previewItems = const [];
  String? _previewFileName;

  List<String> get _pickerIconKeys => _deduplicateIconKeys(widget.availableIcons);

  static List<String> _deduplicateIconKeys(Map<String, IconData> icons) {
    final uniqueKeys = <String>[];
    final seenSignatures = <String>{};
    for (final entry in icons.entries) {
      final icon = entry.value;
      final signature =
          '${icon.fontFamily}|${icon.fontPackage}|${icon.codePoint}|${icon.matchTextDirection}';
      if (seenSignatures.add(signature)) {
        uniqueKeys.add(entry.key);
      }
    }
    return uniqueKeys;
  }

  int _nextProfessionId(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (maxId, item) {
          final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
          return id > maxId ? id : maxId;
        }) +
        1;
  }

  String _normalizeHexColor(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '#1976D2';
    final cleaned = raw.startsWith('#') ? raw.substring(1) : raw;
    final valid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned);
    return valid ? '#${cleaned.toUpperCase()}' : '#1976D2';
  }

  Color _colorFromHex(String? value) {
    final hex = _normalizeHexColor(value).replaceFirst('#', '');
    return Color(int.parse('0xFF$hex'));
  }

  List<Map<String, dynamic>> _itemsFromMetadata(Map<String, dynamic>? data) {
    return ((data?['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _normalizeImportedProfessionItem(
    Map<String, dynamic> raw,
    int fallbackId,
  ) {
    final logo = (raw['logo'] ?? raw['icon'] ?? 'engineering').toString();
    final resolvedLogo = widget.availableIcons.containsKey(logo)
        ? logo
        : 'engineering';
    return {
      'id': int.tryParse(raw['id']?.toString() ?? '') ?? fallbackId,
      'en': (raw['en'] ?? '').toString().trim(),
      'he': (raw['he'] ?? '').toString().trim(),
      'ar': (raw['ar'] ?? '').toString().trim(),
      'ru': (raw['ru'] ?? '').toString().trim(),
      'am': (raw['am'] ?? '').toString().trim(),
      'logo': resolvedLogo,
      'color': _normalizeHexColor(raw['color']?.toString()),
      'updatedAt': Timestamp.now(),
    };
  }

  List<Map<String, dynamic>> _parseImportedProfessionItems(String rawJson) {
    final decoded = jsonDecode(rawJson);
    final List<dynamic> rawItems;
    if (decoded is List) {
      rawItems = decoded;
    } else if (decoded is Map && decoded['items'] is List) {
      rawItems = List<dynamic>.from(decoded['items']);
    } else {
      throw const FormatException(
        'JSON must be a list or an object with an "items" list.',
      );
    }

    final normalized = <Map<String, dynamic>>[];
    var fallbackId = 1;
    for (final item in rawItems) {
      if (item is! Map) continue;
      final normalizedItem = _normalizeImportedProfessionItem(
        Map<String, dynamic>.from(item),
        fallbackId,
      );
      if ((normalizedItem['en'] ?? '').toString().trim().isEmpty) continue;
      normalized.add(normalizedItem);
      fallbackId += 1;
    }
    return normalized;
  }

  Future<void> _saveProfessionItems(List<Map<String, dynamic>> items) async {
    items.sort((a, b) {
      final aId = int.tryParse(a['id']?.toString() ?? '') ?? 1 << 30;
      final bId = int.tryParse(b['id']?.toString() ?? '') ?? 1 << 30;
      return aId.compareTo(bId);
    });

    await widget.firestore.collection('metadata').doc('professions').set({
      'list': items
          .map((item) => item['en']?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(),
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _removeCategoryByEn(String cat) async {
    final metadataRef = widget.firestore.collection('metadata').doc('professions');
    final snapshot = await metadataRef.get();
    final items = _itemsFromMetadata(snapshot.data());
    items.removeWhere(
      (item) => item['en']?.toString().toLowerCase() == cat.toLowerCase(),
    );
    await _saveProfessionItems(items);
  }

  Future<void> _editExistingItem(Map<String, dynamic> item) async {
    final enController = TextEditingController(text: item['en']?.toString() ?? '');
    final heController = TextEditingController(text: item['he']?.toString() ?? '');
    final arController = TextEditingController(text: item['ar']?.toString() ?? '');
    final ruController = TextEditingController(text: item['ru']?.toString() ?? '');
    final amController = TextEditingController(text: item['am']?.toString() ?? '');
    final idController = TextEditingController(text: item['id']?.toString() ?? '');
    final colorController = TextEditingController(
      text: item['color']?.toString() ?? '#1976D2',
    );
    String selectedIcon = item['logo']?.toString() ?? 'engineering';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Profession'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ID'),
                  ),
                  TextField(
                    controller: enController,
                    decoration: const InputDecoration(labelText: 'English'),
                  ),
                  TextField(
                    controller: heController,
                    decoration: const InputDecoration(labelText: 'Hebrew'),
                  ),
                  TextField(
                    controller: arController,
                    decoration: const InputDecoration(labelText: 'Arabic'),
                  ),
                  TextField(
                    controller: ruController,
                    decoration: const InputDecoration(labelText: 'Russian'),
                  ),
                  TextField(
                    controller: amController,
                    decoration: const InputDecoration(labelText: 'Amharic'),
                  ),
                  TextField(
                    controller: colorController,
                    decoration: const InputDecoration(labelText: 'Color (#RRGGBB)'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _AdminPanelState._availableProfessionColors.map((color) {
                      final isSelected =
                          _normalizeHexColor(colorController.text) == color;
                      return GestureDetector(
                        onTap: () => setDialogState(() => colorController.text = color),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _colorFromHex(color),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Icon',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _colorFromHex(colorController.text),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.availableIcons[selectedIcon] ?? Icons.engineering,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    width: double.maxFinite,
                    child: GridView.builder(
                      itemCount: _pickerIconKeys.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                          ),
                      itemBuilder: (context, iconIndex) {
                        final key = _pickerIconKeys[iconIndex];
                        final isSelected = selectedIcon == key;
                        return IconButton(
                          onPressed: () => setDialogState(() => selectedIcon = key),
                          icon: Icon(
                            widget.availableIcons[key],
                            color: isSelected ? Colors.red[900] : Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final originalKey =
                    item['en']?.toString().trim().toLowerCase() ?? '';
                final updated = Map<String, dynamic>.from(item);
                updated['id'] =
                    int.tryParse(idController.text.trim()) ?? item['id'];
                updated['en'] = enController.text.trim();
                updated['he'] = heController.text.trim();
                updated['ar'] = arController.text.trim();
                updated['ru'] = ruController.text.trim();
                updated['am'] = amController.text.trim();
                updated['logo'] = selectedIcon;
                updated['color'] = _normalizeHexColor(colorController.text);
                updated['updatedAt'] = Timestamp.now();
                if ((updated['en'] ?? '').toString().isEmpty) return;

                final metadataRef =
                    widget.firestore.collection('metadata').doc('professions');
                final snapshot = await metadataRef.get();
                final items = _itemsFromMetadata(snapshot.data());
                final index = items.indexWhere(
                  (entry) =>
                      entry['en']?.toString().trim().toLowerCase() == originalKey,
                );
                if (index == -1) return;
                items[index] = updated;
                await _saveProfessionItems(items);
                if (!mounted) return;
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndPreviewJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      String rawJson;
      if (bytes != null) {
        rawJson = utf8.decode(bytes);
      } else if (file.path != null) {
        rawJson = await File(file.path!).readAsString();
      } else {
        throw const FormatException('Could not read the selected JSON file.');
      }

      final parsedItems = _parseImportedProfessionItems(rawJson);
      if (!mounted) return;
      if (parsedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid profession items found in JSON.')),
        );
        return;
      }
      setState(() {
        _previewItems = parsedItems;
        _previewFileName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editPreviewItem(int index) async {
    final item = Map<String, dynamic>.from(_previewItems[index]);
    final enController = TextEditingController(text: item['en']?.toString() ?? '');
    final heController = TextEditingController(text: item['he']?.toString() ?? '');
    final arController = TextEditingController(text: item['ar']?.toString() ?? '');
    final ruController = TextEditingController(text: item['ru']?.toString() ?? '');
    final amController = TextEditingController(text: item['am']?.toString() ?? '');
    final idController = TextEditingController(text: item['id']?.toString() ?? '');
    final colorController = TextEditingController(
      text: item['color']?.toString() ?? '#1976D2',
    );
    String selectedIcon = item['logo']?.toString() ?? 'engineering';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Imported Profession'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ID'),
                  ),
                  TextField(
                    controller: enController,
                    decoration: const InputDecoration(labelText: 'English'),
                  ),
                  TextField(
                    controller: heController,
                    decoration: const InputDecoration(labelText: 'Hebrew'),
                  ),
                  TextField(
                    controller: arController,
                    decoration: const InputDecoration(labelText: 'Arabic'),
                  ),
                  TextField(
                    controller: ruController,
                    decoration: const InputDecoration(labelText: 'Russian'),
                  ),
                  TextField(
                    controller: amController,
                    decoration: const InputDecoration(labelText: 'Amharic'),
                  ),
                  TextField(
                    controller: colorController,
                    decoration: const InputDecoration(labelText: 'Color (#RRGGBB)'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _AdminPanelState._availableProfessionColors.map((color) {
                      final isSelected =
                          _normalizeHexColor(colorController.text) == color;
                      return GestureDetector(
                        onTap: () => setDialogState(() => colorController.text = color),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _colorFromHex(color),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Icon',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _colorFromHex(colorController.text),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.availableIcons[selectedIcon] ?? Icons.engineering,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    width: double.maxFinite,
                    child: GridView.builder(
                      itemCount: _pickerIconKeys.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                          ),
                      itemBuilder: (context, iconIndex) {
                        final key = _pickerIconKeys[iconIndex];
                        final isSelected = selectedIcon == key;
                        return IconButton(
                          onPressed: () => setDialogState(() => selectedIcon = key),
                          icon: Icon(
                            widget.availableIcons[key],
                            color: isSelected ? Colors.red[900] : Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final updated = Map<String, dynamic>.from(item);
                updated['id'] =
                    int.tryParse(idController.text.trim()) ?? item['id'] ?? index + 1;
                updated['en'] = enController.text.trim();
                updated['he'] = heController.text.trim();
                updated['ar'] = arController.text.trim();
                updated['ru'] = ruController.text.trim();
                updated['am'] = amController.text.trim();
                updated['logo'] = selectedIcon;
                updated['color'] = _normalizeHexColor(colorController.text);
                if ((updated['en'] ?? '').toString().isEmpty) return;
                setState(() {
                  _previewItems[index] = updated;
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadPreviewItems() async {
    if (_previewItems.isEmpty) return;
    setState(() => _isUploadingImport = true);
    try {
      final metadataRef = widget.firestore.collection('metadata').doc('professions');
      final snapshot = await metadataRef.get();
      final existingItems = _itemsFromMetadata(snapshot.data());
      final byEn = <String, Map<String, dynamic>>{
        for (final item in existingItems)
          (item['en']?.toString().trim().toLowerCase() ?? ''): item,
      };

      var nextId = _nextProfessionId(existingItems);
      for (final imported in _previewItems) {
        final key = imported['en']?.toString().trim().toLowerCase() ?? '';
        if (key.isEmpty) continue;
        final merged = Map<String, dynamic>.from(imported);
        if ((merged['id'] == null ||
                int.tryParse(merged['id']?.toString() ?? '') == null) &&
            byEn[key] == null) {
          merged['id'] = nextId++;
        } else if (byEn[key] != null) {
          merged['id'] = merged['id'] ?? byEn[key]!['id'];
        }
        byEn[key] = merged;
      }

      final finalItems = byEn.values.toList();
      await _saveProfessionItems(finalItems);
      if (!mounted) return;
      setState(() {
        _previewItems = const [];
        _previewFileName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported professions uploaded successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingImport = false);
      }
    }
  }

  Widget _buildPreviewCard(Map<String, dynamic> item, int index) {
    final logoKey = item['logo']?.toString() ?? 'engineering';
    final icon = widget.availableIcons[logoKey] ?? Icons.engineering;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _colorFromHex(item['color']?.toString()),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['en']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text('ID: ${item['id'] ?? '-'}'),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _editPreviewItem(index),
                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _previewItems = List<Map<String, dynamic>>.from(_previewItems)
                        ..removeAt(index);
                    });
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaChip('he', item['he']),
                _buildMetaChip('ar', item['ar']),
                _buildMetaChip('ru', item['ru']),
                _buildMetaChip('am', item['am']),
                _buildMetaChip('logo', logoKey),
                _buildMetaChip('color', item['color']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: ${value?.toString() ?? ''}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Profession Categories',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Import JSON',
                  onPressed: _pickAndPreviewJson,
                  icon: const Icon(Icons.upload_file_rounded, color: Colors.deepPurple),
                ),
                IconButton(
                  tooltip: 'Add manually',
                  onPressed: widget.onAddSingle,
                  icon: const Icon(Icons.add_box_rounded, color: Colors.blue),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_previewItems.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              color: const Color(0xFFF8FAFC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import Preview${_previewFileName != null ? ' • $_previewFileName' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review, edit, or delete items below. Nothing is uploaded until you press Upload Import.',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isUploadingImport ? null : _uploadPreviewItems,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _isUploadingImport ? 'Uploading...' : 'Upload Import',
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: _isUploadingImport
                            ? null
                            : () {
                                setState(() {
                                  _previewItems = const [];
                                  _previewFileName = null;
                                });
                              },
                        child: const Text('Clear Preview'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: widget.firestore
                  .collection('metadata')
                  .doc('professions')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data =
                    snapshot.data?.data() as Map<String, dynamic>? ?? <String, dynamic>{};
                final items = _itemsFromMetadata(data)
                  ..sort((a, b) {
                    final aId = int.tryParse(a['id']?.toString() ?? '') ?? 1 << 30;
                    final bId = int.tryParse(b['id']?.toString() ?? '') ?? 1 << 30;
                    return aId.compareTo(bId);
                  });

                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    if (_previewItems.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          'Preview Items',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...List.generate(
                        _previewItems.length,
                        (index) => _buildPreviewCard(_previewItems[index], index),
                      ),
                      const Divider(height: 28),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'Current Metadata Items',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No profession entries found')),
                      )
                    else
                      ...items.map((item) {
                        final cat = item['en']?.toString() ?? '';
                        return ListTile(
                          onTap: () => _editExistingItem(item),
                          title: Text(cat),
                          subtitle: Text(
                            'ID ${item['id'] ?? '-'} • ${item['he'] ?? ''} • ${item['ar'] ?? ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => _removeCategoryByEn(cat),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBottomSheet extends StatelessWidget {
  final String title;
  final Stream stream;
  final Widget Function(BuildContext, dynamic) itemBuilder;
  final bool isListStream;
  final List<Widget>? actions;

  const _AdminBottomSheet({
    required this.title,
    required this.stream,
    required this.itemBuilder,
    this.isListStream = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (actions != null) Row(children: actions!),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData)
                  return const Center(child: Text('No data found'));

                final List items = isListStream
                    ? (snapshot.data as List)
                    : (snapshot.data as QuerySnapshot).docs;
                if (items.isEmpty)
                  return const Center(child: Text('No entries found'));

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      itemBuilder(context, items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
