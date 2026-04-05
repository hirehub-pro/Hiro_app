import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:untitled1/sign_up.dart';

class SubscriptionPage extends StatefulWidget {
  final String email;
  final Map<String, dynamic>? pendingUserData;
  final File? pendingImage;
  final bool isNewRegistration;

  const SubscriptionPage({
    super.key,
    required this.email,
    this.pendingUserData,
    this.pendingImage,
    this.isNewRegistration = false,
  });

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  static const MethodChannel _billingStatusChannel = MethodChannel(
    'com.hirehub.app/subscription_status',
  );
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  bool _storeAvailable = true;
  bool _isPurchasing = false;
  String? _storeNotice;
  Map<String, dynamic>? _newRegistrationSubscriptionData;

  static const String _proProductId = 'pro_worker_monthly';
  static const String _backwardsCompatibleId =
      'com-hiro-app-pro-worker-monthly';

  static const Set<String> _allowedSubscriptionIds = {
    _proProductId,
    _backwardsCompatibleId,
  };

  ProductDetails? get _selectedProduct {
    for (final product in _products) {
      if (product.id == _proProductId) return product;
    }
    for (final product in _products) {
      if (product.id == _backwardsCompatibleId) return product;
    }
    return _products.isNotEmpty ? _products.first : null;
  }

  String get _monthlyPriceLabel => _selectedProduct?.price ?? '100 ₪';

  static const List<Map<String, dynamic>> _proCapabilities = [
    {
      'icon': Icons.dashboard_customize_rounded,
      'title': 'דאשבורד מקצועי',
      'subtitle': 'תמונת מצב מלאה על פניות, הכנסות וביצועים במקום אחד.',
    },
    {
      'icon': Icons.event_available_rounded,
      'title': 'מערכת הזמנות חכמה',
      'subtitle': 'ניהול בקשות עבודה, אישור/דחייה ותיעדוף יומי אוטומטי.',
    },
    {
      'icon': Icons.manage_accounts_rounded,
      'title': 'ניהול לידים ולקוחות',
      'subtitle': 'מעקב אחרי כל ליד מהפנייה הראשונה ועד סגירת העבודה.',
    },
    {
      'icon': Icons.analytics_rounded,
      'title': 'ניתוח נתונים מתקדם',
      'subtitle': 'דוחות על שיעור סגירה, זמני תגובה ומקורות פניות.',
    },
    {
      'icon': Icons.calendar_month_rounded,
      'title': 'יומן עבודה מובנה',
      'subtitle': 'תכנון משימות ותיאום תורים ללא כפילויות.',
    },
    {
      'icon': Icons.notifications_active_rounded,
      'title': 'התראות בזמן אמת',
      'subtitle': 'עדכונים מיידיים על פניות חדשות, הודעות ושינויים בהזמנות.',
    },
    {
      'icon': Icons.forum_rounded,
      'title': 'הודעות וצ׳אט עם לקוחות',
      'subtitle': 'תקשורת מהירה מתוך האפליקציה לסגירת עבודות מהר יותר.',
    },
    {
      'icon': Icons.workspace_premium_rounded,
      'title': 'חשיפה ותדמית Pro',
      'subtitle': 'הבלטה בתוצאות החיפוש ותג מקצוען שמחזק אמון.',
    },
    {
      'icon': Icons.support_agent_rounded,
      'title': 'תמיכת VIP',
      'subtitle': 'עדיפות בפניות תמיכה וליווי אישי לעסקים פעילים.',
    },
  ];

  @override
  void initState() {
    super.initState();
    final Stream<List<PurchaseDetails>> purchaseUpdated =
        _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      (purchaseDetailsList) => _listenToPurchaseUpdated(purchaseDetailsList),
      onDone: () => _subscription.cancel(),
      onError: (error) => debugPrint("Purchase Stream Error: $error"),
    );
    _initStoreInfo();
    _syncSubscriptionStateFromGooglePlay();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _initStoreInfo() async {
    setState(() => _isLoading = true);
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) {
      setState(() {
        _storeAvailable = false;
        _storeNotice = 'חנות הרכישות אינה זמינה כרגע במכשיר זה.';
        _isLoading = false;
      });
      return;
    }

    const Set<String> kIds = <String>{_proProductId, _backwardsCompatibleId};
    final ProductDetailsResponse response = await _inAppPurchase
        .queryProductDetails(kIds);

    final bool hasMatchingProduct = response.productDetails.any(
      (p) => _allowedSubscriptionIds.contains(p.id),
    );

    setState(() {
      _products = response.productDetails;
      _storeAvailable = hasMatchingProduct;
      if (response.notFoundIDs.isNotEmpty) {
        _storeNotice = null;
      } else if (!hasMatchingProduct) {
        _storeNotice = 'לא נמצאה חבילת Pro זמינה לרכישה כרגע עבור חשבון זה.';
      } else {
        _storeNotice = null;
      }
      _isLoading = false;
    });
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.error) {
        if (mounted) setState(() => _isPurchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("הרכישה נכשלה: ${purchaseDetails.error?.message}"),
          ),
        );
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        if (mounted) setState(() => _isPurchasing = false);

        if (!_allowedSubscriptionIds.contains(purchaseDetails.productID)) {
          debugPrint('Ignoring non-Pro purchase: ${purchaseDetails.productID}');
        } else if (_isPurchaseDataInvalid(purchaseDetails)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('אימות הרכישה נכשל. נסה שוב או בצע שחזור רכישה.'),
              ),
            );
          }
        } else {
          _completeSubscription(purchaseDetails: purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _isPurchasing = false);
        _syncSubscriptionStateFromGooglePlay();
      }
      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  Future<void> _syncSubscriptionStateFromGooglePlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final dynamic response = await _billingStatusChannel.invokeMethod(
        'getSubscriptionState',
        {'productIds': _allowedSubscriptionIds.toList()},
      );

      if (response is! Map) return;

      final Map<String, dynamic> result = Map<String, dynamic>.from(response);
      final status = (result['status'] ?? '').toString().toLowerCase();

      final firestore = FirebaseFirestore.instance;
      if (status == 'active_renewing') {
        await firestore.collection('users').doc(user.uid).set({
          'isSubscribed': true,
          'subscriptionStatus': 'active',
          'subscriptionCanceled': false,
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (status == 'active_canceled') {
        await firestore.collection('users').doc(user.uid).set({
          'isSubscribed': true,
          'subscriptionStatus': 'inactive',
          'subscriptionCanceled': true,
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (status == 'inactive') {
        await firestore.collection('users').doc(user.uid).set({
          'isSubscribed': false,
          'subscriptionStatus': 'inactive',
          'subscriptionCanceled': true,
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on PlatformException catch (e) {
      debugPrint('Google Play subscription status sync failed: ${e.message}');
    } catch (e) {
      debugPrint('Google Play subscription status sync failed: $e');
    }
  }

  bool _isPurchaseDataInvalid(PurchaseDetails details) {
    final token = details.verificationData.serverVerificationData.trim();
    return token.isEmpty;
  }

  Future<void> _completeSubscription({
    required PurchaseDetails purchaseDetails,
  }) async {
    if (widget.isNewRegistration) {
      final now = DateTime.now();
      _newRegistrationSubscriptionData = {
        'isSubscribed': true,
        'subscriptionStatus': 'active',
        'subscriptionCanceled': false,
        'subscriptionDate': now.toIso8601String(),
        'subscriptionExpiresAt': now
            .add(const Duration(days: 30))
            .toIso8601String(),
        'subscriptionProductId': purchaseDetails.productID,
        'subscriptionPlatform': purchaseDetails.verificationData.source,
        'subscriptionPurchaseId': purchaseDetails.purchaseID,
        'subscriptionTransactionDate': purchaseDetails.transactionDate,
      };
      await _savePurchaseMetadata(purchaseDetails);
      _showSuccessDialog(isNewReg: true);
    } else {
      setState(() => _isLoading = true);
      bool success = await _finalizeWorkerUpgrade(purchaseDetails);
      setState(() => _isLoading = false);
      if (success) {
        _showSuccessDialog(isNewReg: false);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הרכישה זוהתה אך ההפעלה נכשלה. נסה שוב.'),
          ),
        );
      }
    }
  }

  Future<bool> _finalizeWorkerUpgrade(PurchaseDetails purchaseDetails) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      // Fetch existing user data from unified 'users' collection
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> userData = userDoc.exists
          ? (userDoc.data() ?? {})
          : {};

      userData.addAll({
        'role': 'worker',
        'isSubscribed': true,
        'subscriptionStatus': 'active',
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        'subscriptionCanceled': false,
        'subscriptionProductId': purchaseDetails.productID,
        'subscriptionPlatform': purchaseDetails.verificationData.source,
        'subscriptionPurchaseId': purchaseDetails.purchaseID,
        'subscriptionTransactionDate': purchaseDetails.transactionDate,
        'subscriptionDate': Timestamp.fromDate(now),
        'subscriptionExpiresAt': Timestamp.fromDate(
          now.add(const Duration(days: 30)),
        ),
      });

      if (widget.pendingUserData != null) {
        userData.addAll(widget.pendingUserData!);
      }

      if (widget.pendingImage != null) {
        final storageRef = FirebaseStorage.instance.ref().child(
          'profile_pictures/${user.uid}.jpg',
        );
        await storageRef.putFile(widget.pendingImage!);
        userData['profileImageUrl'] = await storageRef.getDownloadURL();
      }

      // Update the same document with new role and subscription status
      await firestore
          .collection('users')
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));

      await _savePurchaseMetadata(purchaseDetails);
      return true;
    } catch (e) {
      debugPrint("Upgrade Error: $e");
      return false;
    }
  }

  Future<void> _savePurchaseMetadata(PurchaseDetails purchaseDetails) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final firestore = FirebaseFirestore.instance;
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('subscriptionPayments')
        .add({
          'productId': purchaseDetails.productID,
          'status': purchaseDetails.status.name,
          'purchaseId': purchaseDetails.purchaseID,
          'transactionDate': purchaseDetails.transactionDate,
          'verificationSource': purchaseDetails.verificationData.source,
          'verificationToken':
              purchaseDetails.verificationData.serverVerificationData,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _buySubscription() async {
    if (!_storeAvailable || _isPurchasing) return;
    final product = _selectedProduct;
    if (product == null) {
      setState(() {
        _storeNotice = 'לא נמצאה חבילת Pro זמינה לרכישה כרגע.';
      });
      return;
    }

    setState(() => _isPurchasing = true);
    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה בהתחלת רכישה: $e')));
      }
    }
  }

  Future<void> _restoreSubscription() async {
    try {
      setState(() => _isPurchasing = true);
      await _inAppPurchase.restorePurchases();
      await _syncSubscriptionStateFromGooglePlay();
      if (mounted) {
        setState(() => _isPurchasing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שחזור רכישות הופעל. בודקים זכאות...')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('שגיאה בשחזור רכישות: $e')));
      }
    }
  }

  void _showSuccessDialog({required bool isNewReg}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'מזל טוב!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'הפכת לעובד Pro רשום בהצלחה! כעת תוכל ליהנות מכל היתרונות.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                if (isNewReg) {
                  final pendingData = <String, dynamic>{
                    ...?widget.pendingUserData,
                    ...?_newRegistrationSubscriptionData,
                  };
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SignUpPage(
                        pendingWorkerData: pendingData,
                        pendingWorkerImage: widget.pendingImage,
                        startAtStep: 1,
                      ),
                    ),
                    (route) => false,
                  );
                } else {
                  Navigator.pop(context); // Go back from subscription page
                }
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('המשך'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8FF),
        appBar: AppBar(
          title: const Text(
            'מנוי Pro',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'רענן',
              onPressed: _isLoading ? null : _initStoreInfo,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomActionBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderHero(),
                      const SizedBox(height: 14),
                      _buildQuickValueChips(),
                      const SizedBox(height: 24),
                      const Text(
                        'שדרג את החשבון שלך',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'קבל יותר עבודות ולידים עם מנוי המקצוענים שלנו. הצטרף לקהילת המומחים המובילה!',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      _buildCard(),
                      const SizedBox(height: 28),
                      if (_storeNotice != null) ...[
                        _buildStoreNotice(_storeNotice!),
                        const SizedBox(height: 22),
                      ],
                      _buildHowItWorks(),
                      const SizedBox(height: 24),
                      _buildProCapabilitiesSection(),
                      const SizedBox(height: 24),
                      _buildGrowthStats(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: (!_storeAvailable || _isPurchasing)
                  ? null
                  : () {
                      _buySubscription();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isPurchasing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'הצטרפות ל-Pro · $_monthlyPriceLabel',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isPurchasing ? null : _restoreSubscription,
              child: const Text('כבר רכשת? שחזור רכישה'),
            ),
            const Text(
              'החיוב חודשי וניתן לבטל בכל עת דרך חנות האפליקציות.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B4FC2), Color(0xFF1E88E5), Color(0xFF48B3FF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'הירו פרו לעסקים שרוצים לגדול',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Text(
            'המסלול שמעניק לך כלים מקצועיים לניהול עבודה, לקוחות והכנסות במקום אחד.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickValueChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: const [
        _ChipLabel(text: 'Dashboard מתקדם'),
        _ChipLabel(text: 'מערכת הזמנות'),
        _ChipLabel(text: 'ניהול לידים'),
        _ChipLabel(text: 'דוחות ביצועים'),
      ],
    );
  }

  Widget _buildStoreNotice(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD08A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF734800),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'איך זה עובד?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF10336F),
            ),
          ),
          SizedBox(height: 10),
          _FlowLine(
            title: 'נרשמים למסלול Pro',
            subtitle: 'הפעלה מהירה מתוך האפליקציה.',
          ),
          _FlowLine(
            title: 'מקבלים את כל הכלים',
            subtitle: 'דאשבורד, הזמנות, לידים ותקשורת עם לקוחות.',
          ),
          _FlowLine(
            title: 'מנהלים וצומחים',
            subtitle: 'יותר חשיפה, יותר פניות ויותר עבודות סגורות.',
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.4),
                blurRadius: 25,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text(
                'מסלול PRO WORKER',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _products.isNotEmpty
                        ? _products.first.price.split(' ')[0]
                        : '100',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '₪ / חודש',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 48, thickness: 1),
              _buildFeatureRow('קבלת פניות (לידים) ללא הגבלה'),
              _buildFeatureRow('תג "מקצוען" מוצמד לפרופיל'),
              _buildFeatureRow('גישה לכלי ניהול מתקדמים'),
              _buildFeatureRow('תמיכה טכנית מועדפת (VIP)'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProCapabilitiesSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EEFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'מה מקבלים במסלול Pro?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F2E67),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'כל היכולות שעוזרות לך לנהל עסק מקצועי ולסגור יותר עבודות.',
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.45),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 520;
              final double itemWidth = isNarrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _proCapabilities
                    .map(
                      (capability) => SizedBox(
                        width: itemWidth,
                        child: _buildCapabilityTile(
                          icon: capability['icon'] as IconData,
                          title: capability['title'] as String,
                          subtitle: capability['subtitle'] as String,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilityTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FAFF), Color(0xFFEEF5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF1E88E5), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D2C61),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthStats() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 20,
        runSpacing: 10,
        children: [
          _StatChip(title: '24/7', subtitle: 'גישה למערכת'),
          _StatChip(title: '1', subtitle: 'מרכז ניהול אחד'),
          _StatChip(title: 'Pro', subtitle: 'חשיפה מוגברת'),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StatChip({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _FlowLine extends StatelessWidget {
  final String title;
  final String subtitle;

  const _FlowLine({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle, color: Color(0xFF1E88E5), size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10336F),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final String text;

  const _ChipLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E5FF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0D3F91),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
