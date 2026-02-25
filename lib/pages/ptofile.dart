import 'package:flutter/material.dart';
import 'package:untitled1/pages/search.dart';
import 'package:untitled1/pages/settings.dart';
import 'formu.dart';
import 'home_page.dart';


class profile extends StatefulWidget{
  const profile({super.key});

  @override
  State<profile> createState() => _profileState();
}

class _profileState extends State<profile> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 100,
            height: 100,

            child: IconButton(
              icon: Icon(Icons.home, color: Colors.black, size: 24),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HomePageWidget(),
                  ),
                );
              },
            ),
          ),
          Container(
            width: 100,
            height: 100,
            child: IconButton(
              icon: Icon(Icons.search_sharp, color: Colors.black, size: 24),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SearchPage(),
                  ),
                );
              },
            ),
          ),
          Container(
            width: 100,
            height: 100,

            child: IconButton(
              icon: Icon(Icons.four_k_rounded, color: Colors.black, size: 24),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const BlogPage()),
                );
              },
            ),
          ),
          Container(
            width: 100,
            height: 100,
            child: IconButton(
              icon: Icon(Icons.person_outlined, color: Colors.black, size: 24),
              onPressed: () {
              },
            ),
          ),
        ],
      ),

      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Profile'),
        centerTitle: true,

      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[300],
              child: const Icon(Icons.person, size: 50),
            ),
            const SizedBox(height: 16),
            const Text(
              'User Name',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'user@example.com',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text('Help & Support'),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}