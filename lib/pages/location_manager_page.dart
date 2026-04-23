import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/location_context_service.dart';

class LocationManagerPage extends StatefulWidget {
  const LocationManagerPage({super.key});

  @override
  State<LocationManagerPage> createState() => _LocationManagerPageState();
}

class _LocationManagerPageState extends State<LocationManagerPage> {
  bool _isLoading = true;
  String _activeId = AppLocation.currentId;
  List<AppLocation> _saved = [];
  AppLocation? _currentDeviceLocation;

  Map<String, String> _strings(BuildContext context) {
    final code = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (code) {
      case 'he':
        return {
          'delete_location': 'מחיקת מיקום',
          'remove_saved': 'להסיר את "{label}" מהמיקומים השמורים?',
          'cancel': 'ביטול',
          'delete': 'מחק',
          'current_prefix': 'נוכחי',
          'map_prefix': 'מפה',
          'edit_location': 'עריכת מיקום',
          'name': 'שם',
          'name_hint': 'בית, עבודה, הורים...',
          'choose_coordinates': 'בחרו קואורדינטות',
          'current': 'נוכחי',
          'choose_from_map': 'בחר מהמפה',
          'validation': 'נא להזין שם ולבחור קואורדינטות.',
          'save_changes': 'שמירת שינויים',
          'no_coordinates': 'לא נבחרו קואורדינטות עדיין',
          'add_new_location': 'הוספת מיקום חדש',
          'save_location': 'שמור מיקום',
          'my_locations': 'המיקומים שלי',
          'add_location': 'הוסף מיקום',
          'distance_source': 'מקור מרחק',
          'current_location': 'מיקום נוכחי',
          'unavailable': 'לא זמין',
          'saved_locations': 'מיקומים שמורים',
          'no_saved':
              'אין עדיין מיקומים שמורים.\nהקשו על הוספת מיקום כדי לשמור בית, עבודה וכו׳.',
          'active': 'פעיל',
        };
      case 'ar':
        return {
          'delete_location': 'حذف الموقع',
          'remove_saved': 'إزالة "{label}" من المواقع المحفوظة؟',
          'cancel': 'إلغاء',
          'delete': 'حذف',
          'current_prefix': 'الحالي',
          'map_prefix': 'الخريطة',
          'edit_location': 'تعديل الموقع',
          'name': 'الاسم',
          'name_hint': 'المنزل، العمل، الأهل...',
          'choose_coordinates': 'اختر الإحداثيات',
          'current': 'الحالي',
          'choose_from_map': 'اختر من الخريطة',
          'validation': 'يرجى إدخال اسم واختيار الإحداثيات.',
          'save_changes': 'حفظ التغييرات',
          'no_coordinates': 'لم يتم اختيار الإحداثيات بعد',
          'add_new_location': 'إضافة موقع جديد',
          'save_location': 'حفظ الموقع',
          'my_locations': 'مواقعي',
          'add_location': 'إضافة موقع',
          'distance_source': 'مصدر المسافة',
          'current_location': 'الموقع الحالي',
          'unavailable': 'غير متاح',
          'saved_locations': 'المواقع المحفوظة',
          'no_saved':
              'لا توجد مواقع محفوظة بعد.\nاضغط إضافة موقع لحفظ المنزل، العمل، وغيرها.',
          'active': 'نشط',
        };
      case 'am':
        return {
          'delete_location': 'ቦታ ሰርዝ',
          'remove_saved': '"{label}" ከተቀመጡ ቦታዎች ማስወገድ?',
          'cancel': 'ሰርዝ',
          'delete': 'ሰርዝ',
          'current_prefix': 'አሁን',
          'map_prefix': 'ካርታ',
          'edit_location': 'ቦታ አርትዕ',
          'name': 'ስም',
          'name_hint': 'ቤት፣ ስራ፣ ወላጆች...',
          'choose_coordinates': 'ኮኦርዲኔቶችን ይምረጡ',
          'current': 'አሁን',
          'choose_from_map': 'ከካርታ ምረጥ',
          'validation': 'እባክዎ ስም ያስገቡ እና ኮኦርዲኔት ይምረጡ።',
          'save_changes': 'ለውጦችን አስቀምጥ',
          'no_coordinates': 'ኮኦርዲኔት ገና አልተመረጠም',
          'add_new_location': 'አዲስ ቦታ ጨምር',
          'save_location': 'ቦታ አስቀምጥ',
          'my_locations': 'የእኔ ቦታዎች',
          'add_location': 'ቦታ ጨምር',
          'distance_source': 'የርቀት ምንጭ',
          'current_location': 'የአሁኑ ቦታ',
          'unavailable': 'አይገኝም',
          'saved_locations': 'የተቀመጡ ቦታዎች',
          'no_saved': 'እስካሁን የተቀመጡ ቦታዎች የሉም።\nቤት፣ ስራ ወዘተ ለማስቀመጥ ቦታ ጨምር ይጫኑ።',
          'active': 'ንቁ',
        };
      case 'ru':
        return {
          'delete_location': 'Удалить локацию',
          'remove_saved': 'Удалить "{label}" из сохраненных локаций?',
          'cancel': 'Отмена',
          'delete': 'Удалить',
          'current_prefix': 'Текущая',
          'map_prefix': 'Карта',
          'edit_location': 'Изменить локацию',
          'name': 'Название',
          'name_hint': 'Дом, работа, родители...',
          'choose_coordinates': 'Выберите координаты',
          'current': 'Текущая',
          'choose_from_map': 'Выбрать на карте',
          'validation': 'Введите название и выберите координаты.',
          'save_changes': 'Сохранить изменения',
          'no_coordinates': 'Координаты еще не выбраны',
          'add_new_location': 'Добавить новую локацию',
          'save_location': 'Сохранить локацию',
          'my_locations': 'Мои локации',
          'add_location': 'Добавить локацию',
          'distance_source': 'Источник расстояния',
          'current_location': 'Текущее местоположение',
          'unavailable': 'Недоступно',
          'saved_locations': 'Сохраненные локации',
          'no_saved':
              'Пока нет сохраненных локаций.\nНажмите "Добавить локацию", чтобы сохранить Дом, Работу и т.д.',
          'active': 'Активно',
        };
      default:
        return {
          'delete_location': 'Delete Location',
          'remove_saved': 'Remove "{label}" from saved locations?',
          'cancel': 'Cancel',
          'delete': 'Delete',
          'current_prefix': 'Current',
          'map_prefix': 'Map',
          'edit_location': 'Edit Location',
          'name': 'Name',
          'name_hint': 'Home, Work, Parents...',
          'choose_coordinates': 'Choose coordinates',
          'current': 'Current',
          'choose_from_map': 'Choose from Map',
          'validation': 'Please enter a name and choose coordinates.',
          'save_changes': 'Save Changes',
          'no_coordinates': 'No coordinates selected yet',
          'add_new_location': 'Add New Location',
          'save_location': 'Save Location',
          'my_locations': 'My Locations',
          'add_location': 'Add Location',
          'distance_source': 'Distance Source',
          'current_location': 'Current Location',
          'unavailable': 'Unavailable',
          'saved_locations': 'Saved Locations',
          'no_saved':
              'No saved locations yet.\nTap Add Location to save Home, Work, etc.',
          'active': 'Active',
        };
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Show blocking loader only for initial empty state; keep UI responsive
    // during refreshes triggered by add/edit/delete actions.
    final shouldShowBlockingLoader = _saved.isEmpty && !_isLoading;
    if (shouldShowBlockingLoader) {
      setState(() => _isLoading = true);
    }

    final results = await Future.wait<dynamic>([
      LocationContextService.getActiveLocationId(),
      LocationContextService.getSavedLocations(),
    ]);

    if (!mounted) return;
    setState(() {
      _activeId = results[0] as String;
      _saved = results[1] as List<AppLocation>;
      _isLoading = false;
    });

    // Do not block page appearance on GPS/permission delays.
    _loadCurrentDeviceLocation();
  }

  Future<void> _loadCurrentDeviceLocation() async {
    final currentDeviceLocation =
        await LocationContextService.getCurrentDeviceLocation();
    if (!mounted) return;
    setState(() {
      _currentDeviceLocation = currentDeviceLocation;
    });
  }

  Future<void> _select(String id) async {
    await LocationContextService.setActiveLocationId(id);
    if (!mounted) return;
    setState(() => _activeId = id);
    Navigator.pop(context, true);
  }

  Future<void> _delete(AppLocation location) async {
    final strings = _strings(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings['delete_location']!),
        content: Text(
          strings['remove_saved']!.replaceFirst('{label}', location.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings['cancel']!),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(strings['delete']!),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await LocationContextService.deleteLocation(location.id);
      await _load();
    }
  }

  Future<void> _openEditDialog(AppLocation location) async {
    final strings = _strings(context);
    final nameController = TextEditingController(text: location.label);
    LatLng? selectedPoint = LatLng(location.latitude, location.longitude);
    String selectedSource =
        '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
    bool isSaving = false;
    bool showValidation = false;

    Future<void> fillFromCurrent(StateSetter setDialogState) async {
      final current = await LocationContextService.getCurrentDeviceLocation();
      if (current == null) return;
      setDialogState(() {
        selectedPoint = LatLng(current.latitude, current.longitude);
        selectedSource =
            '${strings['current_prefix']}: ${current.latitude.toStringAsFixed(5)}, ${current.longitude.toStringAsFixed(5)}';
      });
    }

    Future<void> pickFromMap(StateSetter setDialogState) async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocationPicker(initialCenter: selectedPoint),
        ),
      );
      if (result is LatLng) {
        setDialogState(() {
          selectedPoint = result;
          selectedSource =
              '${strings['map_prefix']}: ${result.latitude.toStringAsFixed(5)}, ${result.longitude.toStringAsFixed(5)}';
        });
      }
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasName = nameController.text.trim().isNotEmpty;
            final hasPoint = selectedPoint != null;
            final canSave = hasName && hasPoint && !isSaving;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.edit_location_alt_outlined,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings['edit_location']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: strings['name'],
                        hintText: strings['name_hint'],
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings['choose_coordinates']!,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => fillFromCurrent(setDialogState),
                            icon: const Icon(Icons.my_location),
                            label: Text(strings['current']!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickFromMap(setDialogState),
                            icon: const Icon(Icons.map_outlined),
                            label: Text(strings['choose_from_map']!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        selectedSource,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (showValidation && !canSave) ...[
                      const SizedBox(height: 10),
                      Text(
                        strings['validation']!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings['cancel']!),
                ),
                ElevatedButton(
                  onPressed: canSave
                      ? () async {
                          setDialogState(() {
                            isSaving = true;
                            showValidation = false;
                          });
                          await LocationContextService.saveLocation(
                            id: location.id,
                            label: nameController.text.trim(),
                            latitude: selectedPoint!.latitude,
                            longitude: selectedPoint!.longitude,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        }
                      : () {
                          setDialogState(() {
                            showValidation = true;
                          });
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings['save_changes']!),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      await _load();
    }
  }

  Future<void> _openAddDialog() async {
    final strings = _strings(context);
    final nameController = TextEditingController();
    LatLng? selectedPoint;
    String selectedSource = strings['no_coordinates']!;
    bool isSaving = false;
    bool showValidation = false;

    Future<void> fillFromCurrent(StateSetter setDialogState) async {
      final current = await LocationContextService.getCurrentDeviceLocation();
      if (current == null) return;
      setDialogState(() {
        selectedPoint = LatLng(current.latitude, current.longitude);
        selectedSource =
            '${strings['current_prefix']}: ${current.latitude.toStringAsFixed(5)}, ${current.longitude.toStringAsFixed(5)}';
      });
    }

    Future<void> pickFromMap(StateSetter setDialogState) async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocationPicker(initialCenter: selectedPoint),
        ),
      );
      if (result is LatLng) {
        setDialogState(() {
          selectedPoint = result;
          selectedSource =
              '${strings['map_prefix']}: ${result.latitude.toStringAsFixed(5)}, ${result.longitude.toStringAsFixed(5)}';
        });
      }
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final hasName = nameController.text.trim().isNotEmpty;
            final hasPoint = selectedPoint != null;
            final canSave = hasName && hasPoint && !isSaving;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    Icons.add_location_alt_outlined,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings['add_new_location']!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: strings['name'],
                        hintText: strings['name_hint'],
                        prefixIcon: const Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings['choose_coordinates']!,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => fillFromCurrent(setDialogState),
                            icon: const Icon(Icons.my_location),
                            label: Text(strings['current']!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickFromMap(setDialogState),
                            icon: const Icon(Icons.map_outlined),
                            label: Text(strings['choose_from_map']!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        selectedSource,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (showValidation && !canSave) ...[
                      const SizedBox(height: 10),
                      Text(
                        strings['validation']!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(strings['cancel']!),
                ),
                ElevatedButton(
                  onPressed: canSave
                      ? () async {
                          setDialogState(() {
                            isSaving = true;
                            showValidation = false;
                          });
                          final label = nameController.text.trim();

                          await LocationContextService.saveLocation(
                            label: label,
                            latitude: selectedPoint!.latitude,
                            longitude: selectedPoint!.longitude,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        }
                      : () {
                          setDialogState(() {
                            showValidation = true;
                          });
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings['save_location']!),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(strings['my_locations']!),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: Text(strings['add_location']!),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              children: [
                Text(
                  strings['distance_source']!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildLocationCard(
                  icon: Icons.my_location,
                  title: strings['current_location']!,
                  subtitle: _currentDeviceLocation == null
                      ? strings['unavailable']!
                      : '${_currentDeviceLocation!.latitude.toStringAsFixed(5)}, ${_currentDeviceLocation!.longitude.toStringAsFixed(5)}',
                  isActive: _activeId == AppLocation.currentId,
                  onTap: () => _select(AppLocation.currentId),
                ),
                const SizedBox(height: 18),
                Text(
                  strings['saved_locations']!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_saved.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          color: Color(0xFF94A3B8),
                          size: 34,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings['no_saved']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                else
                  ..._saved.map((location) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildLocationCard(
                        icon: Icons.place_outlined,
                        title: location.label,
                        subtitle:
                            '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                        isActive: _activeId == location.id,
                        onTap: () => _select(location.id),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              color: const Color(0xFF1976D2),
                              onPressed: () => _openEditDialog(location),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red.shade400,
                              onPressed: () => _delete(location),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _buildLocationCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? const Color(0xFF1976D2) : const Color(0xFFE2E8F0),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEEF2FF),
              child: Icon(icon, size: 18, color: const Color(0xFF1976D2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _strings(context)['active']!,
                            style: TextStyle(
                              color: Color(0xFF0369A1),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
            Radio<bool>(
              value: true,
              groupValue: isActive,
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}
