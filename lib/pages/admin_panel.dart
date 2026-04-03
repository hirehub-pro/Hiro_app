import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/ptofile.dart';

class AdminPanel extends StatefulWidget {
  final bool showAppBar;
  const AdminPanel({super.key, this.showAppBar = true});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, IconData> _availableIcons = {
    'plumbing': Icons.plumbing,
    'electrical_services': Icons.electrical_services,
    'carpenter': Icons.carpenter,
    'format_paint': Icons.format_paint,
    'vpn_key': Icons.vpn_key,
    'park': Icons.park,
    'ac_unit': Icons.ac_unit,
    'cleaning_services': Icons.cleaning_services,
    'build': Icons.build,
    'handyman': Icons.handyman,
    'foundation': Icons.foundation,
    'grid_view': Icons.grid_view,
    'settings': Icons.settings,
    'home_repair_service': Icons.home_repair_service,
    'computer': Icons.computer,
    'content_cut': Icons.content_cut,
    'checkroom': Icons.checkroom,
    'local_shipping': Icons.local_shipping,
    'pest_control': Icons.pest_control,
    'solar_power': Icons.solar_power,
    'chair': Icons.chair,
    'format_shapes': Icons.format_shapes,
    'architecture': Icons.architecture,
    'school': Icons.school,
    'child_care': Icons.child_care,
    'photo_camera': Icons.photo_camera,
    'music_note': Icons.music_note,
    'face': Icons.face,
    'medical_services': Icons.medical_services,
    'self_improvement': Icons.self_improvement,
    'window': Icons.window,
    'pool': Icons.pool,
    'fitness_center': Icons.fitness_center,
    'pets': Icons.pets,
    'home': Icons.home,
    'waves': Icons.waves,
    'dry_cleaning': Icons.dry_cleaning,
    'event': Icons.event,
    'restaurant': Icons.restaurant,
    'security': Icons.security,
    'delivery_dining': Icons.delivery_dining,
    'local_car_wash': Icons.local_car_wash,
    'spa': Icons.spa,
    'restaurant_menu': Icons.restaurant_menu,
    'flight': Icons.flight,
    'real_estate_agent': Icons.real_estate_agent,
    'gavel': Icons.gavel,
    'calculate': Icons.calculate,
    'translate': Icons.translate,
    'format_color_fill': Icons.format_color_fill,
    'square_foot': Icons.square_foot,
    'videocam': Icons.videocam,
    'public': Icons.public,
    'psychology': Icons.psychology,
    'add_a_photo': Icons.add_a_photo,
    'flight_takeoff': Icons.flight_takeoff,
    'piano': Icons.piano,
    'language': Icons.language,
    'functions': Icons.functions,
    'science': Icons.science,
    'biotech': Icons.biotech,
    'eco': Icons.eco,
    'history_edu': Icons.history_edu,
    'palette': Icons.palette,
    'pedal_bike': Icons.pedal_bike,
    'engineering': Icons.engineering,
  };

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
      builder: (context) => _AdminBottomSheet(
        title: 'Profession Categories',
        stream: _firestore
            .collection('metadata')
            .doc('professions')
            .snapshots()
            .map(
              (s) => s.exists
                  ? (s.data() as Map<String, dynamic>)['list'] as List
                  : [],
            ),
        isListStream: true,
        itemBuilder: (context, item) {
          final String cat = item.toString();
          return ListTile(
            title: Text(cat),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => _removeCategory(cat),
            ),
          );
        },
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded, color: Colors.blue),
            onPressed: () => _addCategoryDialog(context),
          ),
        ],
      ),
    );
  }

  void _showMarketingBroadcastDialog(BuildContext context) {
    final titleController = TextEditingController();
    final msgController = TextEditingController();
    final linkController = TextEditingController();
    final btnTextController = TextEditingController(text: 'Learn More');
    File? imageFile;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.campaign, color: Colors.red),
              SizedBox(width: 10),
              Text('Marketing Ads / Popup'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Title',
                    hintText: 'Special Announcement',
                  ),
                ),
                TextField(
                  controller: msgController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Message',
                    hintText: 'Write your message here...',
                  ),
                  maxLines: 3,
                ),
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(
                    labelText: 'Action Link (Optional)',
                    hintText: 'https://...',
                  ),
                ),
                TextField(
                  controller: btnTextController,
                  decoration: const InputDecoration(
                    labelText: 'Button Label',
                    hintText: 'e.g. Visit Website',
                  ),
                ),
                const SizedBox(height: 16),
                if (imageFile != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          imageFile!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          onPressed: () => setState(() => imageFile = null),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_a_photo),
                    label: const Text('Pick Ad Image'),
                    onPressed: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null)
                        setState(() => imageFile = File(picked.path));
                    },
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
              onPressed: isUploading
                  ? null
                  : () async {
                      if (titleController.text.isEmpty ||
                          msgController.text.isEmpty)
                        return;
                      setState(() => isUploading = true);

                      String? imageUrl;
                      if (imageFile != null) {
                        final ref = FirebaseStorage.instance.ref().child(
                          'ads/${DateTime.now().millisecondsSinceEpoch}.jpg',
                        );
                        await ref.putFile(imageFile!);
                        imageUrl = await ref.getDownloadURL();
                      }

                      await _firestore.collection('system_announcements').add({
                        'title': titleController.text,
                        'message': msgController.text,
                        'imageUrl': imageUrl,
                        'link': linkController.text,
                        'buttonText': btnTextController.text,
                        'timestamp': FieldValue.serverTimestamp(),
                        'isPopup': true, // To show as an urgent popup
                      });

                      if (context.mounted) Navigator.pop(context);
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
                    itemCount: _availableIcons.length,
                    itemBuilder: (context, index) {
                      String key = _availableIcons.keys.elementAt(index);
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
                  children:
                      [
                        '#1976D2',
                        '#D32F2F',
                        '#388E3C',
                        '#FBC02D',
                        '#7B1FA2',
                        '#E64A19',
                        '#455A64',
                      ].map((color) {
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
