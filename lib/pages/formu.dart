import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/language_provider.dart';
import 'package:untitled1/pages/ptofile.dart';

class BlogPage extends StatefulWidget {
  const BlogPage({Key? key}) : super(key: key);

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  final List<Map<String, dynamic>> _customPosts = [];

  // Basic moderation list
  final List<String> _blockedKeywords = [
    'buy now', 'discount', 'sale', 'free', 'click here', 'http', 'www', 'promo',
    'offensive_word1', 'offensive_word2',
    'asdf', 'qwerty', 'zxcv'
  ];

  bool _isSafe(String text) {
    final lowerText = text.toLowerCase();
    if (text.trim().length < 10) return false;
    for (var keyword in _blockedKeywords) {
      if (lowerText.contains(keyword)) return false;
    }
    final repeatRegex = RegExp(r'(.)\1{4,}');
    if (repeatRegex.hasMatch(lowerText)) return false;
    return true;
  }

  Map<String, dynamic> _getLocalizedStrings(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    switch (locale) {
      case 'he':
        return {
          'title': 'בלוג וטיפים',
          'featured': 'כתבות מומלצות',
          'create_post': 'כתוב פוסט חדש',
          'post_title': 'כותרת הפוסט',
          'post_category': 'קטגוריה',
          'post_content': 'תוכן הפוסט',
          'rules': 'שים לב: פוסטים הכוללים פרסומות או תוכן פוגעני יימחקו.',
          'publish': 'פרסם',
          'cancel': 'ביטול',
          'invalid_content': 'הפוסט נראה כמו פרסומת, תוכן פוגעני או ג\'יבריש. אנא נסה שוב.',
          'author': 'מחבר',
          'comments': 'תגובות',
          'write_comment': 'כתוב תגובה...',
          'posts': [
            {
              'title': 'איך לבחור את בעל המקצוע הנכון',
              'authorName': 'אבי כהן',
              'date': '15 במרץ 2024',
              'excerpt': 'טיפים לבחירת אינסטלטור או חשמלאי אמין שיבצע את העבודה על הצד הטוב ביותר...',
              'content': 'בחירת בעל מקצוע היא משימה מורכבת. מומלץ תמיד לבקש המלצות מחברים, לבדוק עבודות קודמות ולוודא שיש לו את ההסמכות המתאימות. אל תתפתו תמיד למחיר הנמוך ביותר, שכן איכות העבודה חשובה לא פחות.',
              'category': 'מדריך',
              'likes': 45,
              'dislikes': 2,
            },
            {
              'title': 'חידוש הבית בתקציב נמוך',
              'authorName': 'דנה לוי',
              'date': '10 במרץ 2024',
              'excerpt': 'איך לצבוע את הבית לבד ולחסוך בעלויות תוך קבלת תוצאה מקצועית ומרשימה...',
              'content': 'צביעת הבית היא הדרך המהירה והזולה ביותר לשדרג את המראה שלו. חשוב להכין את הקירות מראש, להשתמש בצבע איכותי ובמברשות מתאימות. התחילו מהפינות ועברו לשטחים הגדולים יותר.',
              'category': 'עיצוב',
              'likes': 32,
              'dislikes': 1,
            },
          ]
        };
      case 'ar':
        return {
          'title': 'المدونة والنصائح',
          'featured': 'مقالات مختارة',
          'create_post': 'اكتب مقالاً جديداً',
          'post_title': 'عنوان المقال',
          'post_category': 'الفئة',
          'post_content': 'محتوى المقال',
          'rules': 'ملاحظة: سيتم حذف المنشورات التي تتضمن إعلانات أو محتوى مسيء.',
          'publish': 'نشر',
          'cancel': 'إلغاء',
          'invalid_content': 'يبدو أن المنشور يحتوي على إعلانات أو محتوى غير لائق. يرجى المحاولة مرة أخرى.',
          'author': 'مؤلف',
          'comments': 'تعليقات',
          'write_comment': 'اكتب تعليقاً...',
          'posts': [
            {
              'title': 'كيفية اختيار المحترف المناسب',
              'authorName': 'أحمد محمد',
              'date': '15 مارس 2024',
              'excerpt': 'نصائح لاختيار سباك أو كهربائي موثوق للقيام بالعمل على أكمل وجه...',
              'content': 'يعد اختيار المحترف المناسب أمرًا حيويًا. تأكد من مراجعة التقييمات السابقة وطلب المراجع. الجودة أهم من السعر الأرخص دائمًا.',
              'category': 'دليل',
              'likes': 28,
              'dislikes': 0,
            },
            {
              'title': 'تجديد المنزل بميزانية محدودة',
              'authorName': 'ليلى خالد',
              'date': '10 مارس 2024',
              'excerpt': 'كيفية طلاء المنزل بنفسك وتوفير التكاليف مع الحصول على نتيجة احترافية...',
              'content': 'طلاء الجدران هو أسهل طريقة لتجديد المنزل. قم بتغطية الأثاث جيدًا واستخدم شريطًا لاصقًا للحواف النظيفة.',
              'category': 'تصميم',
              'likes': 19,
              'dislikes': 1,
            },
          ]
        };
      default:
        return {
          'title': 'Blog & Tips',
          'featured': 'Featured Posts',
          'create_post': 'Create a new post',
          'post_title': 'Post Title',
          'post_category': 'Category',
          'post_content': 'Post Content',
          'rules': 'Note: Posts containing advertisements or nonsense will be removed.',
          'publish': 'Publish',
          'cancel': 'Cancel',
          'invalid_content': 'Your post appears to contain spam, nonsense, or offensive material. Please revise.',
          'author': 'Author',
          'comments': 'Comments',
          'write_comment': 'Write a comment...',
          'posts': [
            {
              'title': 'How to Choose the Right Pro',
              'authorName': 'John Doe',
              'date': 'March 15, 2024',
              'excerpt': 'Tips for choosing a reliable plumber or electrician to get the job done right...',
              'content': 'Finding a reliable professional can be tricky. Always check reviews, ask for references, and ensure they have the necessary licenses. Don\'t just go for the cheapest quote; quality and reliability are paramount.',
              'category': 'Guide',
              'likes': 56,
              'dislikes': 3,
            },
            {
              'title': 'Home Renovation on a Budget',
              'authorName': 'Jane Smith',
              'date': 'March 10, 2024',
              'excerpt': 'How to paint your home yourself and save costs while getting professional results...',
              'content': 'Painting is the most cost-effective way to refresh your home. Preparation is key: clean the walls, tape the edges, and use high-quality rollers. One or two coats can make a world of difference.',
              'category': 'DIY',
              'likes': 42,
              'dislikes': 0,
            },
          ]
        };
    }
  }

  void _showCreatePostSheet(BuildContext context, Map<String, dynamic> strings) {
    final titleController = TextEditingController();
    final categoryController = TextEditingController();
    final contentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings['create_post'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(strings['rules'], style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(controller: titleController, decoration: InputDecoration(labelText: strings['post_title'], border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: categoryController, decoration: InputDecoration(labelText: strings['post_category'], border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: contentController, maxLines: 5, decoration: InputDecoration(labelText: strings['post_content'], border: const OutlineInputBorder())),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(strings['cancel'])),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text;
                    final content = contentController.text;
                    if (title.isNotEmpty && content.isNotEmpty) {
                      if (_isSafe(title) && _isSafe(content)) {
                        setState(() {
                          _customPosts.insert(0, {
                            'title': title,
                            'authorName': 'Me', // Simplified for now
                            'date': 'Just now',
                            'excerpt': content.length > 100 ? content.substring(0, 100) + '...' : content,
                            'content': content,
                            'category': categoryController.text.isNotEmpty ? categoryController.text : 'General',
                            'isUserPost': true,
                            'likes': 0,
                            'dislikes': 0,
                          });
                        });
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings['invalid_content'])));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2)),
                  child: Text(strings['publish'], style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    // For now, since it's local data or static, we just simulate a delay.
    // If you add real Firebase fetching for posts, call it here.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = _getLocalizedStrings(context);
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isRtl = locale == 'he' || locale == 'ar';
    final allPosts = [..._customPosts, ...strings['posts']];

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCreatePostSheet(context, strings),
          backgroundColor: const Color(0xFF1976D2),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120.0,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(strings['title'], style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  centerTitle: true,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Text(strings['featured'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = allPosts[index];
                    return _BlogCard(
                      post: post,
                      localizedStrings: strings,
                    );
                  },
                  childCount: allPosts.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlogCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic> localizedStrings;

  const _BlogCard({Key? key, required this.post, required this.localizedStrings}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          // Show full post content in a dialog or new page
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(post['title']),
              content: SingleChildScrollView(child: Text(post['content'])),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(post['category'], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const Spacer(),
                  Text(post['date'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Text(post['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 8),
              Text(post['excerpt'], style: const TextStyle(color: Colors.grey, height: 1.4)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(post['authorName'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const Spacer(),
                  Icon(Icons.thumb_up_outlined, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 4),
                  Text(post['likes'].toString(), style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
