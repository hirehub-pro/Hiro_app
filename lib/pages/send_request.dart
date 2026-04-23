import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/map/location_picker.dart';
import 'package:untitled1/pages/my_requests_page.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/utils/booking_mode.dart';

class SendRequestPage extends StatefulWidget {
  final String workerId;
  final String workerName;
  final DateTime selectedDay;
  final bool isExtraHours;
  final bool isQuoteRequest;
  final String? initialFrom;
  final String? initialTo;
  final String bookingMode;
  final String? professionName;

  const SendRequestPage({
    super.key,
    required this.workerId,
    required this.workerName,
    required this.selectedDay,
    this.isExtraHours = false,
    this.isQuoteRequest = false,
    this.initialFrom,
    this.initialTo,
    this.bookingMode = bookingModeProviderTravels,
    this.professionName,
  });

  @override
  State<SendRequestPage> createState() => _SendRequestPageState();
}

class _SendRequestPageState extends State<SendRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final List<File> _images = [];
  final ImagePicker _picker = ImagePicker();

  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  Position? _currentPosition;
  LatLng? _selectedLocation;
  String? _locationSelectionMode;
  bool _isLoading = false;
  bool _isLocating = false;

  String get _normalizedBookingMode => normalizeBookingMode(widget.bookingMode);
  bool get _customerTravels =>
      _normalizedBookingMode == bookingModeCustomerTravels;
  bool get _onlineOnly => _normalizedBookingMode == bookingModeOnline;

  @override
  void initState() {
    super.initState();
    if (widget.isExtraHours) {
      if (widget.initialFrom != null) {
        final parts = widget.initialFrom!.split(':');
        _fromTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } else {
        _fromTime = const TimeOfDay(hour: 8, minute: 0);
      }

      if (widget.initialTo != null) {
        final parts = widget.initialTo!.split(':');
        _toTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } else {
        _toTime = const TimeOfDay(hour: 16, minute: 0);
      }
    } else {
      _fromTime = const TimeOfDay(hour: 8, minute: 0);
      _toTime = const TimeOfDay(hour: 16, minute: 0);
    }
    if (!widget.isQuoteRequest && !_customerTravels && !_onlineOnly) {
      _fetchLocation();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = pos;
        _selectedLocation = LatLng(pos.latitude, pos.longitude);
        _locationSelectionMode = 'current';
        _isLocating = false;
      });
    } catch (e) {
      debugPrint('Error fetching location: $e');
      setState(() => _isLocating = false);
    }
  }

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((file) => File(file.path)));
      });
    }
  }

  Future<void> _pickLocationFromMap() async {
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPicker(initialCenter: _selectedLocation),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedLocation = picked;
      _locationSelectionMode = 'map';
    });
  }

  Map<String, String> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'שליחת בקשת עבודה',
          'subtitle': _onlineOnly
              ? 'מלא כמה פרטים כדי לקבוע פגישה אונליין ברורה ומהירה.'
              : _customerTravels
              ? 'מלא כמה פרטים כדי לקבוע תור ברור ומהיר אצל בעל המקצוע.'
              : 'מלא כמה פרטים כדי שהעובד יוכל להבין את העבודה ולהגיב מהר יותר.',
          'worker': 'בעל מקצוע:',
          'profession': 'מקצוע',
          'date': 'תאריך:',
          'request_type': 'סוג בקשה',
          'my_requests': 'הבקשות שלי',
          'extra_hours': _onlineOnly
              ? 'שעות פגישה נוספות'
              : _customerTravels
              ? 'שעות תור נוספות'
              : 'שעות נוספות',
          'regular_request': _onlineOnly
              ? 'קביעת פגישה אונליין'
              : _customerTravels
              ? 'קביעת תור'
              : 'בקשת עבודה רגילה',
          'quote_request': 'בקשה לתן הצעת מחיר',
          'desc_label': _onlineOnly
              ? 'פרטי הפגישה'
              : _customerTravels
              ? 'פרטי התור'
              : 'תיאור העבודה',
          'desc_hint': _onlineOnly
              ? 'תאר מה אתה צריך ומה תרצה לכסות בפגישה האונליין...'
              : _customerTravels
              ? 'תאר מה אתה צריך ולמה אתה מגיע...'
              : 'תאר את העבודה שאתה צריך...',
          'desc_helper': _onlineOnly
              ? 'כדאי לציין מה צריך לבצע, מטרת הפגישה, וכל פרט שיעזור להתכונן אונליין.'
              : _customerTravels
              ? 'כדאי לציין מה צריך לבצע, מה חשוב לביקור, וכל פרט שיעזור להכין את התור.'
              : 'כדאי לציין מה צריך לבצע, מיקום, גודל עבודה ודגשים חשובים.',
          'desc_quick_help': 'עזרה מהירה לכתיבת תיאור',
          'desc_quick_help_subtitle':
              'בחר התחלה מהירה כדי למלא תיאור ברור ומדויק יותר.',
          'desc_template_short': 'ניקיון / תיקון קטן',
          'desc_template_medium': 'עבודה בינונית',
          'desc_template_quote': 'בקשת הצעת מחיר',
          'desc_template_short_text':
              'אני צריך עזרה ב:\n- מה בדיוק צריך לבצע:\n- כתובת / אזור:\n- מתי נוח להגיע:\n- פרטים חשובים נוספים:',
          'desc_template_medium_text':
              'פירוט העבודה:\n- סוג העבודה:\n- גודל / כמות:\n- האם יש חומרים קיימים במקום:\n- מיקום מדויק:\n- דחיפות או טווח זמנים:',
          'desc_template_quote_text':
              'אשמח לקבל הצעת מחיר עבור:\n- מה צריך לבצע:\n- גודל העבודה / כמות:\n- כתובת או אזור:\n- האם יש תמונות / פרטים חשובים:\n- מתי תרצו לחזור אליי:',
          'images': 'תמונות (אופציונלי)',
          'images_helper': 'הוסף תמונות כדי להסביר טוב יותר את העבודה.',
          'add_images': 'הוסף תמונות',
          'photos_count': 'תמונות',
          'location': _onlineOnly
              ? 'סוג הפגישה'
              : _customerTravels
              ? 'מיקום הפגישה'
              : 'מיקום GPS',
          'loc_found': 'המיקום נמצא',
          'loc_not_found': 'מחפש מיקום...',
          'loc_current_selected': 'נבחר המיקום הנוכחי שלך',
          'loc_map_selected': 'נבחר מיקום מהמפה',
          'location_helper': _onlineOnly
              ? 'הפגישה תתקיים אונליין, לכן אין צורך לצרף מיקום.'
              : _customerTravels
              ? 'התור ייקבע אצל בעל המקצוע. אין צורך לצרף את המיקום שלך.'
              : 'המיקום יתווסף לבקשה כדי לעזור לעובד להבין היכן העבודה.',
          'appointment_place_helper':
              'הבקשה תישלח כתור אצל בעל המקצוע, לפי המיקום שמופיע בפרופיל שלו.',
          'online_place_helper':
              'הבקשה תישלח כפגישה אונליין. אפשר לשתף קישור או פרטי התחברות בהמשך בצ׳אט.',
          'use_current_location': 'השתמש במיקום נוכחי',
          'choose_from_map': 'בחר מהמפה',
          'from': 'מ-',
          'to': 'עד',
          'time_window': 'שעות עבודה',
          'time_window_helper': 'בחר את טווח השעות המבוקש לעבודה.',
          'send': 'שלח בקשה',
          'send_cta': 'שלח עכשיו',
          'req': 'שדה חובה',
          'sending': 'שולח...',
          'success': 'הבקשה נשלחה בהצלחה',
          'error': 'שליחת הבקשה נכשלה',
          'invalid_time_range': 'שעת הסיום חייבת להיות אחרי שעת ההתחלה.',
          'refresh_location': 'רענן מיקום',
          'ready_to_send': _onlineOnly
              ? 'הבקשה תישלח כפגישת אונליין עם תיאור, שעות ותמונות אם יש.'
              : _customerTravels
              ? 'הבקשה תישלח כתיאום תור עם תיאור, שעות ותמונות אם יש.'
              : 'הבקשה תישלח בצירוף תיאור, שעות, תמונות ומיקום אם זמינים.',
          'chat_request_msg': _onlineOnly
              ? 'שלחתי לך בקשת פגישת אונליין לתאריך: '
              : _customerTravels
              ? 'שלחתי לך בקשת תור לתאריך: '
              : 'שלחתי לך בקשת עבודה לתאריך: ',
          'error_not_found': 'שגיאה: משתמש לא נמצא',
        };
      case 'ar':
        return {
          'title': 'إرسال طلب عمل',
          'subtitle': _onlineOnly
              ? 'أضف بعض التفاصيل لحجز جلسة أونلاين واضحة وسريعة.'
              : _customerTravels
              ? 'أضف بعض التفاصيل لحجز موعد واضح وسريع عند المحترف.'
              : 'أضف بعض التفاصيل حتى يفهم العامل الطلب ويرد بشكل أسرع.',
          'worker': 'المحترف:',
          'profession': 'المهنة',
          'date': 'التاريخ:',
          'request_type': 'نوع الطلب',
          'my_requests': 'طلباتي',
          'extra_hours': _onlineOnly
              ? 'ساعات جلسة إضافية'
              : _customerTravels
              ? 'ساعات موعد إضافية'
              : 'ساعات إضافية',
          'regular_request': _onlineOnly
              ? 'حجز جلسة أونلاين'
              : _customerTravels
              ? 'حجز موعد'
              : 'طلب عمل عادي',
          'quote_request': 'طلب تقديم عرض سعر',
          'desc_label': _onlineOnly
              ? 'تفاصيل الجلسة'
              : _customerTravels
              ? 'تفاصيل الموعد'
              : 'وصف العمل',
          'desc_hint': _onlineOnly
              ? 'اشرح ما تحتاجه وما الذي تريد تغطيته في الجلسة الأونلاين...'
              : _customerTravels
              ? 'اشرح ما تحتاجه ولماذا ستزور المحترف...'
              : 'صف العمل الذي تحتاجه...',
          'desc_helper': _onlineOnly
              ? 'اذكر المطلوب وهدف الجلسة وأي تفاصيل تساعد على التحضير للجلسة أونلاين.'
              : _customerTravels
              ? 'اذكر المطلوب وأي تفاصيل تساعد المحترف على تجهيز الموعد.'
              : 'اذكر المطلوب والموقع وحجم العمل وأي تفاصيل مهمة.',
          'desc_quick_help': 'مساعدة سريعة لكتابة الوصف',
          'desc_quick_help_subtitle':
              'اختر بداية سريعة لكتابة وصف أوضح وأكثر دقة.',
          'desc_template_short': 'تنظيف / إصلاح بسيط',
          'desc_template_medium': 'عمل متوسط',
          'desc_template_quote': 'طلب عرض سعر',
          'desc_template_short_text':
              'أحتاج مساعدة في:\n- ما المطلوب بالضبط:\n- العنوان / المنطقة:\n- الوقت المناسب للوصول:\n- تفاصيل إضافية مهمة:',
          'desc_template_medium_text':
              'تفاصيل العمل:\n- نوع العمل:\n- الحجم / الكمية:\n- هل المواد موجودة في المكان:\n- الموقع الدقيق:\n- درجة الاستعجال أو الوقت المطلوب:',
          'desc_template_quote_text':
              'أرغب في الحصول على عرض سعر من أجل:\n- ما الذي يجب تنفيذه:\n- حجم العمل / الكمية:\n- العنوان أو المنطقة:\n- هل توجد صور أو تفاصيل مهمة:\n- متى يمكنكم التواصل معي:',
          'images': 'الصور (اختياري)',
          'images_helper': 'أضف صورًا لتوضيح العمل بشكل أفضل.',
          'add_images': 'إضافة صور',
          'photos_count': 'صور',
          'location': _onlineOnly
              ? 'نوع الجلسة'
              : _customerTravels
              ? 'مكان الموعد'
              : 'موقع GPS',
          'loc_found': 'تم العثور على الموقع',
          'loc_not_found': 'جاري البحث عن الموقع...',
          'loc_current_selected': 'تم اختيار موقعك الحالي',
          'loc_map_selected': 'تم اختيار موقع من الخريطة',
          'location_helper': _onlineOnly
              ? 'ستتم الجلسة عبر الإنترنت، لذلك لا حاجة لإرفاق موقعك.'
              : _customerTravels
              ? 'سيتم حجز الموعد لدى المحترف، لذلك لا حاجة لإرفاق موقعك.'
              : 'سيتم إرفاق الموقع بالطلب لمساعدة العامل على فهم مكان العمل.',
          'appointment_place_helper':
              'سيتم إرسال الطلب كموعد لدى المحترف حسب الموقع الظاهر في ملفه.',
          'online_place_helper':
              'سيتم إرسال الطلب كجلسة أونلاين. يمكن مشاركة رابط الاجتماع أو تفاصيل الدخول لاحقًا في الدردشة.',
          'use_current_location': 'استخدم موقعي الحالي',
          'choose_from_map': 'اختر من الخريطة',
          'from': 'من',
          'to': 'إلى',
          'time_window': 'ساعات العمل',
          'time_window_helper': 'اختر الفترة الزمنية المطلوبة للعمل.',
          'send': 'إرسال الطلب',
          'send_cta': 'إرسال الآن',
          'req': 'مطلوب',
          'sending': 'جاري الإرسال...',
          'success': 'تم إرسال الطلب بنجاح',
          'error': 'فشل إرسال الطلب',
          'invalid_time_range': 'يجب أن يكون وقت الانتهاء بعد وقت البدء.',
          'refresh_location': 'تحديث الموقع',
          'ready_to_send': _onlineOnly
              ? 'سيتم إرسال الطلب كجلسة أونلاين مع الوصف والساعات والصور إن وُجدت.'
              : _customerTravels
              ? 'سيتم إرسال الطلب كحجز موعد مع الوصف والساعات والصور إن وُجدت.'
              : 'سيتم إرسال الطلب مع الوصف والساعات والصور والموقع إذا كان متاحًا.',
          'chat_request_msg': _onlineOnly
              ? 'لقد أرسلت لك طلب جلسة أونلاين بتاريخ: '
              : _customerTravels
              ? 'لقد أرسلت لك طلب موعد بتاريخ: '
              : 'لقد أرسلت لك طلب عمل بتاريخ: ',
          'error_not_found': 'خطأ: المستخدم غير موجود',
        };
      default:
        return {
          'title': 'Send Work Request',
          'subtitle': _onlineOnly
              ? 'Add a few details to book a clear online session.'
              : _customerTravels
              ? 'Add a few details to book a clear appointment at the professional location.'
              : 'Add a few details so the worker can understand the job and reply faster.',
          'worker': 'Professional:',
          'profession': 'Profession',
          'date': 'Date:',
          'request_type': 'Request Type',
          'my_requests': 'My Requests',
          'extra_hours': _onlineOnly
              ? 'Extra Session Hours'
              : _customerTravels
              ? 'Extra Appointment Hours'
              : 'Extra Hours',
          'regular_request': _onlineOnly
              ? 'Book Online Session'
              : _customerTravels
              ? 'Book Appointment'
              : 'Standard Work Request',
          'quote_request': 'Request a Quote',
          'desc_label': _onlineOnly
              ? 'Session Details'
              : _customerTravels
              ? 'Appointment Details'
              : 'Job Description',
          'desc_hint': _onlineOnly
              ? 'Describe what you need and what you want to cover in the online session...'
              : _customerTravels
              ? 'Describe what you need and what the visit is for...'
              : 'Describe the job you need...',
          'desc_helper': _onlineOnly
              ? 'Include what you need, the goal of the session, and anything helpful for preparing online.'
              : _customerTravels
              ? 'Include what you need, what the visit is for, and anything helpful for preparing the appointment.'
              : 'Include what needs to be done, the location, scope, and anything important.',
          'desc_quick_help': 'Quick description help',
          'desc_quick_help_subtitle':
              'Choose a quick start to write a clearer, more useful work description.',
          'desc_template_short': 'Small fix / cleaning',
          'desc_template_medium': 'Medium job',
          'desc_template_quote': 'Quote request',
          'desc_template_short_text':
              'I need help with:\n- What exactly needs to be done:\n- Address / area:\n- Best time to arrive:\n- Extra details to know:',
          'desc_template_medium_text':
              'Job details:\n- Type of work:\n- Size / quantity:\n- Are materials already on site:\n- Exact location:\n- Urgency or preferred time window:',
          'desc_template_quote_text':
              'I would like a quote for:\n- What needs to be done:\n- Job size / quantity:\n- Address or area:\n- Photos or important details:\n- Best way / time to get back to me:',
          'images': 'Images (Optional)',
          'images_helper':
              'Add photos to make the request easier to understand.',
          'add_images': 'Add Images',
          'photos_count': 'Photos',
          'location': _onlineOnly
              ? 'Session Type'
              : _customerTravels
              ? 'Appointment Location'
              : 'GPS Location',
          'loc_found': 'Location found',
          'loc_not_found': 'Locating...',
          'loc_current_selected': 'Using your current location',
          'loc_map_selected': 'Using a map-selected location',
          'location_helper': _onlineOnly
              ? 'This session is online, so your location is not needed.'
              : _customerTravels
              ? 'This appointment is at the professional location, so your location is not needed.'
              : 'Your location will be attached to help the worker understand where the job is.',
          'appointment_place_helper':
              'The request will be sent as an appointment at the professional location shown on their profile.',
          'online_place_helper':
              'The request will be sent as an online session. You can share a meeting link or access details later in chat.',
          'use_current_location': 'Use current location',
          'choose_from_map': 'Choose from map',
          'from': 'From',
          'to': 'To',
          'time_window': 'Time Window',
          'time_window_helper': 'Choose the requested working hours.',
          'send': 'Send Request',
          'send_cta': 'Send Now',
          'req': 'Required',
          'sending': 'Sending...',
          'success': 'Request sent successfully',
          'error': 'Failed to send request',
          'invalid_time_range': 'End time must be after start time.',
          'refresh_location': 'Refresh location',
          'ready_to_send': _onlineOnly
              ? 'The request will be sent as an online session with details, hours, and images when available.'
              : _customerTravels
              ? 'The request will be sent as an appointment with details, hours, and images when available.'
              : 'The request will include description, hours, images, and location when available.',
          'chat_request_msg': _onlineOnly
              ? 'I sent you an online session request for: '
              : _customerTravels
              ? 'I sent you an appointment request for: '
              : 'I sent you a work request for: ',
          'error_not_found': 'Error: User not found',
        };
    }
  }

  Future<void> _sendFCMNotification(
    String targetToken,
    String title,
    String body,
  ) async {
    debugPrint('FCM trigger would happen here for token: $targetToken');
  }

  String _getChatRoomId(String user1, String user2) {
    final ids = [user1, user2]..sort();
    return ids.join('_');
  }

  bool _hasValidTimeRange() {
    if (_fromTime == null || _toTime == null) return true;
    final fromMinutes = (_fromTime!.hour * 60) + _fromTime!.minute;
    final toMinutes = (_toTime!.hour * 60) + _toTime!.minute;
    return toMinutes > fromMinutes;
  }

  String _formatSelectedDate() {
    final day = widget.selectedDay.day.toString().padLeft(2, '0');
    final month = widget.selectedDay.month.toString().padLeft(2, '0');
    final year = widget.selectedDay.year.toString();
    return '$day/$month/$year';
  }

  void _applyDescriptionTemplate(String template) {
    setState(() {
      _descriptionController.text = template;
      _descriptionController.selection = TextSelection.fromPosition(
        TextPosition(offset: _descriptionController.text.length),
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final strings = _getLocalizedStrings(context);
    if (!widget.isQuoteRequest && !_hasValidTimeRange()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['invalid_time_range']!)));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final dStr =
        '${widget.selectedDay.year}-${widget.selectedDay.month}-${widget.selectedDay.day}';

    try {
      final imageUrls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final ref = FirebaseStorage.instance.ref().child(
          'request_images/${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        );
        await ref.putFile(_images[i]);
        imageUrls.add(await ref.getDownloadURL());
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['error_not_found']!)));
        }
        return;
      }
      final userData = userDoc.data();
      final userName = userData?['name'] ?? 'Client';
      final userTown = userData?['town'];

      final workerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.workerId)
          .get();
      if (!workerDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(strings['error_not_found']!)));
        }
        return;
      }
      final workerData = workerDoc.data();
      final workerFcmToken = workerData?['fcmToken'] as String?;

      final fStr = !widget.isQuoteRequest && _fromTime != null
          ? '${_fromTime!.hour.toString().padLeft(2, '0')}:${_fromTime!.minute.toString().padLeft(2, '0')}'
          : null;
      final tStr = !widget.isQuoteRequest && _toTime != null
          ? '${_toTime!.hour.toString().padLeft(2, '0')}:${_toTime!.minute.toString().padLeft(2, '0')}'
          : null;

      final professionLabel = widget.professionName?.trim();
      final workerLocationName =
          (workerData?['town'] ?? workerData?['address'] ?? '')
              .toString()
              .trim();
      final locationName = widget.isQuoteRequest
          ? null
          : _onlineOnly
          ? 'online'
          : _customerTravels
          ? (workerLocationName.isEmpty
                ? widget.workerName
                : workerLocationName)
          : userTown?.toString().trim();
      final serviceLocationType = _onlineOnly
          ? bookingModeOnline
          : _customerTravels
          ? bookingModeCustomerTravels
          : bookingModeProviderTravels;

      final notifTitle = widget.isQuoteRequest
          ? 'Quote Request'
          : _onlineOnly
          ? 'Online Session Request'
          : _customerTravels
          ? 'Appointment Request'
          : widget.isExtraHours
          ? 'Extra Hours Request'
          : 'Work Request';
      final notifBody = widget.isQuoteRequest
          ? '$userName ($userTown) requested a quote.'
          : _onlineOnly
          ? (widget.isExtraHours
                ? '$userName requested an online session on $dStr from $fStr to $tStr.'
                : '$userName requested an online session on $dStr.')
          : _customerTravels
          ? (widget.isExtraHours
                ? '$userName requested an appointment on $dStr from $fStr to $tStr.'
                : '$userName requested an appointment on $dStr.')
          : !widget.isExtraHours
          ? '$userName ($userTown) requested you to work on $dStr.'
          : '$userName ($userTown) requested you to work on $dStr from $fStr to $tStr.';

      final firestore = FirebaseFirestore.instance;
      final requestId = firestore
          .collection('users')
          .doc(user.uid)
          .collection('requests')
          .doc()
          .id;
      final workerNotificationRef = firestore
          .collection('users')
          .doc(widget.workerId)
          .collection('notifications')
          .doc();

      final requestData = {
        'requestId': requestId,
        'workerId': widget.workerId,
        'workerName': widget.workerName,
        'workerNotificationId': workerNotificationRef.id,
        'type': widget.isQuoteRequest ? 'quote_request' : 'work_request',
        'fromId': user.uid,
        'fromName': userName,
        'fromLocation': userTown,
        'profession': professionLabel,
        'jobDescription': _descriptionController.text.trim(),
        'images': imageUrls,
        'latitude': widget.isQuoteRequest || _customerTravels || _onlineOnly
            ? null
            : _selectedLocation?.latitude,
        'longitude': widget.isQuoteRequest || _customerTravels || _onlineOnly
            ? null
            : _selectedLocation?.longitude,
        'date': widget.isQuoteRequest ? null : dStr,
        'requestedFrom': fStr,
        'requestedTo': tStr,
        'locationName': locationName,
        'serviceLocationType': serviceLocationType,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'title': notifTitle,
        'body': notifBody,
      };

      final batch = firestore.batch();
      batch.set(workerNotificationRef, requestData);
      batch.set(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('requests')
            .doc(requestId),
        requestData,
      );
      await batch.commit();

      final chatRoomId = _getChatRoomId(user.uid, widget.workerId);
      final chatMsg =
          '${strings['chat_request_msg']}$dStr\n${_descriptionController.text.trim()}';

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'receiverId': widget.workerId,
            'message': chatMsg,
            'type': 'request_link',
            'requestId': requestId,
            'requestOwnerId': user.uid,
            'workerNotificationId': workerNotificationRef.id,
            'timestamp': FieldValue.serverTimestamp(),
            'isSystem': true,
          });

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .set({
            'lastMessage': chatMsg,
            'lastTimestamp': FieldValue.serverTimestamp(),
            'users': [user.uid, widget.workerId],
            'userNames': {
              user.uid: userName,
              widget.workerId: widget.workerName,
            },
          }, SetOptions(merge: true));

      if (workerFcmToken != null) {
        await _sendFCMNotification(workerFcmToken, notifTitle, notifBody);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['success']!)));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings['error']!)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final theme = Theme.of(context);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4FAFA),
        appBar: AppBar(
          title: Text(strings['title']!),
          actions: [
            IconButton(
              tooltip: strings['my_requests'],
              icon: const Icon(Icons.list_alt_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyRequestsPage()),
                );
              },
            ),
          ],
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: const Color(0xFF103A44),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _isLoading
              ? Center(
                  key: const ValueKey('loading'),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        strings['sending']!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF103A44),
                        ),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  key: const ValueKey('form'),
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroCard(strings, theme),
                          const SizedBox(height: 16),
                          _buildSectionCard(child: _buildInfoSection(strings)),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            child: _buildDescriptionSection(strings),
                          ),
                          if (!widget.isQuoteRequest) ...[
                            const SizedBox(height: 16),
                            _buildSectionCard(
                              child: _buildTimeSection(strings),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _buildSectionCard(child: _buildImageSection(strings)),
                          if (!widget.isQuoteRequest) ...[
                            const SizedBox(height: 16),
                            _buildSectionCard(
                              child: _buildLocationCard(strings),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              widget.isQuoteRequest
                                  ? strings['desc_helper']!
                                  : strings['ready_to_send']!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF5F7D83),
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton.icon(
                              onPressed: _submit,
                              icon: const Icon(Icons.send_rounded),
                              label: Text(
                                strings['send_cta']!,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A7E8C),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(Map<String, String> strings, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A7E8C), Color(0xFF17A398)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220A7E8C),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings['title']!,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings['subtitle']!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroChip(Icons.person_outline_rounded, widget.workerName),
              if (!widget.isQuoteRequest)
                _buildHeroChip(
                  Icons.calendar_today_rounded,
                  _formatSelectedDate(),
                ),
              _buildHeroChip(
                Icons.schedule_send_rounded,
                widget.isQuoteRequest
                    ? strings['quote_request']!
                    : widget.isExtraHours
                    ? strings['extra_hours']!
                    : strings['regular_request']!,
              ),
              if (widget.professionName != null &&
                  widget.professionName!.trim().isNotEmpty)
                _buildHeroChip(
                  Icons.work_outline_rounded,
                  widget.professionName!.trim(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE1ECEE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F103A44),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F6F4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF0A7E8C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF103A44),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6B8790),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.info_outline_rounded,
          title: strings['request_type']!,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildInfoTile(
              icon: Icons.person_rounded,
              label: strings['worker']!,
              value: widget.workerName,
            ),
            if (!widget.isQuoteRequest)
              _buildInfoTile(
                icon: Icons.event_rounded,
                label: strings['date']!,
                value: _formatSelectedDate(),
              ),
            _buildInfoTile(
              icon: Icons.bolt_rounded,
              label: strings['request_type']!,
              value: widget.isQuoteRequest
                  ? strings['quote_request']!
                  : widget.isExtraHours
                  ? strings['extra_hours']!
                  : strings['regular_request']!,
            ),
            if (widget.professionName != null &&
                widget.professionName!.trim().isNotEmpty)
              _buildInfoTile(
                icon: Icons.work_outline_rounded,
                label: strings['profession']!,
                value: widget.professionName!.trim(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1ECEE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE6F6F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF0A7E8C)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B8790),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF103A44),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.edit_note_rounded,
          title: strings['desc_label']!,
          subtitle: strings['desc_helper'],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descriptionController,
          minLines: 5,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: strings['desc_hint'],
            filled: true,
            fillColor: const Color(0xFFF7FBFB),
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFE1ECEE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: Color(0xFF0A7E8C),
                width: 1.3,
              ),
            ),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? strings['req'] : null,
        ),
      ],
    );
  }

  Widget _buildTimeSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.schedule_rounded,
          title: strings['time_window']!,
          subtitle: strings['time_window_helper'],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildTimePickerTile(
                label: strings['from']!,
                value: _fromTime!.format(context),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _fromTime!,
                  );
                  if (picked != null) {
                    setState(() => _fromTime = picked);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimePickerTile(
                label: strings['to']!,
                value: _toTime!.format(context),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _toTime!,
                  );
                  if (picked != null) {
                    setState(() => _toTime = picked);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimePickerTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF7FBFB),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE1ECEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B8790),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: Color(0xFF0A7E8C),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF103A44),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.photo_library_outlined,
          title: strings['images']!,
          subtitle: strings['images_helper'],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '${strings['photos_count']!}: ${_images.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B8790),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(strings['add_images']!),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _images.length) {
                return Material(
                  color: const Color(0xFFF7FBFB),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: _pickImages,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      width: 112,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE1ECEE)),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Color(0xFF0A7E8C),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(
                      _images[index],
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withOpacity(0.5),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _images.removeAt(index)),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
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
    );
  }

  Widget _buildLocationCard(Map<String, String> strings) {
    if (_onlineOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.videocam_outlined,
            title: strings['location']!,
            subtitle: strings['online_place_helper'],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.video_call_outlined,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings['online_place_helper']!,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_customerTravels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.storefront_outlined,
            title: strings['location']!,
            subtitle: strings['appointment_place_helper'],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.store_mall_directory_outlined,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings['appointment_place_helper']!,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final hasLocation = _selectedLocation != null;
    final isMapLocation = _locationSelectionMode == 'map';
    final statusColor = hasLocation
        ? const Color(0xFF246B45)
        : const Color(0xFF8D5D13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.location_on_outlined,
          title: strings['location']!,
          subtitle: strings['location_helper'],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasLocation
                ? const Color(0xFFEAF8EF)
                : const Color(0xFFFFF7E8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasLocation
                  ? const Color(0xFFB7E4C7)
                  : const Color(0xFFF2D28B),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      hasLocation
                          ? isMapLocation
                                ? Icons.map_rounded
                                : Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      color: hasLocation
                          ? const Color(0xFF2D8F5B)
                          : const Color(0xFFB7791F),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasLocation
                              ? isMapLocation
                                    ? strings['loc_map_selected']!
                                    : strings['loc_current_selected']!
                              : strings['loc_not_found']!,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasLocation
                              ? '${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}'
                              : strings['location_helper']!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF5F7D83),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLocating)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isLocating ? null : _fetchLocation,
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: Text(strings['use_current_location']!),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0A7E8C),
                      side: const BorderSide(color: Color(0xFFB9D8DC)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLocating ? null : _pickLocationFromMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(strings['choose_from_map']!),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1976D2),
                      side: const BorderSide(color: Color(0xFFBFD7F8)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
