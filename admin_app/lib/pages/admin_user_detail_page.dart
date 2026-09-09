import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdminUserDetailPage extends StatelessWidget {
  final String userId;

  const AdminUserDetailPage({super.key, required this.userId});

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _load() {
    final db = FirebaseFirestore.instance;
    return Future.wait([
      db.collection('users').doc(userId).get(),
      db.collection('publicWorkerProfiles').doc(userId).get(),
      db
          .collection('users')
          .doc(userId)
          .collection('verification_info')
          .doc('latest')
          .get(),
    ]);
  }

  String _value(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is Iterable) return value.join(', ');
    return value?.toString() ?? '—';
  }

  Widget _section(String title, Map<String, dynamic> data) {
    final entries = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Divider(height: 24),
            if (entries.isEmpty) const Text('No document found.'),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectableText('${entry.key}: ${_value(entry.value)}'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Details'),
        actions: [
          IconButton(
            tooltip: 'Copy UID',
            onPressed: () => Clipboard.setData(ClipboardData(text: userId)),
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load user: ${snapshot.error}'),
            );
          }
          final docs = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SelectableText(
                'UID: $userId',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _section('Private account', docs[0].data() ?? {}),
              _section('Public worker profile', docs[1].data() ?? {}),
              _section('Verification', docs[2].data() ?? {}),
            ],
          );
        },
      ),
    );
  }
}
