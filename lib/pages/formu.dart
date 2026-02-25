import 'package:flutter/material.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/search.dart';
import 'home_page.dart';


class BlogPage extends StatelessWidget {
  const BlogPage({Key? key}) : super(key: key);

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

              icon: Icon(Icons.four_k_outlined, color: Colors.black, size: 24),
              onPressed: () {},
            ),
          ),
          Container(
            width: 100,
            height: 100,

            child: IconButton(

              icon: Icon(
                Icons.person_sharp,
                color: const Color.fromARGB(255, 0, 0, 0),
                size: 24,
              ),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const profile()),
                );
              },
            ),
          ),
        ],
      ),
      appBar: AppBar(title: const Text('Blog'), centerTitle: true,backgroundColor: Colors.white,),

      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _BlogCard(
            title: 'Getting Started with Flutter',
            date: 'March 15, 2024',
            excerpt: 'Learn the basics of Flutter development...',
          ),
          _BlogCard(
            title: 'Dart Tips and Tricks',
            date: 'March 10, 2024',
            excerpt: 'Improve your Dart programming skills...',
          ),
          _BlogCard(
            title: 'State Management in Flutter',
            date: 'March 5, 2024',
            excerpt: 'Explore different state management solutions...',
          ),
        ],
      ),
    );
  }
}

class _BlogCard extends StatelessWidget {
  final String title;
  final String date;
  final String excerpt;

  const _BlogCard({
    required this.title,
    required this.date,
    required this.excerpt,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8.0),
            Text(date, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12.0),
            Text(excerpt),
          ],
        ),
      ),
    );
  }
}
