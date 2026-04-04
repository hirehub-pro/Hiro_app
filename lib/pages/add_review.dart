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

  Future<void> _recalculateProRatingsForWorker() async {
    final firestore = FirebaseFirestore.instance;
    final workerRef = firestore.collection('users').doc(widget.targetUserId);
    final reviewsSnap = await workerRef.collection('reviews').get();

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final doc in reviewsSnap.docs) {
      final data = doc.data();
      final profession = (data['profession'] ?? '').toString().trim();
      if (profession.isEmpty) continue;
      grouped.putIfAbsent(profession, () => []).add(data);
    }

    final batch = firestore.batch();
    final proRatingCol = workerRef.collection('ProRating');

    final existingDocs = await proRatingCol.get();
    for (final oldDoc in existingDocs.docs) {
      if (!grouped.containsKey(oldDoc.id)) {
        final existingData = oldDoc.data();
        batch.set(oldDoc.reference, {
          'profession': (existingData['profession'] ?? oldDoc.id).toString(),
          'reviewCount': 0,
          'avgOverallRating': 0.0,
          'avgPriceRating': 0.0,
          'avgServiceRating': 0.0,
          'avgTimingRating': 0.0,
          'avgWorkQualityRating': 0.0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    final Map<String, dynamic> professionStats = {};
    int totalReviews = 0;
    double totalOverallSum = 0.0;

    grouped.forEach((profession, reviews) {
      final count = reviews.length;
      if (count == 0) return;

      double overallSum = 0.0;
      double priceSum = 0.0;
      double serviceSum = 0.0;
      double timingSum = 0.0;
      double workQualitySum = 0.0;

      for (final review in reviews) {
        final overall = _toDouble(review['rating'], fallback: 0.0);
        final price = _toDouble(review['priceRating'], fallback: overall);
        final service = _toDouble(
          review['serviceRating'],
          fallback: _toDouble(
            review['professionalismRating'],
            fallback: overall,
          ),
        );
        final timing = _toDouble(review['timingRating'], fallback: overall);
        final workQuality = _toDouble(
          review['workQualityRating'],
          fallback: _toDouble(review['workRating'], fallback: overall),
        );

        overallSum += overall;
        priceSum += price;
        serviceSum += service;
        timingSum += timing;
        workQualitySum += workQuality;
      }

      final avgOverall = overallSum / count;
      final avgPrice = priceSum / count;
      final avgService = serviceSum / count;
      final avgTiming = timingSum / count;
      final avgWorkQuality = workQualitySum / count;

      final docId = _docIdForProfession(profession);
      batch.set(proRatingCol.doc(docId), {
        'profession': profession,
        'reviewCount': count,
        'avgOverallRating': avgOverall,
        'avgPriceRating': avgPrice,
        'avgServiceRating': avgService,
        'avgTimingRating': avgTiming,
        'avgWorkQualityRating': avgWorkQuality,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      professionStats[profession] = {'avg': avgOverall, 'count': count};

      totalReviews += count;
      totalOverallSum += overallSum;
    });

    batch.set(workerRef, {
      'professionStats': professionStats,
      'avgRating': totalReviews == 0 ? 0.0 : totalOverallSum / totalReviews,
      'reviewCount': totalReviews,
      'ratingsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> _submitReview() async {
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('אנא כתוב תגובה')));
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

      // Unified collection name 'users'
      final reviewCollection = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.targetUserId)
          .collection('reviews');

      if (widget.existingReview != null) {
        await reviewCollection
            .doc(widget.existingReview!['id'])
            .update(reviewData);
      } else {
        await reviewCollection.doc(user.uid).set(reviewData);
      }

      await _recalculateProRatingsForWorker();

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Review upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('הגשת הביקורת נכשלה: $e')));
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
    final isRtl =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he';

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
