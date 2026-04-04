import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/map/map_radius_picker.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/utils/profession_localization.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _altPhoneController;
  late TextEditingController _descriptionController;
  late TextEditingController _townController;
  TextEditingController? _professionsSearchController;

  String? _selectedTown;
  List<String> _selectedProfessions = [];
  File? _image;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  double _workRadius = 25000.0;
  LatLng? _workCenter;

  final List<String> _allProfessions =
      ProfessionLocalization.canonicalProfessions;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userData['name']);
    _emailController = TextEditingController(text: widget.userData['email']);
    _phoneController = TextEditingController(text: widget.userData['phone']);
    _altPhoneController = TextEditingController(
      text: widget.userData['optionalPhone'],
    );
    _descriptionController = TextEditingController(
      text: widget.userData['description'] ?? widget.userData['bio'],
    );
    _selectedTown = widget.userData['town'];
    _townController = TextEditingController(text: _selectedTown);
    _selectedProfessions = List<String>.from(
      widget.userData['professions'] ?? [],
    ).map(ProfessionLocalization.toCanonical).toList();

    _workRadius = (widget.userData['workRadius'] ?? 25000.0).toDouble();
    if (widget.userData['workCenterLat'] != null &&
        widget.userData['workCenterLng'] != null) {
      _workCenter = LatLng(
        widget.userData['workCenterLat'],
        widget.userData['workCenterLng'],
      );
    } else if (widget.userData['lat'] != null &&
        widget.userData['lng'] != null) {
      _workCenter = LatLng(widget.userData['lat'], widget.userData['lng']);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _descriptionController.dispose();
    _townController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) setState(() => _image = File(picked.path));
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      }

      Position position = await Geolocator.getCurrentPosition();
      LatLng loc = LatLng(position.latitude, position.longitude);
      setState(() {
        _workCenter = loc;
      });
      await _updateTownFromLocation(loc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateTownFromLocation(LatLng loc) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        String? town =
            placemarks.first.locality ?? placemarks.first.subLocality;
        if (town != null && town.isNotEmpty) {
          setState(() {
            _selectedTown = town;
            _townController.text = town;
          });
        }
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      double? lat = _workCenter?.latitude;
      double? lng = _workCenter?.longitude;

      if (lat == null && _selectedTown != null && _selectedTown!.isNotEmpty) {
        try {
          List<Location> locations = await locationFromAddress(
            "$_selectedTown, Israel",
          );
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (e) {
          debugPrint("Geocoding error: $e");
        }
      }

      String? imageUrl;
      if (_image != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'profile_pictures/${user.uid}.jpg',
        );
        await ref.putFile(_image!);
        imageUrl = await ref.getDownloadURL();
      }

      final updateData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'town': _selectedTown,
        'lat': lat,
        'lng': lng,
        'workRadius': _workRadius,
        'workCenterLat': _workCenter?.latitude,
        'workCenterLng': _workCenter?.longitude,
        'optionalPhone': _altPhoneController.text.trim(),
        'description': _descriptionController.text.trim(),
        'professions': _selectedProfessions,
      };

      if (imageUrl != null) {
        updateData['profileImageUrl'] = imageUrl;
      }

      // Update in the unified 'users' collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updateData);
      await user.updateDisplayName(_nameController.text.trim());

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, String> _getLocalizedStrings() {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'עריכת פרופיל',
          'basic_info': 'פרטים בסיסיים',
          'service_details': 'פרטי שירות',
          'about_you': 'עליך',
          'name': 'שם מלא',
          'email': 'אימייל',
          'phone': 'מספר טלפון',
          'town': 'עיר',
          'professions': 'בחר מקצועות',
          'alt_phone': 'טלפון נוסף (אופציונלי)',
          'desc': 'ספר על עצמך (אופציונלי)',
          'save': 'שמור שינויים',
          'req': 'שדה חובה',
          'search': 'חפש...',
          'work_radius': 'רדיוס עבודה',
          'select_radius': 'בחר רדיוס על המפה',
          'radius_val': 'רדיוס: {val} ק"מ',
          'current_loc': 'השתמש במיקום נוכחי',
          'pick_map': 'בחר מהמפה',
          'location_info': 'מיקום מדויק עוזר למצוא אותך בקלות',
        };
      default:
        return {
          'title': 'Edit Profile',
          'basic_info': 'Basic Information',
          'service_details': 'Service Details',
          'about_you': 'About You',
          'name': 'Full Name',
          'email': 'Email',
          'phone': 'Phone Number',
          'town': 'City',
          'professions': 'Select Professions',
          'alt_phone': 'Alt Phone (Optional)',
          'desc': 'Description (Optional)',
          'save': 'Save Changes',
          'req': 'Required',
          'search': 'Search...',
          'work_radius': 'Work Radius',
          'select_radius': 'Select radius on Map',
          'radius_val': 'Radius: {val} km',
          'current_loc': 'Use Current Location',
          'pick_map': 'Select on Map',
          'location_info': 'Precise location helps others find you easily',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings();
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(strings),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildImagePicker(),
                            const SizedBox(height: 24),
                            _buildSectionCard(
                              title: strings['basic_info']!,
                              child: Column(
                                children: [
                                  _buildStyledTextField(
                                    controller: _nameController,
                                    labelText: strings['name']!,
                                    icon: Icons.person_outline,
                                    validator: (v) =>
                                        v!.isEmpty ? strings['req'] : null,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildStyledTextField(
                                    controller: _emailController,
                                    labelText: strings['email']!,
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildLocationSection(strings),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (widget.userData['role'] == 'worker') ...[
                              _buildSectionCard(
                                title: strings['service_details']!,
                                child: Column(
                                  children: [
                                    _buildWorkRadiusSelector(strings),
                                    const SizedBox(height: 16),
                                    _buildMultiSelectProfessions(strings),
                                    const SizedBox(height: 16),
                                    _buildStyledTextField(
                                      controller: _altPhoneController,
                                      labelText: strings['alt_phone']!,
                                      icon: Icons.phone_android_outlined,
                                      keyboardType: TextInputType.phone,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildSectionCard(
                              title: strings['about_you']!,
                              child: Column(
                                children: [
                                  _buildStyledTextField(
                                    controller: _phoneController,
                                    labelText: strings['phone']!,
                                    icon: Icons.phone_android_outlined,
                                    keyboardType: TextInputType.phone,
                                    enabled: false,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildStyledTextField(
                                    controller: _descriptionController,
                                    labelText: strings['desc']!,
                                    icon: Icons.description_outlined,
                                    maxLines: 3,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            _buildSaveButton(strings),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLocationSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStyledTextField(
          controller: _townController,
          labelText: strings['town']!,
          icon: Icons.location_on_outlined,
          readOnly: true,
          onTap: _openMapPicker,
          validator: (v) => (v == null || v.isEmpty) ? strings['req'] : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(
                  strings['current_loc']!,
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openMapPicker,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(
                  strings['pick_map']!,
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF1976D2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openMapPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPicker(initialCenter: _workCenter),
      ),
    );
    if (result != null && result is LatLng) {
      setState(() {
        _workCenter = result;
      });
      _updateTownFromLocation(result);
    }
  }

  Widget _buildWorkRadiusSelector(Map<String, String> strings) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: Color(0xFF1976D2)),
              const SizedBox(width: 12),
              Text(
                strings['work_radius']!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                strings['radius_val']!.replaceFirst(
                  '{val}',
                  (_workRadius / 1000).toStringAsFixed(1),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapRadiusPicker(
                        initialCenter: _workCenter,
                        initialRadius: _workRadius,
                      ),
                    ),
                  );
                  if (result != null) {
                    setState(() {
                      _workCenter = result['center'];
                      _workRadius = result['radius'];
                    });
                    if (_workCenter != null) {
                      _updateTownFromLocation(_workCenter!);
                    }
                  }
                },
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(strings['select_radius']!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, String> strings) {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Center(
            child: Text(
              strings['title']!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF60A5FA)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 58,
              backgroundColor: const Color(0xFFF1F5F9),
              backgroundImage: _image != null
                  ? FileImage(_image!)
                  : (widget.userData['profileImageUrl'] != null &&
                                widget.userData['profileImageUrl'].isNotEmpty
                            ? NetworkImage(widget.userData['profileImageUrl'])
                            : null)
                        as ImageProvider?,
              child:
                  _image == null &&
                      (widget.userData['profileImageUrl'] == null ||
                          widget.userData['profileImageUrl'].isEmpty)
                  ? Icon(
                      Icons.person_rounded,
                      size: 56,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    String? hintText,
    bool enabled = true,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(icon, color: const Color(0xFF1976D2)),
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFE2E8F0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildMultiSelectProfessions(Map<String, String> strings) {
    final localeCode = Provider.of<LanguageProvider>(
      context,
    ).locale.languageCode;
    final localizedOptions = _allProfessions
        .map((p) => ProfessionLocalization.toLocalized(p, localeCode))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return localizedOptions;
              }
              return localizedOptions.where((String option) {
                return option.toLowerCase().contains(
                  textEditingValue.text.toLowerCase(),
                );
              });
            },
            onSelected: (String selection) {
              final canonical = ProfessionLocalization.toCanonical(selection);
              setState(() {
                if (!_selectedProfessions.contains(canonical)) {
                  _selectedProfessions.add(canonical);
                }
              });
              _professionsSearchController?.clear();
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 250,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return ListTile(
                          title: Text(option),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  _professionsSearchController = controller;
                  return _buildStyledTextField(
                    controller: controller,
                    labelText: strings['professions']!,
                    icon: Icons.work_outline,
                    focusNode: focusNode,
                    hintText: strings['search'],
                  );
                },
          ),
        ),
        if (_selectedProfessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedProfessions
                .map(
                  (prof) => Chip(
                    label: Text(
                      ProfessionLocalization.toLocalized(prof, localeCode),
                    ),
                    onDeleted: () {
                      setState(() {
                        _selectedProfessions.remove(prof);
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveButton(Map<String, String> strings) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF1976D2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          strings['save']!,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
