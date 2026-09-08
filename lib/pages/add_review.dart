import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class AddReviewPage extends StatefulWidget {
  final String targetUserId;
  final List<String> professions;
  final Map<String, dynamic>? existingReview;

  const AddReviewPage({
    super.key,
    required this.targetUserId,
    required this.professions,
    this.existingReview,
  });

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final _commentController = TextEditingController();
  String? _selectedProfession;
  double _priceRating = 10.0;
  double _serviceRating = 10.0;
  double _timingRating = 10.0;
  double _workQualityRating = 10.0;

  final List<File> _newImages = [];
  List<String> _existingImageUrls = [];
  bool _isUploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.existingReview != null) {
      _commentController.text = widget.existingReview!['comment'] ?? '';
      _priceRating = (widget.existingReview!['priceRating'] ?? 10.0).toDouble();
      _serviceRating = (widget.existingReview!['serviceRating'] ?? 10.0)
          .toDouble();
      _timingRating =
          (widget.existingReview!['timingRating'] ??
                  widget.existingReview!['rating'] ??
                  10.0)
              .toDouble();
      _workQualityRating = (widget.existingReview!['workQualityRating'] ?? 10.0)
          .toDouble();
      _selectedProfession = widget.existingReview!['profession'];
      _existingImageUrls = List<String>.from(
        widget.existingReview!['imageUrls'] ?? [],
      );
    } else if (widget.professions.isNotEmpty) {
      _selectedProfession = widget.professions.first;
    }
  }

  Future<void> _pickImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 60);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _newImages.addAll(pickedFiles.map((file) => File(file.path)));
      });
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  Future<void> _submitReview() async {
    final strings = _getLocalizedStrings();
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings['comment_required']!)));
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      List<String> finalImageUrls = List.from(_existingImageUrls);

      for (var i = 0; i < _newImages.length; i++) {
        final fileName =
            'review_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reviews')
            .child(widget.targetUserId)
            .child(fileName);

        await storageRef.putFile(_newImages[i]);
        final imageUrl = await storageRef.getDownloadURL();
        finalImageUrls.add(imageUrl);
      }

      final overallRating =
          (_priceRating + _serviceRating + _timingRating + _workQualityRating) /
          4;

      final reviewData = {
        'userId': user.uid,
        'userName': user.displayName ?? "Anonymous",
        if (user.photoURL != null && user.photoURL!.isNotEmpty)
          'userProfileImage': user.photoURL,
        'profession': _selectedProfession,
        'rating': overallRating,
        'priceRating': _priceRating,
        'serviceRating': _serviceRating,
        'timingRating': _timingRating,
        'workQualityRating': _workQualityRating,
        'comment': _commentController.text.trim(),
        'imageUrls': finalImageUrls,
        'timestamp': FieldValue.serverTimestamp(),
      };

      final reviewCollection = FirebaseFirestore.instance
          .collection('publicWorkerProfiles')
          .doc(widget.targetUserId)
          .collection('reviews');
      final reviewId = widget.existingReview != null
          ? widget.existingReview!['id'].toString()
          : user.uid;
      final reviewRef = reviewCollection.doc(reviewId);

      await reviewRef.set(reviewData);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Review upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings['submit_failed']!}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Map<String, String> _getLocalizedStrings() {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    if (locale == 'he') {
      return {
        'title': widget.existingReview != null ? 'ערוך ביקורת' : 'כתוב ביקורת',
        'profession_label': 'בחר מקצוע:',
        'rating_details': 'פירוט איכות השירות',
        'price_rating': 'מחיר',
        'service_rating': 'שירות',
        'timing_rating': 'עמידה בזמנים',
        'work_quality_rating': 'איכות עבודה',
        'comment_hint': 'ספר לנו על החוויה שלך...',
        'add_images': 'הוסף תמונות',
        'submit': widget.existingReview != null ? 'עדכן ביקורת' : 'שלח ביקורת',
        'uploading': 'שולח ביקורת...',
        'rating_summary': 'איך הייתה החוויה שלך?',
        'comment_required': 'אנא כתוב תגובה',
        'submit_failed': 'הגשת הביקורת נכשלה',
      };
    }
    if (locale == 'ar') {
      return {
        'title': widget.existingReview != null
            ? 'تعديل التقييم'
            : 'كتابة تقييم',
        'profession_label': 'اختر المهنة:',
        'rating_details': 'تفاصيل جودة الخدمة',
        'price_rating': 'السعر',
        'service_rating': 'الخدمة',
        'timing_rating': 'الالتزام بالمواعيد',
        'work_quality_rating': 'جودة العمل',
        'comment_hint': 'أخبرنا عن تجربتك...',
        'add_images': 'إضافة صور',
        'submit': widget.existingReview != null
            ? 'تحديث التقييم'
            : 'إرسال التقييم',
        'uploading': 'جارٍ إرسال التقييم...',
        'rating_summary': 'كيف كانت تجربتك؟',
        'comment_required': 'يرجى كتابة تعليق',
        'submit_failed': 'فشل إرسال التقييم',
      };
    }
    if (locale == 'am') {
      return {
        'title': widget.existingReview != null ? 'ግምገማ አርትዕ' : 'ግምገማ ጻፍ',
        'profession_label': 'ሙያ ይምረጡ:',
        'rating_details': 'የአገልግሎት ጥራት ዝርዝር',
        'price_rating': 'ዋጋ',
        'service_rating': 'አገልግሎት',
        'timing_rating': 'ሰዓት አክባሪነት',
        'work_quality_rating': 'የስራ ጥራት',
        'comment_hint': 'ስለ ተሞክሮዎ ይንገሩን...',
        'add_images': 'ምስሎች ጨምር',
        'submit': widget.existingReview != null ? 'ግምገማ አዘምን' : 'ግምገማ ላክ',
        'uploading': 'ግምገማ በመላክ ላይ...',
        'rating_summary': 'ተሞክሮዎ እንዴት ነበር?',
        'comment_required': 'እባክዎ አስተያየት ይጻፉ',
        'submit_failed': 'ግምገማ መላክ አልተሳካም',
      };
    }
    if (locale == 'ru') {
      return {
        'title': widget.existingReview != null
            ? 'Изменить отзыв'
            : 'Написать отзыв',
        'profession_label': 'Выберите профессию:',
        'rating_details': 'Оценка качества услуги',
        'price_rating': 'Цена',
        'service_rating': 'Сервис',
        'timing_rating': 'Соблюдение сроков',
        'work_quality_rating': 'Качество работы',
        'comment_hint': 'Расскажите о вашем опыте...',
        'add_images': 'Добавить изображения',
        'submit': widget.existingReview != null
            ? 'Обновить отзыв'
            : 'Отправить отзыв',
        'uploading': 'Отправка отзыва...',
        'rating_summary': 'Какой был ваш опыт?',
        'comment_required': 'Пожалуйста, напишите комментарий',
        'submit_failed': 'Не удалось отправить отзыв',
      };
    }
    return {
      'title': widget.existingReview != null ? 'Edit Review' : 'Write a Review',
      'profession_label': 'Select Profession:',
      'rating_details': 'Service Quality Details',
      'price_rating': 'Price',
      'service_rating': 'Service',
      'timing_rating': 'Timeliness',
      'work_quality_rating': 'Work Quality',
      'comment_hint': 'Tell us about your experience...',
      'add_images': 'Add Images',
      'submit': widget.existingReview != null
          ? 'Update Review'
          : 'Submit Review',
      'uploading': 'Submitting review...',
      'rating_summary': 'How was your experience?',
      'comment_required': 'Please write a comment',
      'submit_failed': 'Failed to submit review',
    };
  }

  Widget _buildRatingSlider(
    String label,
    double rating,
    Color color,
    Function(double) onRatingChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.14),
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.12),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: rating.clamp(1.0, 10.0).toDouble(),
            min: 1,
            max: 10,
            divisions: 90,
            label: rating.toStringAsFixed(1),
            onChanged: (value) => onRatingChanged((value * 10).round() / 10),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('1'), Text('10')],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings();
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            strings['title']!,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.black,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings['rating_summary']!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              if (widget.professions.length > 1) ...[
                Text(
                  strings['profession_label']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedProfession,
                  items: widget.professions
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedProfession = val),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              Text(
                strings['rating_details']!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A0F172A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildRatingSlider(
                      strings['price_rating']!,
                      _priceRating,
                      const Color(0xFFFBBF24),
                      (val) => setState(() => _priceRating = val),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    _buildRatingSlider(
                      strings['service_rating']!,
                      _serviceRating,
                      const Color(0xFF3B82F6),
                      (val) => setState(() => _serviceRating = val),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    _buildRatingSlider(
                      strings['timing_rating']!,
                      _timingRating,
                      const Color(0xFF34D399),
                      (val) => setState(() => _timingRating = val),
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    _buildRatingSlider(
                      strings['work_quality_rating']!,
                      _workQualityRating,
                      const Color(0xFF7C3AED),
                      (val) => setState(() => _workQualityRating = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              TextField(
                controller: _commentController,
                maxLines: 4,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: strings['comment_hint'],
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings['add_images']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    "${_existingImageUrls.length + _newImages.length}/5",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _existingImageUrls.length + _newImages.length < 5
                      ? _existingImageUrls.length + _newImages.length + 1
                      : 5,
                  itemBuilder: (context, index) {
                    if (index < _existingImageUrls.length) {
                      return _buildImageThumb(
                        NetworkImage(_existingImageUrls[index]),
                        () => _removeExistingImage(index),
                      );
                    } else if (index <
                        _existingImageUrls.length + _newImages.length) {
                      int newIdx = index - _existingImageUrls.length;
                      return _buildImageThumb(
                        FileImage(_newImages[newIdx]),
                        () => _removeNewImage(newIdx),
                      );
                    } else {
                      return GestureDetector(
                        onTap: _pickImages,
                        child: Container(
                          width: 88,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: Colors.grey[400],
                            size: 26,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isUploading ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        strings['submit']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageThumb(ImageProvider image, VoidCallback onRemove) {
    return Container(
      width: 88,
      margin: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              image: DecorationImage(image: image, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
