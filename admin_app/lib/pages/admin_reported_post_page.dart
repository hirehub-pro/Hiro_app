import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminReportedPostPage extends StatelessWidget {
  final Map<String, dynamic> post;

  const AdminReportedPostPage({super.key, required this.post});

  List<String> get _images {
    final values = <String>[];
    final list = post['imageUrls'];
    if (list is Iterable) values.addAll(list.map((item) => item.toString()));
    final single = post['imageUrl']?.toString() ?? '';
    if (single.isNotEmpty && !values.contains(single)) values.add(single);
    return values.where((url) => url.startsWith('http')).toList();
  }

  String _value(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is Iterable) return value.join(', ');
    return value?.toString() ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final entries = post.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Reported Post')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final url in _images)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SelectableText(
                        '${entry.key}: ${_value(entry.value)}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
