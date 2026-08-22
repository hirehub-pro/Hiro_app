import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:untitled1/utils/constants.dart';

class PrivacyPolicyPage extends StatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  State<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<PrivacyPolicyPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Cache-busting URL to ensure the app fetches the latest version from the server
    final cacheBusterUrl =
        "${AppConstants.privacyPolicyUrl}?v=${DateTime.now().millisecondsSinceEpoch}";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..clearCache() // Explicitly clear cache to handle aggressive WebView storage
      ..loadRequest(Uri.parse(cacheBusterUrl));
  }

  @override
  Widget build(BuildContext context) {
    final isHe =
        Provider.of<LanguageProvider>(context).locale.languageCode == 'he';
    return Directionality(
      textDirection: isHe ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isHe ? 'מדיניות פרטיות' : 'Privacy Policy'),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
