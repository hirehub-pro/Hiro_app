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
  double _priceRating = 5.0;
  double _workRating = 5.0;
  double _professionalismRating = 5.0;

  final List<File> _newImages = [];
  List<String> _existingImageUrls = [];
  bool _isUploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.existingReview != null) {
      _commentController.text = widget.existingReview!['comment'] ?? '';
      _priceRating = (widget.existingReview!['priceRating'] ?? 5.0).toDouble();
      _workRating = (widget.existingReview!['workRating'] ?? 5.0).toDouble();
      _professionalismRating =
          (widget.existingReview!['professionalismRating'] ?? 5.0).toDouble();
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

  String _docIdForProfession(String profession) {
    return profession.trim().replaceAll('/', '_');
  }

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  Map<String, double> _reviewMetrics(Map<String, dynamic> review) {
    final overall = _toDouble(review['rating'], fallback: 0.0);
    final price = _toDouble(review['priceRating'], fallback: overall);
    final service = _toDouble(
      review['serviceRating'],
      fallback: _toDouble(review['professionalismRating'], fallback: overall),
    );
    final timing = _toDouble(review['timingRating'], fallback: overall);
    final workQuality = _toDouble(
      review['workQualityRating'],
      fallback: _toDouble(review['workRating'], fallback: overall),
    );

    return {
      'overall': overall,
      'price': price,
      'service': service,
      'timing': timing,
      'workQuality': workQuality,
    };
  }

  Map<String, dynamic> _buildProfessionAggregateUpdate({
    required String profession,
    required int reviewCount,
    required double totalStars,
    required double totalPriceStars,
    required double totalServiceStars,
    required double totalTimingStars,
    required double totalWorkQualityStars,
  }) {
    final safeCount = reviewCount < 0 ? 0 : reviewCount;
    final divisor = safeCount == 0 ? 1 : safeCount;

    return {
      'profession': profession,
      'reviewCount': safeCount,
      'totalStars': totalStars < 0 ? 0.0 : totalStars,
      'totalPriceStars': totalPriceStars < 0 ? 0.0 : totalPriceStars,
      'totalServiceStars': totalServiceStars < 0 ? 0.0 : totalServiceStars,
      'totalTimingStars': totalTimingStars < 0 ? 0.0 : totalTimingStars,
      'totalWorkQualityStars': totalWorkQualityStars < 0
          ? 0.0
          : totalWorkQualityStars,
      'avgOverallRating': safeCount == 0 ? 0.0 : totalStars / divisor,
      'avgPriceRating': safeCount == 0 ? 0.0 : totalPriceStars / divisor,
      'avgServiceRating': safeCount == 0 ? 0.0 : totalServiceStars / divisor,
      'avgTimingRating': safeCount == 0 ? 0.0 : totalTimingStars / divisor,
      'avgWorkQualityRating': safeCount == 0
          ? 0.0
          : totalWorkQualityStars / divisor,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _updateWorkerRatingAggregates({
    required DocumentReference<Map<String, dynamic>> reviewRef,
    required Map<String, dynamic> newReviewData,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final workerRef = firestore.collection('users').doc(widget.targetUserId);
    final proRatingCol = workerRef.collection('ProRating');

    await firestore.runTransaction((tx) async {
      final workerSnap = await tx.get(workerRef);
      final reviewSnap = await tx.get(reviewRef);

      final existingReview = reviewSnap.data();
      final oldProfession = (existingReview?['profession'] ?? '')
          .toString()
          .trim();
      final newProfession = (newReviewData['profession'] ?? '')
          .toString()
          .trim();
      if (newProfession.isEmpty) {
        throw StateError('Review profession is required.');
      }

      final oldMetrics = existingReview == null
          ? null
          : _reviewMetrics(Map<String, dynamic>.from(existingReview));
      final newMetrics = _reviewMetrics(newReviewData);

      final oldProRef = oldProfession.isEmpty
          ? null
          : proRatingCol.doc(_docIdForProfession(oldProfession));
      final newProRef = proRatingCol.doc(_docIdForProfession(newProfession));

      DocumentSnapshot<Map<String, dynamic>>? oldProSnap;
      if (oldProRef != null) {
        oldProSnap = await tx.get(oldProRef);
      }
      final newProSnap = oldProfession == newProfession && oldProSnap != null
          ? oldProSnap
          : await tx.get(newProRef);

      final workerData = workerSnap.data() ?? <String, dynamic>{};
      final currentReviewCount =
          (workerData['reviewCount'] as num?)?.toInt() ?? 0;
      final currentTotalStars = _toDouble(
        workerData['totalStars'],
        fallback: 0.0,
      );

      int nextReviewCount = currentReviewCount;
      double nextTotalStars = currentTotalStars;

      if (oldMetrics == null) {
        nextReviewCount += 1;
      } else {
        nextTotalStars -= oldMetrics['overall'] ?? 0.0;
      }
      nextTotalStars += newMetrics['overall'] ?? 0.0;

      final safeReviewCount = nextReviewCount < 0 ? 0 : nextReviewCount;
      final safeTotalStars = nextTotalStars < 0 ? 0.0 : nextTotalStars;
      final nextAvgRating = safeReviewCount == 0
          ? 0.0
          : safeTotalStars / safeReviewCount;

      final professionStats = Map<String, dynamic>.from(
        (workerData['professionStats'] as Map<String, dynamic>?) ?? {},
      );

      if (oldProRef != null) {
        final oldData = oldProSnap?.data() ?? <String, dynamic>{};
        var oldCount = (oldData['reviewCount'] as num?)?.toInt() ?? 0;
        var oldTotalStars = _toDouble(oldData['totalStars'], fallback: 0.0);
        var oldTotalPriceStars = _toDouble(
          oldData['totalPriceStars'],
          fallback: oldTotalStars,
        );
        var oldTotalServiceStars = _toDouble(
          oldData['totalServiceStars'],
          fallback: oldTotalStars,
        );
        var oldTotalTimingStars = _toDouble(
          oldData['totalTimingStars'],
          fallback: oldTotalStars,
        );
        var oldTotalWorkQualityStars = _toDouble(
          oldData['totalWorkQualityStars'],
          fallback: oldTotalStars,
        );

        if (oldMetrics != null) {
          oldCount -= 1;
          oldTotalStars -= oldMetrics['overall'] ?? 0.0;
          oldTotalPriceStars -= oldMetrics['price'] ?? 0.0;
          oldTotalServiceStars -= oldMetrics['service'] ?? 0.0;
          oldTotalTimingStars -= oldMetrics['timing'] ?? 0.0;
          oldTotalWorkQualityStars -= oldMetrics['workQuality'] ?? 0.0;
        }

        if (oldProfession == newProfession) {
          oldCount += 1;
          oldTotalStars += newMetrics['overall'] ?? 0.0;
          oldTotalPriceStars += newMetrics['price'] ?? 0.0;
          oldTotalServiceStars += newMetrics['service'] ?? 0.0;
          oldTotalTimingStars += newMetrics['timing'] ?? 0.0;
          oldTotalWorkQualityStars += newMetrics['workQuality'] ?? 0.0;
        }

        final updatedOld = _buildProfessionAggregateUpdate(
          profession: oldProfession,
          reviewCount: oldCount,
          totalStars: oldTotalStars,
          totalPriceStars: oldTotalPriceStars,
          totalServiceStars: oldTotalServiceStars,
          totalTimingStars: oldTotalTimingStars,
          totalWorkQualityStars: oldTotalWorkQualityStars,
        );
        tx.set(oldProRef, updatedOld, SetOptions(merge: true));

        if ((updatedOld['reviewCount'] as int) == 0) {
          professionStats.remove(oldProfession);
        } else {
          professionStats[oldProfession] = {
            'avg': updatedOld['avgOverallRating'],
            'count': updatedOld['reviewCount'],
          };
        }
      }

      if (oldProfession != newProfession) {
        final newData = newProSnap.data() ?? <String, dynamic>{};
        final updatedNew = _buildProfessionAggregateUpdate(
          profession: newProfession,
          reviewCount: ((newData['reviewCount'] as num?)?.toInt() ?? 0) + 1,
          totalStars:
              _toDouble(newData['totalStars'], fallback: 0.0) +
              (newMetrics['overall'] ?? 0.0),
          totalPriceStars:
              _toDouble(newData['totalPriceStars'], fallback: 0.0) +
              (newMetrics['price'] ?? 0.0),
          totalServiceStars:
              _toDouble(newData['totalServiceStars'], fallback: 0.0) +
              (newMetrics['service'] ?? 0.0),
          totalTimingStars:
              _toDouble(newData['totalTimingStars'], fallback: 0.0) +
              (newMetrics['timing'] ?? 0.0),
          totalWorkQualityStars:
              _toDouble(newData['totalWorkQualityStars'], fallback: 0.0) +
              (newMetrics['workQuality'] ?? 0.0),
        );
        tx.set(newProRef, updatedNew, SetOptions(merge: true));
        professionStats[newProfession] = {
          'avg': updatedNew['avgOverallRating'],
          'count': updatedNew['reviewCount'],
        };
      } else if (oldProRef == null) {
        final newData = newProSnap.data() ?? <String, dynamic>{};
        final updatedNew = _buildProfessionAggregateUpdate(
          profession: newProfession,
          reviewCount: ((newData['reviewCount'] as num?)?.toInt() ?? 0) + 1,
          totalStars:
              _toDouble(newData['totalStars'], fallback: 0.0) +
              (newMetrics['overall'] ?? 0.0),
          totalPriceStars:
              _toDouble(newData['totalPriceStars'], fallback: 0.0) +
              (newMetrics['price'] ?? 0.0),
          totalServiceStars:
              _toDouble(newData['totalServiceStars'], fallback: 0.0) +
              (newMetrics['service'] ?? 0.0),
          totalTimingStars:
              _toDouble(newData['totalTimingStars'], fallback: 0.0) +
              (newMetrics['timing'] ?? 0.0),
          totalWorkQualityStars:
              _toDouble(newData['totalWorkQualityStars'], fallback: 0.0) +
              (newMetrics['workQuality'] ?? 0.0),
        );
        tx.set(newProRef, updatedNew, SetOptions(merge: true));
        professionStats[newProfession] = {
          'avg': updatedNew['avgOverallRating'],
          'count': updatedNew['reviewCount'],
        };
      }

      tx.set(reviewRef, newReviewData, SetOptions(merge: true));
      tx.set(workerRef, {
        'professionStats': professionStats,
        'totalStars': safeTotalStars,
        'avgRating': nextAvgRating,
        'reviewCount': safeReviewCount,
        'ratingsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

      double overallRating =
          (_priceRating + _workRating + _professionalismRating) / 3;

      final reviewData = {
        'userId': user.uid,
        'userName': user.displayName ?? "Anonymous",
        'userProfileImage': user.photoURL,
        'profession': _selectedProfession,
        'rating': overallRating,
        'priceRating': _priceRating,
        'workRating': _workRating,
        'professionalismRating': _professionalismRating,
        'comment': _commentController.text.trim(),
        'imageUrls': finalImageUrls,
        'timestamp': FieldValue.serverTimestamp(),
      };

      final reviewCollection = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.targetUserId)
          .collection('reviews');
      final reviewId = widget.existingReview != null
          ? widget.existingReview!['id'].toString()
          : user.uid;
      final reviewRef = reviewCollection.doc(reviewId);

      await _updateWorkerRatingAggregates(
        reviewRef: reviewRef,
        newReviewData: reviewData,
      );

      if (widget.existingReview == null) {
        await FirebaseFirestore.instance
            .collection('metadata')
            .doc('system')
            .set({
              'reviewsCount': FieldValue.increment(1),
            }, SetOptions(merge: true));
      }

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
        'price_rating': 'דירוג מחיר',
        'work_rating': 'איכות העבודה',
        'professionalism': 'מקצועיות',
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
        'price_rating': 'تقييم السعر',
        'work_rating': 'جودة العمل',
        'professionalism': 'الاحترافية',
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
        'price_rating': 'የዋጋ ደረጃ',
        'work_rating': 'የስራ ጥራት',
        'professionalism': 'ሙያዊነት',
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
        'price_rating': 'Оценка цены',
        'work_rating': 'Качество работы',
        'professionalism': 'Профессионализм',
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
      'price_rating': 'Price Rating',
      'work_rating': 'Work Quality',
      'professionalism': 'Professionalism',
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

  Widget _buildRatingStars(
    String label,
    double rating,
    Function(double) onRatingChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(5, (index) {
            return IconButton(
              iconSize: 32,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                index < rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: Colors.amber,
              ),
              onPressed: () => onRatingChanged(index + 1.0),
            );
          }),
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings['rating_summary']!,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (widget.professions.length > 1) ...[
                Text(
                  strings['profession_label']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedProfession,
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
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    _buildRatingStars(
                      strings['price_rating']!,
                      _priceRating,
                      (val) => setState(() => _priceRating = val),
                    ),
                    _buildRatingStars(
                      strings['work_rating']!,
                      _workRating,
                      (val) => setState(() => _workRating = val),
                    ),
                    _buildRatingStars(
                      strings['professionalism']!,
                      _professionalismRating,
                      (val) => setState(() => _professionalismRating = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              TextField(
                controller: _commentController,
                maxLines: 5,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: strings['comment_hint'],
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings['add_images']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    "${_existingImageUrls.length + _newImages.length}/5",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 100,
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
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: Colors.grey[400],
                            size: 30,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _isUploading ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
                          fontSize: 18,
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
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
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
                  color: Colors.black.withOpacity(0.5),
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
