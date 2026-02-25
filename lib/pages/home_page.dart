import 'package:untitled1/pages/search.dart';
import 'package:flutter/material.dart';
import 'package:untitled1/pages/ptofile.dart';
import 'package:untitled1/pages/search.dart';

import 'formu.dart';
import 'home_page_model.dart';
class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';
  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget>
    with TickerProviderStateMixin {
  late HomePageModel _model;

  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _model.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 0, 55, 255),
          toolbarHeight: 150,

              title:  Text('user101'),
             leading:  Row(
                children:[ TextField(

                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xfff1f1f1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    hintText: "Search for Items",
                    prefixIcon: const Icon(Icons.search),
                    prefixIconColor: Colors.black,
                  ),
                ),
             ] ),



          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(15),
              bottomRight: Radius.circular(15),
            ),
          ),
          automaticallyImplyLeading: false,
          actions: [],
          centerTitle: false,
          elevation: 2,
        ),

        body: NestedScrollView(
          floatHeaderSlivers: false,
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              expandedHeight: 1,
              collapsedHeight: 1,
              pinned: false,
              floating: false,
              backgroundColor: Color(0xFF1944DE),
              automaticallyImplyLeading: false,
              actions: [],
              flexibleSpace: FlexibleSpaceBar(
                title: Text('welcome home user101'),
                centerTitle: false,
                expandedTitleScale: 1.0,
              ),
              toolbarHeight: 1,
              elevation: 2,
            ),
          ],
          body: Builder(
            builder: (context) {
              return SafeArea(
                top: false,
                child: Align(
                  alignment: AlignmentDirectional(0, 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,

                        child: IconButton(

                          icon: Icon(
                            Icons.home,
                            color: const Color.fromARGB(255, 47, 0, 255),
                            size: 24,
                          ),
                          onPressed: () {},
                        ),
                      ),
                      Container(
                        width: 100,
                        height: 100,

                        child: IconButton(

                          icon: Icon(
                            Icons.search_sharp,
                            color: Colors.black,
                            size: 24,
                          ),
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

                          icon: Icon(
                            Icons.four_k_rounded,
                            color: Colors.black,
                            size: 24,
                          ),
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BlogPage(),
                              ),
                            );
                          },
                        ),
                      ),

                      Container(
                        width: 100,
                        height: 100,

                        child: IconButton(
                          icon: Icon(
                            Icons.person_sharp,
                            color: Colors.black,
                            size: 24,
                          ),

                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const profile(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

