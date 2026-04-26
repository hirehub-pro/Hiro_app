import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:untitled1/sign_up.dart';
import 'package:untitled1/services/subscription_access_service.dart';

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

class _SubscriptionPageState extends State<SubscriptionPage>
    with TickerProviderStateMixin {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  bool _storeAvailable = true;
  bool _isPurchasing = false;
  String? _storeNotice;
  Map<String, dynamic>? _newRegistrationSubscriptionData;

  AnimationController? _introController;
  AnimationController? _backgroundController;

  AnimationController get _introAnimationController {
    final controller = _introController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _introController = created;
    return created;
  }

  AnimationController get _backgroundAnimationController {
    final controller = _backgroundController;
    if (controller != null) return controller;
    final created = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _backgroundController = created;
    return created;
  }

  void _ensureAnimationControllers() {
    _introAnimationController;
    _backgroundAnimationController;
  }

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

  String get _monthlyPriceLabel => _selectedProduct?.price ?? '99.90 ₪';

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
    _ensureAnimationControllers();
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
    _introController?.dispose();
    _backgroundController?.dispose();
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
        if (_isAlreadyOwnedError(purchaseDetails.error)) {
          _handleSubscriptionOwnedByAnotherAccount();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("הרכישה נכשלה: ${purchaseDetails.error?.message}"),
            ),
          );
        }
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
    await _syncSubscriptionStateFromGooglePlayWithClaim(
      allowClaimUnownedPurchase: false,
    );
  }

  Future<void> _syncSubscriptionStateFromGooglePlayWithClaim({
    required bool allowClaimUnownedPurchase,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await SubscriptionAccessService.syncCurrentUserWithGooglePlay(
        allowClaimUnownedPurchase: allowClaimUnownedPurchase,
      );
      await _refreshLinkedAccountNotice();
    } on PlatformException catch (e) {
      debugPrint('Google Play subscription status sync failed: ${e.message}');
    } catch (e) {
      debugPrint('Google Play subscription status sync failed: $e');
    }
  }

  Future<void> _refreshLinkedAccountNotice() async {
    final linkedElsewhere =
        await SubscriptionAccessService.isCurrentGooglePlaySubscriptionLinkedToAnotherAccount();
    if (!mounted) return;

    setState(() {
      if (linkedElsewhere) {
        _storeNotice =
            'חשבון Google Play הזה כבר מחזיק מנוי Hiro שמקושר למספר טלפון אחר. המנוי זמין רק בחשבון המקורי.';
      } else if (_storeNotice != null &&
          _storeNotice!.contains('Google Play') &&
          _storeNotice!.contains('Hiro')) {
        _storeNotice = null;
      }
    });
  }

  bool _isAlreadyOwnedError(IAPError? error) {
    if (error == null) return false;
    final code = error.code.toLowerCase();
    final message = (error.message ?? '').toLowerCase();
    final details = (error.details ?? '').toString().toLowerCase();
    final combined = '$code $message $details';
    return combined.contains('already owned') ||
        combined.contains('item already owned') ||
        combined.contains('alreadyown') ||
        combined.contains('duplicate');
  }

  Future<void> _handleSubscriptionOwnedByAnotherAccount() async {
    await _refreshLinkedAccountNotice();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'חשבון Google Play הזה כבר מחזיק מנוי Hiro שמקושר לחשבון אחר.',
        ),
      ),
    );
  }

  bool _isPurchaseDataInvalid(PurchaseDetails details) {
    final token = details.verificationData.serverVerificationData.trim();
    return token.isEmpty;
  }

  Future<void> _completeSubscription({
    required PurchaseDetails purchaseDetails,
  }) async {
    final accountToken =
        await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();
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
        'subscriptionPurchaseToken':
            purchaseDetails.verificationData.serverVerificationData,
        'subscriptionTransactionDate': purchaseDetails.transactionDate,
        if (accountToken != null) 'subscriptionAccountToken': accountToken,
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
      final accountToken =
          await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();

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
        'subscriptionPurchaseToken':
            purchaseDetails.verificationData.serverVerificationData,
        'subscriptionTransactionDate': purchaseDetails.transactionDate,
        'subscriptionDate': Timestamp.fromDate(now),
        'subscriptionExpiresAt': Timestamp.fromDate(
          now.add(const Duration(days: 30)),
        ),
        if (accountToken != null) 'subscriptionAccountToken': accountToken,
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
    final accountToken =
        await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();

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
          if (accountToken != null) 'subscriptionAccountToken': accountToken,
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
      final purchaseParam = await _buildPurchaseParam(product);
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        final errorText = e.toString().toLowerCase();
        if (errorText.contains('already owned') ||
            errorText.contains('item already owned') ||
            errorText.contains('duplicate')) {
          await _handleSubscriptionOwnedByAnotherAccount();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('שגיאה בהתחלת רכישה: $e')));
        }
      }
    }
  }

  Future<PurchaseParam> _buildPurchaseParam(ProductDetails product) async {
    final user = FirebaseAuth.instance.currentUser;
    final accountToken = user == null
        ? null
        : await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: accountToken,
      );
    }

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppStorePurchaseParam(
        productDetails: product,
        applicationUserName: accountToken,
      );
    }

    return PurchaseParam(
      productDetails: product,
      applicationUserName: accountToken,
    );
  }

  Future<void> _restoreSubscription() async {
    try {
      setState(() => _isPurchasing = true);
      await _inAppPurchase.restorePurchases();
      await _syncSubscriptionStateFromGooglePlayWithClaim(
        allowClaimUnownedPurchase: true,
      );
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
    _ensureAnimationControllers();
    final backgroundController = _backgroundAnimationController;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFF),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 420 ? 20.0 : 28.0;
            final verticalPadding = 28.0;

            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: backgroundController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _SubscriptionBackgroundPainter(
                          backgroundController.value,
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(
                          0,
                          constraints.maxHeight -
                              MediaQuery.paddingOf(context).vertical,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: verticalPadding,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: _isLoading
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        SizedBox(height: 80),
                                        CircularProgressIndicator(),
                                        SizedBox(height: 80),
                                      ],
                                    ),
                                  )
                                : _buildContentColumn(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomActionBar(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAnimatedEntry(delay: 0.0, child: _buildHeaderPill()),
        const SizedBox(height: 28),
        _buildAnimatedEntry(delay: 0.08, child: _buildMainHeading()),
        const SizedBox(height: 32),
        _buildAnimatedEntry(delay: 0.14, child: _buildPricingCard()),
        const SizedBox(height: 28),
        if (_storeNotice != null) ...[
          _buildAnimatedEntry(
            delay: 0.20,
            child: _buildStoreNotice(_storeNotice!),
          ),
          const SizedBox(height: 22),
        ],
        _buildAnimatedEntry(delay: 0.26, child: _buildProCapabilitiesSection()),
        const SizedBox(height: 28),
        _buildAnimatedEntry(delay: 0.32, child: _buildHowItWorks()),
        const SizedBox(height: 28),
        _buildAnimatedEntry(delay: 0.38, child: _buildGrowthStats()),
        const SizedBox(height: 140),
      ],
    );
  }

  Widget _buildAnimatedEntry({
    required Widget child,
    double delay = 0,
    Offset begin = const Offset(0, 0.08),
  }) {
    final start = delay.clamp(0.0, 0.9).toDouble();
    final animation = CurvedAnimation(
      parent: _introAnimationController,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: begin,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildHeaderPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF1976D2),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            'מסלול Pro'.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1976D2),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'שדרג לעובד Pro',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF070B18),
            fontSize: 42,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Text(
            'קבל יותר עבודות ולידים עם מנוי המקצוענים שלנו. כלים מקצועיים לניהול עסק ותקשורת עם לקוחות במקום אחד.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 18,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPricingCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 48,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'מסלול PRO WORKER',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _monthlyPriceLabel.split(' ')[0],
                  style: const TextStyle(
                    color: Color(0xFF070B18),
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '₪ / חודש',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(color: Color(0xFFE5E7EB), height: 1),
          const SizedBox(height: 32),
          _buildFeatureRow('פניות ולידים ללא הגבלה'),
          _buildFeatureRow('תג Pro בולט בפרופיל שלך'),
          _buildFeatureRow('כלים לניהול עבודות ולקוחות'),
          _buildFeatureRow('תמיכה מועדפת לעובדי Pro'),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (!_storeAvailable || _isPurchasing)
                    ? null
                    : _buySubscription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  disabledBackgroundColor: const Color(0xFF8ABCEA),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isPurchasing
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : FittedBox(
                          key: ValueKey('purchase'),
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.shopping_cart_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'הצטרפות ל-Pro · $_monthlyPriceLabel',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'החיוב חודשי וניתן לבטל בכל עת דרך חנות האפליקציות.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreNotice(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD08A), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF8A5A00), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF734800),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'איך זה עובד?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F2E67),
            ),
          ),
          SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFF1976D2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.3,
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

class _SubscriptionBackgroundPainter extends CustomPainter {
  const _SubscriptionBackgroundPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final eased = Curves.easeInOut.transform(progress);
    final begin = Alignment.lerp(Alignment.topLeft, Alignment.topRight, eased)!;
    final end = Alignment.lerp(
      Alignment.bottomRight,
      Alignment.bottomLeft,
      eased,
    )!;

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: const [
          Color(0xFFFDFEFF),
          Color(0xFFEAF5FF),
          Color(0xFFF7FBFF),
          Color(0xFFE3F8FF),
        ],
        stops: const [0, 0.38, 0.68, 1],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final width = size.width;
    final height = size.height;
    final phase = progress * math.pi * 2;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(120, size.shortestSide * 0.18)
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.055)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 54);
    final path = Path()
      ..moveTo(-width * 0.2, height * (0.22 + math.sin(phase) * 0.03))
      ..cubicTo(
        width * 0.24,
        height * (0.02 + math.cos(phase) * 0.04),
        width * 0.58,
        height * (0.54 + math.sin(phase) * 0.03),
        width * 1.2,
        height * (0.25 + math.cos(phase) * 0.03),
      );
    canvas.drawPath(path, highlightPaint);

    final lowerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(90, size.shortestSide * 0.13)
      ..color = const Color(0xFF62D6E8).withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 46);
    final lowerPath = Path()
      ..moveTo(width * 0.36, height * 1.12)
      ..cubicTo(
        width * (0.46 + math.sin(phase) * 0.04),
        height * 0.78,
        width * (0.72 + math.cos(phase) * 0.03),
        height * 0.95,
        width * 1.16,
        height * (0.65 + math.sin(phase) * 0.04),
      );
    canvas.drawPath(lowerPath, lowerPaint);
  }

  @override
  bool shouldRepaint(covariant _SubscriptionBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
