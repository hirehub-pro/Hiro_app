import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/widgets/tour_tip_dialog.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:video_player/video_player.dart';

class AddProjectPage extends StatefulWidget {
  final String? tourIntroText;

  const AddProjectPage({super.key, this.tourIntroText});

  @override
  State<AddProjectPage> createState() => _AddProjectPageState();
}

class _AddProjectPageState extends State<AddProjectPage> {
  final _descriptionController = TextEditingController();
  final List<File> _mediaFiles = [];
  bool _isUploading = false;
  double _uploadProgress = 0;
  final _picker = ImagePicker();
  bool _tourIntroShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTourIntroIfNeeded();
    });
  }

  Future<void> _showTourIntroIfNeeded() async {
    if (_tourIntroShown) return;
    final intro = widget.tourIntroText;
    if (intro == null || intro.isEmpty || !mounted) return;
    _tourIntroShown = true;

    final strings = _getLocalizedStrings();
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';

    await showTourTipDialog(
      context: context,
      title: strings['title']!,
      body: intro,
      stepLabel: isRtl ? 'שלב 1 / 8' : 'Step 1 / 8',
      icon: Icons.add_photo_alternate_rounded,
      isRtl: isRtl,
      confirmLabel: isRtl ? 'הבנתי' : 'Got it',
    );
  }

  bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv');
  }

  void _showLimitReached() {
    final strings = _getLocalizedStrings();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings['limit_reached']!),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _pickImages() async {
    if (_mediaFiles.length >= 5) {
      _showLimitReached();
      return;
    }
    final remaining = 5 - _mediaFiles.length;
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 70);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _mediaFiles.addAll(
          pickedFiles.take(remaining).map((file) => File(file.path)),
        );
      });
      if (pickedFiles.length > remaining) {
        _showLimitReached();
      }
    }
  }

  Future<void> _pickVideo() async {
    if (_mediaFiles.length >= 5) {
      _showLimitReached();
      return;
    }
    final strings = _getLocalizedStrings();
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 1),
    );

    if (video != null) {
      // Secondary manual check for safety
      final controller = VideoPlayerController.file(File(video.path));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();

      if (duration.inSeconds > 60) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings['video_too_long']!),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _mediaFiles.add(File(video.path));
      });
    }
  }

  void _showPickerOptions() {
    final strings = _getLocalizedStrings();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  strings['pick_media']!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library, color: Colors.blue[700]),
                ),
                title: Text(strings['image']!),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.video_library, color: Colors.orange[700]),
                ),
                title: Text(strings['video']!),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _removeMedia(int index) {
    setState(() {
      _mediaFiles.removeAt(index);
    });
  }

  Future<File?> _compressImage(File file) async {
    final tempDir = await path_provider.getTemporaryDirectory();
    final path = tempDir.path;
    final targetPath =
        "$path/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg";

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80,
    );

    return result != null ? File(result.path) : null;
  }

  Future<void> _saveProject() async {
    if (_mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא בחר לפחות תמונה או סרטון אחד')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      List<String> mediaUrls = [];

      for (var i = 0; i < _mediaFiles.length; i++) {
        File fileToUpload = _mediaFiles[i];
        final isVideoFile = _isVideo(fileToUpload.path);

        if (!isVideoFile) {
          final compressed = await _compressImage(fileToUpload);
          if (compressed != null) fileToUpload = compressed;
        }

        final extension = isVideoFile ? 'mp4' : 'jpg';
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_$i.$extension';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('projects')
            .child(user.uid)
            .child(fileName);

        final metadata = SettableMetadata(
          contentType: isVideoFile ? 'video/mp4' : 'image/jpeg',
        );
        final uploadTask = storageRef.putFile(fileToUpload, metadata);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          setState(() {
            _uploadProgress =
                (i / _mediaFiles.length) +
                (snapshot.bytesTransferred / snapshot.totalBytes) /
                    _mediaFiles.length;
          });
        });

        await uploadTask;
        final url = await storageRef.getDownloadURL();
        mediaUrls.add(url);
      }

      // Save under 'users' collection sub-collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('projects')
          .add({
            'imageUrls': mediaUrls,
            'imageUrl': mediaUrls.first,
            'description': _descriptionController.text.trim(),
            'timestamp': FieldValue.serverTimestamp(),
            'hasVideo': _mediaFiles.any((f) => _isVideo(f.path)),
            'mediaTypes': _mediaFiles
                .map((f) => _isVideo(f.path) ? 'video' : 'image')
                .toList(),
          });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('העלאה נכשלה: $e')));
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
        'title': 'הוסף פרויקט חדש',
        'description': 'תיאור הפרויקט (מה בוצע?)',
        'pick_media': 'בחירת מדיה',
        'save': 'שמור ופרסם',
        'uploading': 'מעלה פרויקט...',
        'limit_reached': 'ניתן להעלות עד 5 קבצים',
        'image': 'תמונות מהגלריה',
        'video': 'סרטון מהגלריה',
        'hint': 'ספר ללקוחות שלך על הפרויקט הזה...',
        'video_too_long': 'הסרטון ארוך מדי. המקסימום הוא דקה אחת.',
      };
    }
    return {
      'title': 'Add New Project',
      'description': 'Project Description',
      'pick_media': 'Select Media',
      'save': 'Save & Publish',
      'uploading': 'Uploading...',
      'limit_reached': 'Limit: 5 files max',
      'image': 'Images from Gallery',
      'video': 'Video from Gallery',
      'hint': 'Tell your customers about this project...',
      'video_too_long': 'Video is too long. Maximum is 1 minute.',
    };
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
            style: const TextStyle(fontWeight: FontWeight.bold),
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
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMediaSection(strings),
                  const SizedBox(height: 32),
                  Text(
                    strings['description']!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: strings['hint'],
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
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _saveProject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: Colors.blue.withOpacity(0.4),
                    ),
                    child: Text(
                      strings['save']!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            if (_isUploading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 20),
                          Text(
                            strings['uploading']!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF1976D2),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          const SizedBox(height: 8),
                          Text("${(_uploadProgress * 100).toInt()}%"),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(Map<String, String> strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              strings['pick_media']!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              "${_mediaFiles.length}/5",
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_mediaFiles.isEmpty)
          GestureDetector(
            onTap: _showPickerOptions,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.blue[50]?.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.blue[100]!,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_to_photos_rounded,
                      size: 40,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    strings['pick_media']!,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _mediaFiles.length < 5
                  ? _mediaFiles.length + 1
                  : _mediaFiles.length,
              itemBuilder: (context, index) {
                if (index == _mediaFiles.length && _mediaFiles.length < 5) {
                  return GestureDetector(
                    onTap: _showPickerOptions,
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.grey[400],
                        size: 32,
                      ),
                    ),
                  );
                }

                final file = _mediaFiles[index];
                final isVideo = _isVideo(file.path);

                return Container(
                  width: 100,
                  margin: const EdgeInsets.only(left: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: isVideo
                            ? _VideoThumbnail(file: file)
                            : Image.file(
                                file,
                                fit: BoxFit.cover,
                                width: 100,
                                height: 120,
                              ),
                      ),
                      if (isVideo)
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white70,
                            size: 32,
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeMedia(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  final File file;
  const _VideoThumbnail({required this.file});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? VideoPlayer(_controller)
        : Container(
            color: Colors.black12,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
  }
}
