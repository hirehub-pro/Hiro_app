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
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:untitled1/sign_up.dart';
import 'package:untitled1/main.dart';
import 'package:untitled1/services/language_provider.dart';
import 'package:untitled1/services/subscription_access_service.dart';
import 'package:untitled1/utils/constants.dart';

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

  static const String _androidProProductId = 'pro_worker_monthly';
  static const String _androidBackwardsCompatibleId =
      'com-hiro-app-pro-worker-monthly';
  static const String _iosProProductId = 'HIRO_SUBSCRIPTION';
  static const String _appleStandardEulaUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  Set<String> get _storeProductIds {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return const {_iosProProductId};
    }

    return const {_androidProProductId, _androidBackwardsCompatibleId};
  }

  Set<String> get _allowedSubscriptionIds => _storeProductIds;

  ProductDetails? get _selectedProduct {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      for (final product in _products) {
        if (product.id == _iosProProductId) return product;
      }
    }

    for (final product in _products) {
      if (product.id == _androidProProductId) return product;
    }
    for (final product in _products) {
      if (product.id == _androidBackwardsCompatibleId) return product;
    }
    return _products.isNotEmpty ? _products.first : null;
  }

  String get _monthlyPriceLabel => _selectedProduct?.price ?? '99.90 ₪';

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

    final ProductDetailsResponse response = await _inAppPurchase
        .queryProductDetails(_storeProductIds);

    final bool hasMatchingProduct = response.productDetails.any(
      (p) => _allowedSubscriptionIds.contains(p.id),
    );

    setState(() {
      _products = response.productDetails;
      _storeAvailable = hasMatchingProduct;
      if (!hasMatchingProduct) {
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
    final message = error.message.toLowerCase();
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
        'subscriptionAccountToken': accountToken,
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
        'subscriptionAccountToken': accountToken,
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
          'subscriptionAccountToken': accountToken,
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
      final user = FirebaseAuth.instance.currentUser;
      final accountToken = user == null
          ? null
          : await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();
      await _inAppPurchase.restorePurchases(applicationUserName: accountToken);
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

  Future<void> _confirmSkipForLater() async {
    final strings = _pageStrings;
    final shouldSkip = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) => Directionality(
        textDirection: _isRtlLocale ? TextDirection.rtl : TextDirection.ltr,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB91C1C),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings['skip_dialog_title']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  strings['skip_dialog_subtitle']!,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 14),
                _buildSkipLossRow(strings['skip_loss_1']!),
                const SizedBox(height: 8),
                _buildSkipLossRow(strings['skip_loss_2']!),
                const SizedBox(height: 8),
                _buildSkipLossRow(strings['skip_loss_3']!),
                const SizedBox(height: 14),
                Text(
                  strings['skip_dialog_note']!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(strings['skip_dialog_stay']!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(strings['skip_dialog_confirm']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldSkip != true || !mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MyHomePage()),
      (route) => false,
    );
  }

  Widget _buildSkipLossRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: Color(0xFF1976D2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Color(0xFF1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureAnimationControllers();
    final strings = _strings;
    final backgroundController = _backgroundAnimationController;

    return Directionality(
      textDirection: _isRtlLocale ? TextDirection.rtl : TextDirection.ltr,
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
                                      children: [
                                        SizedBox(height: 80),
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 14),
                                        Text(strings['loading']!),
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
        const SizedBox(height: 22),
        _buildAnimatedEntry(delay: 0.44, child: _buildSubscriptionCompliance()),
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
    final strings = _pageStrings;
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
            strings['pill']!.toUpperCase(),
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
    final strings = _pageStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          strings['title']!,
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
          child: Text(
            strings['subtitle']!,
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
    final strings = _pageStrings;
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
          Text(
            strings['plan']!,
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
                Text(
                  strings['per_month']!,
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
          _buildFeatureRow(strings['feature_1']!),
          _buildFeatureRow(strings['feature_2']!),
          _buildFeatureRow(strings['feature_3']!),
          _buildFeatureRow(strings['feature_4']!),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    final strings = _pageStrings;
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
                                '${strings['cta']} · $_monthlyPriceLabel',
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
            Text(
              strings['billing']!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings['auto_renew_note']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              strings['subscription_title_note']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 6,
              children: [
                _buildBottomLegalLink(
                  label: strings['privacy_link']!,
                  url: AppConstants.privacyPolicyUrl,
                ),
                _buildBottomLegalLink(
                  label: strings['terms_link']!,
                  url: _appleStandardEulaUrl,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _isPurchasing ? null : _restoreSubscription,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1976D2),
              ),
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: Text(
                strings['restore']!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextButton(
              onPressed: _isPurchasing ? null : _confirmSkipForLater,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1F2937),
              ),
              child: Text(
                strings['skip']!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLegalLink({required String label, required String url}) {
    return InkWell(
      onTap: () => _openLink(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D4ED8),
            decoration: TextDecoration.underline,
          ),
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
    final strings = _pageStrings;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings['how_title']!,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F2E67),
            ),
          ),
          SizedBox(height: 16),
          _FlowLine(
            title: strings['flow_1_title']!,
            subtitle: strings['flow_1_subtitle']!,
          ),
          _FlowLine(
            title: strings['flow_2_title']!,
            subtitle: strings['flow_2_subtitle']!,
          ),
          _FlowLine(
            title: strings['flow_3_title']!,
            subtitle: strings['flow_3_subtitle']!,
          ),
        ],
      ),
    );
  }

  Widget _buildProCapabilitiesSection() {
    final strings = _pageStrings;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EEFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings['cap_title']!,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F2E67),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings['cap_subtitle']!,
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
                children: _capabilities
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
              color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
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

  Widget _buildSubscriptionCompliance() {
    final strings = _strings;
    final title = _selectedProduct?.title.trim().isNotEmpty == true
        ? _selectedProduct!.title
        : strings['pro_plan_title']!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            const Color(0xFFF5F9FF).withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E7FF), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  size: 18,
                  color: Color(0xFF1257A8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings['subscription_details']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailRow(
            icon: Icons.subscriptions_outlined,
            label: strings['subscription_title']!,
            value: title,
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            icon: Icons.schedule_outlined,
            label: strings['subscription_length']!,
            value: strings['subscription_monthly']!,
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            icon: Icons.payments_outlined,
            label: strings['subscription_price']!,
            value: _monthlyPriceLabel,
            highlight: true,
          ),
          const SizedBox(height: 14),
          _buildLegalActionButton(
            label: strings['privacy_policy']!,
            onTap: () => _openLink(AppConstants.privacyPolicyUrl),
          ),
          const SizedBox(height: 8),
          _buildLegalActionButton(
            label: strings['terms_of_use']!,
            onTap: () => _openLink(_appleStandardEulaUrl),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFE8F2FF)
            : const Color(0xFFF8FAFC).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFFBFDBFE) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: highlight ? 15 : 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalActionButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF2563EB),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_strings['open_link_error']!)));
    }
  }

  String get _localeCode =>
      Provider.of<LanguageProvider>(context, listen: false).locale.languageCode;

  bool get _isRtlLocale => _localeCode == 'he' || _localeCode == 'ar';

  Map<String, String> get _strings {
    switch (_localeCode) {
      case 'ar':
        return {
          'loading': 'جارٍ تحميل الاشتراك...',
          'subscription_details': 'تفاصيل الاشتراك',
          'subscription_title': 'اسم الاشتراك',
          'subscription_length': 'مدة الاشتراك',
          'subscription_price': 'السعر',
          'subscription_monthly': 'شهري (يتجدد تلقائياً)',
          'privacy_policy': 'سياسة الخصوصية',
          'terms_of_use': 'شروط الاستخدام',
          'open_link_error': 'تعذر فتح الرابط حالياً.',
          'pro_plan_title': 'باقة PRO WORKER',
        };
      case 'ru':
        return {
          'loading': 'Загрузка подписки...',
          'subscription_details': 'Детали подписки',
          'subscription_title': 'Название подписки',
          'subscription_length': 'Срок подписки',
          'subscription_price': 'Цена',
          'subscription_monthly': 'Ежемесячно (автопродление)',
          'privacy_policy': 'Политика конфиденциальности',
          'terms_of_use': 'Условия использования',
          'open_link_error': 'Не удалось открыть ссылку.',
          'pro_plan_title': 'ТАРИФ PRO WORKER',
        };
      case 'am':
        return {
          'loading': 'ምዝገባ በመጫን ላይ...',
          'subscription_details': 'የምዝገባ ዝርዝሮች',
          'subscription_title': 'የምዝገባ ስም',
          'subscription_length': 'የምዝገባ ጊዜ',
          'subscription_price': 'ዋጋ',
          'subscription_monthly': 'ወርሃዊ (በራስ-ሰር የሚታደስ)',
          'privacy_policy': 'የግላዊነት ፖሊሲ',
          'terms_of_use': 'የአጠቃቀም ውል',
          'open_link_error': 'ሊንኩን መክፈት አልተቻለም።',
          'pro_plan_title': 'PRO WORKER ፓኬጅ',
        };
      case 'en':
        return {
          'loading': 'Loading subscription...',
          'subscription_details': 'Subscription details',
          'subscription_title': 'Subscription title',
          'subscription_length': 'Subscription length',
          'subscription_price': 'Price',
          'subscription_monthly': 'Monthly (auto-renewable)',
          'privacy_policy': 'Privacy Policy',
          'terms_of_use': 'Terms of Use',
          'open_link_error': 'Could not open the link right now.',
          'pro_plan_title': 'PRO WORKER PLAN',
        };
      default:
        return {
          'loading': 'טוען מנוי...',
          'subscription_details': 'פרטי המנוי',
          'subscription_title': 'שם המנוי',
          'subscription_length': 'אורך המנוי',
          'subscription_price': 'מחיר',
          'subscription_monthly': 'חודשי (מתחדש אוטומטית)',
          'privacy_policy': 'מדיניות פרטיות',
          'terms_of_use': 'תנאי שימוש',
          'open_link_error': 'לא ניתן לפתוח את הקישור כרגע.',
          'pro_plan_title': 'מסלול PRO WORKER',
        };
    }
  }

  Map<String, String> get _pageStrings {
    switch (_localeCode) {
      case 'ar':
        return {
          'pill': 'باقة Pro',
          'title': 'الترقية إلى عامل Pro',
          'subtitle':
              'احصل على أعمال وفرص أكثر مع اشتراك المحترفين. أدوات متقدمة لإدارة العمل والتواصل مع العملاء في مكان واحد.',
          'plan': 'باقة PRO WORKER',
          'per_month': '₪ / شهرياً',
          'feature_1': 'طلبات وفرص عمل غير محدودة',
          'feature_2': 'شارة Pro مميزة في ملفك',
          'feature_3': 'أدوات لإدارة الأعمال والعملاء',
          'feature_4': 'دعم مفضل لمشتركي Pro',
          'cta': 'الانضمام إلى Pro',
          'billing': 'يتم الدفع شهرياً ويمكن الإلغاء في أي وقت عبر المتجر.',
          'auto_renew_note': 'اشتراك يتجدد تلقائياً حتى يتم الإلغاء.',
          'subscription_title_note': 'اسم الاشتراك: HIRO_SUBSCRIPTION',
          'privacy_link': 'سياسة الخصوصية',
          'terms_link': 'شروط الاستخدام',
          'restore': 'استعادة الشراء',
          'skip': 'تخطي الآن',
          'skip_dialog_title': 'تخطي الاشتراك الآن؟',
          'skip_dialog_subtitle':
              'يمكنك المتابعة بدون Pro، لكن ستفقد أدوات مهمة تساعدك على الحصول على فرص أكثر.',
          'skip_loss_1': 'سيتم إخفاؤك من نتائج البحث وبدون شارة Pro.',
          'skip_loss_2': 'عدم الوصول الكامل لأدوات إدارة العملاء والطلبات.',
          'skip_loss_3': 'لن تتمكن من إنشاء فواتير داخل التطبيق.',
          'skip_dialog_note': 'يمكنك الاشتراك لاحقاً من صفحة الملف الشخصي.',
          'skip_dialog_stay': 'العودة إلى Pro',
          'skip_dialog_confirm': 'تخطي حالياً',
          'how_title': 'كيف يعمل؟',
          'flow_1_title': 'اشترك في باقة Pro',
          'flow_1_subtitle': 'تفعيل سريع من داخل التطبيق.',
          'flow_2_title': 'احصل على كل الأدوات',
          'flow_2_subtitle': 'لوحة تحكم، حجوزات، فرص وتواصل مع العملاء.',
          'flow_3_title': 'أدر عملك وانمُ',
          'flow_3_subtitle': 'ظهور أكبر وطلبات أكثر وأعمال مغلقة أكثر.',
          'cap_title': 'ماذا تحصل في باقة Pro؟',
          'cap_subtitle': 'كل الإمكانيات التي تساعدك على إدارة عمل احترافي.',
          'cap_1_title': 'لوحة تحكم احترافية',
          'cap_1_sub': 'رؤية كاملة للطلبات والإيرادات والأداء.',
          'cap_2_title': 'نظام حجوزات ذكي',
          'cap_2_sub': 'إدارة الطلبات والموافقة أو الرفض تلقائياً.',
          'cap_3_title': 'إدارة العملاء والفرص',
          'cap_3_sub': 'متابعة كل فرصة من أول تواصل حتى الإغلاق.',
          'cap_4_title': 'تحليلات متقدمة',
          'cap_4_sub': 'تقارير عن نسبة الإغلاق وسرعة الرد.',
        };
      case 'ru':
        return {
          'pill': 'Тариф Pro',
          'title': 'Перейти на Pro для мастера',
          'subtitle':
              'Получайте больше заказов и лидов с подпиской Pro. Профессиональные инструменты для бизнеса и общения с клиентами.',
          'plan': 'ТАРИФ PRO WORKER',
          'per_month': '₪ / месяц',
          'feature_1': 'Неограниченные заявки и лиды',
          'feature_2': 'Заметный значок Pro в профиле',
          'feature_3': 'Инструменты для управления заказами и клиентами',
          'feature_4': 'Приоритетная поддержка Pro',
          'cta': 'Подключить Pro',
          'billing':
              'Списание ежемесячное, отмена доступна в любое время через магазин приложений.',
          'auto_renew_note': 'Подписка продлевается автоматически до отмены.',
          'subscription_title_note': 'Название подписки: HIRO_SUBSCRIPTION',
          'privacy_link': 'Политика конфиденциальности',
          'terms_link': 'Условия использования',
          'restore': 'Восстановить покупку',
          'skip': 'Пропустить сейчас',
          'skip_dialog_title': 'Пропустить подписку сейчас?',
          'skip_dialog_subtitle':
              'Вы можете продолжить без Pro, но потеряете важные инструменты для роста.',
          'skip_loss_1':
              'Ваш профиль будет скрыт из результатов поиска и без значка Pro.',
          'skip_loss_2':
              'Без полного доступа к управлению заявками и клиентами.',
          'skip_loss_3': 'Вы не сможете создавать счета в приложении.',
          'skip_dialog_note': 'Вы сможете подключить Pro позже из профиля.',
          'skip_dialog_stay': 'Вернуться к Pro',
          'skip_dialog_confirm': 'Пропустить сейчас',
          'how_title': 'Как это работает?',
          'flow_1_title': 'Оформите тариф Pro',
          'flow_1_subtitle': 'Быстрая активация прямо в приложении.',
          'flow_2_title': 'Получите все инструменты',
          'flow_2_subtitle':
              'Панель, бронирования, лиды и общение с клиентами.',
          'flow_3_title': 'Управляйте и растите',
          'flow_3_subtitle': 'Больше видимости, заявок и закрытых заказов.',
          'cap_title': 'Что входит в Pro?',
          'cap_subtitle': 'Все возможности для профессионального управления.',
          'cap_1_title': 'Профессиональная панель',
          'cap_1_sub': 'Полная картина по заявкам, доходам и эффективности.',
          'cap_2_title': 'Умные бронирования',
          'cap_2_sub': 'Управление заявками и авто-приоритизация.',
          'cap_3_title': 'Лиды и клиенты',
          'cap_3_sub': 'Отслеживание каждого лида до закрытия.',
          'cap_4_title': 'Продвинутая аналитика',
          'cap_4_sub': 'Отчеты по конверсии и времени ответа.',
        };
      case 'am':
        return {
          'pill': 'Pro ፓኬጅ',
          'title': 'ወደ Pro ሰራተኛ አሻሽል',
          'subtitle':
              'በፕሮ ምዝገባ ተጨማሪ ስራ እና ደንበኛ ጥያቄ ያግኙ። ለንግድዎ አስፈላጊ መሳሪያዎች በአንድ ቦታ።',
          'plan': 'PRO WORKER ፓኬጅ',
          'per_month': '₪ / በወር',
          'feature_1': 'ያልተገደበ ጥያቄ እና ሊድ',
          'feature_2': 'በፕሮፋይልዎ ላይ የPro ምልክት',
          'feature_3': 'ስራ እና ደንበኛ አስተዳደር መሳሪያዎች',
          'feature_4': 'ለPro አባላት ቅድሚያ ድጋፍ',
          'cta': 'ወደ Pro ይቀላቀሉ',
          'billing': 'ክፍያው ወርሃዊ ነው እና በማንኛውም ጊዜ መሰረዝ ይቻላል።',
          'auto_renew_note': 'ምዝገባው እስክትሰርዙ ድረስ በራስ-ሰር ይታደሳል።',
          'subscription_title_note': 'የምዝገባ ስም: HIRO_SUBSCRIPTION',
          'privacy_link': 'የግላዊነት ፖሊሲ',
          'terms_link': 'የአጠቃቀም ውል',
          'restore': 'ግዢን መልስ',
          'skip': 'አሁን ዝለል',
          'skip_dialog_title': 'አሁን ምዝገባውን ትዝለላለህ?',
          'skip_dialog_subtitle':
              'ያለ Pro መቀጠል ይችላሉ፣ ግን ለእድገት ጠቃሚ መሳሪያዎችን ታጣላችሁ።',
          'skip_loss_1': 'ከፍለጋ ውጤቶች ውስጥ ትደበቃላችሁ እና የPro ምልክት አይኖርም።',
          'skip_loss_2': 'የደንበኛ እና የትዕዛዝ አስተዳደር መሳሪያ ሙሉ መዳረሻ አይኖርዎትም።',
          'skip_loss_3': 'በመተግበሪያው ውስጥ ደረሰኞችን መፍጠር አትችሉም።',
          'skip_dialog_note': 'በኋላ ከፕሮፋይል ገጽ Pro መቀላቀል ይችላሉ።',
          'skip_dialog_stay': 'ወደ Pro ተመለስ',
          'skip_dialog_confirm': 'ለአሁን ዝለል',
          'how_title': 'እንዴት ይሰራል?',
          'flow_1_title': 'የPro ፓኬጅ ይመዝገቡ',
          'flow_1_subtitle': 'ፈጣን እንቅስቃሴ ከመተግበሪያው ውስጥ።',
          'flow_2_title': 'ሁሉንም መሳሪያዎች ያግኙ',
          'flow_2_subtitle': 'ዳሽቦርድ፣ ትዕዛዞች፣ ሊዶች እና ግንኙነት።',
          'flow_3_title': 'ያስተዳድሩ እና ያድጉ',
          'flow_3_subtitle': 'ተጨማሪ ታይነት እና ተጨማሪ ስራዎች።',
          'cap_title': 'በPro ምን ያገኛሉ?',
          'cap_subtitle': 'ንግድዎን ለማስተዳደር የሚያስፈልጉ ችሎታዎች።',
          'cap_1_title': 'የባለሙያ ዳሽቦርድ',
          'cap_1_sub': 'ሙሉ እይታ በጥያቄዎች እና ገቢ ላይ።',
          'cap_2_title': 'ብልህ የትዕዛዝ ስርዓት',
          'cap_2_sub': 'ጥያቄዎችን አስተዳድር እና ቅድሚያ አድርግ።',
          'cap_3_title': 'የሊድ እና ደንበኛ አስተዳደር',
          'cap_3_sub': 'ከመጀመሪያ ግንኙነት እስከ መዝጊያ ተከታተል።',
          'cap_4_title': 'የላቀ ትንታኔ',
          'cap_4_sub': 'በመዝጊያ መጠን እና ምላሽ ፍጥነት ሪፖርቶች።',
        };
      case 'en':
        return {
          'pill': 'Pro Plan',
          'title': 'Upgrade to Pro Worker',
          'subtitle':
              'Get more jobs and leads with our professional subscription. Advanced tools for business management and client communication in one place.',
          'plan': 'PRO WORKER PLAN',
          'per_month': '₪ / month',
          'feature_1': 'Unlimited requests and leads',
          'feature_2': 'Highlighted Pro badge on your profile',
          'feature_3': 'Tools to manage jobs and customers',
          'feature_4': 'Priority support for Pro workers',
          'cta': 'Join Pro',
          'billing':
              'Billing is monthly and can be canceled anytime through the app store.',
          'auto_renew_note': 'Auto-renewable subscription until canceled.',
          'subscription_title_note': 'Subscription title: HIRO_SUBSCRIPTION',
          'privacy_link': 'Privacy Policy',
          'terms_link': 'Terms of Use',
          'restore': 'Restore purchase',
          'skip': 'Skip for now',
          'skip_dialog_title': 'Skip subscription for now?',
          'skip_dialog_subtitle':
              'You can continue without Pro, but you will miss tools that help you win more jobs.',
          'skip_loss_1':
              'You will be hidden from search results and without a Pro badge.',
          'skip_loss_2': 'No full access to lead and booking management tools.',
          'skip_loss_3': 'You will not be able to create invoices in the app.',
          'skip_dialog_note': 'You can subscribe later from your profile page.',
          'skip_dialog_stay': 'Back to Pro',
          'skip_dialog_confirm': 'Skip for now',
          'how_title': 'How it works?',
          'flow_1_title': 'Subscribe to Pro',
          'flow_1_subtitle': 'Fast activation from inside the app.',
          'flow_2_title': 'Get all tools',
          'flow_2_subtitle':
              'Dashboard, bookings, leads, and client communication.',
          'flow_3_title': 'Manage and grow',
          'flow_3_subtitle': 'More visibility, more leads, more closed jobs.',
          'cap_title': 'What do you get with Pro?',
          'cap_subtitle':
              'All capabilities you need to run a professional business.',
          'cap_1_title': 'Professional dashboard',
          'cap_1_sub':
              'A complete snapshot of requests, revenue, and performance.',
          'cap_2_title': 'Smart booking system',
          'cap_2_sub':
              'Manage requests and auto-prioritize your daily pipeline.',
          'cap_3_title': 'Lead and client management',
          'cap_3_sub': 'Track each lead from first contact to closed job.',
          'cap_4_title': 'Advanced analytics',
          'cap_4_sub': 'Reports on conversion rate and response speed.',
        };
      default:
        return {
          'pill': 'מסלול Pro',
          'title': 'שדרג לעובד Pro',
          'subtitle':
              'קבל יותר עבודות ולידים עם מנוי המקצוענים שלנו. כלים מקצועיים לניהול עסק ותקשורת עם לקוחות במקום אחד.',
          'plan': 'מסלול PRO WORKER',
          'per_month': '₪ / חודש',
          'feature_1': 'פניות ולידים ללא הגבלה',
          'feature_2': 'תג Pro בולט בפרופיל שלך',
          'feature_3': 'כלים לניהול עבודות ולקוחות',
          'feature_4': 'תמיכה מועדפת לעובדי Pro',
          'cta': 'הצטרפות ל-Pro',
          'billing': 'החיוב חודשי וניתן לבטל בכל עת דרך חנות האפליקציות.',
          'auto_renew_note': 'זהו מנוי מתחדש אוטומטית עד לביטול.',
          'subscription_title_note': 'שם המנוי: HIRO_SUBSCRIPTION',
          'privacy_link': 'מדיניות פרטיות',
          'terms_link': 'תנאי שימוש',
          'restore': 'שחזור רכישה',
          'skip': 'דלג בינתיים',
          'skip_dialog_title': 'לדלג על המנוי כרגע?',
          'skip_dialog_subtitle':
              'אפשר להמשיך בלי Pro, אבל תאבד כלים חשובים שיעזרו לך לקבל יותר עבודות.',
          'skip_loss_1': 'הפרופיל שלך יוסתר מתוצאות החיפוש וללא תג Pro בולט.',
          'skip_loss_2': 'ללא גישה מלאה לכלי ניהול לידים, לקוחות והזמנות.',
          'skip_loss_3': 'לא תהיה לך אפשרות ליצור חשבוניות באפליקציה.',
          'skip_dialog_note': 'תוכל להצטרף למנוי בכל שלב מעמוד הפרופיל.',
          'skip_dialog_stay': 'חזרה ל-Pro',
          'skip_dialog_confirm': 'דלג כרגע',
          'how_title': 'איך זה עובד?',
          'flow_1_title': 'נרשמים למסלול Pro',
          'flow_1_subtitle': 'הפעלה מהירה מתוך האפליקציה.',
          'flow_2_title': 'מקבלים את כל הכלים',
          'flow_2_subtitle': 'דאשבורד, הזמנות, לידים ותקשורת עם לקוחות.',
          'flow_3_title': 'מנהלים וצומחים',
          'flow_3_subtitle': 'יותר חשיפה, יותר פניות ויותר עבודות סגורות.',
          'cap_title': 'מה מקבלים במסלול Pro?',
          'cap_subtitle':
              'כל היכולות שעוזרות לך לנהל עסק מקצועי ולסגור יותר עבודות.',
          'cap_1_title': 'דאשבורד מקצועי',
          'cap_1_sub': 'תמונת מצב מלאה על פניות, הכנסות וביצועים במקום אחד.',
          'cap_2_title': 'מערכת הזמנות חכמה',
          'cap_2_sub': 'ניהול בקשות עבודה, אישור/דחייה ותיעדוף יומי אוטומטי.',
          'cap_3_title': 'ניהול לידים ולקוחות',
          'cap_3_sub': 'מעקב אחרי כל ליד מהפנייה הראשונה ועד סגירת העבודה.',
          'cap_4_title': 'ניתוח נתונים מתקדם',
          'cap_4_sub': 'דוחות על שיעור סגירה, זמני תגובה ומקורות פניות.',
        };
    }
  }

  List<Map<String, dynamic>> get _capabilities {
    final s = _pageStrings;
    return [
      {
        'icon': Icons.dashboard_customize_rounded,
        'title': s['cap_1_title']!,
        'subtitle': s['cap_1_sub']!,
      },
      {
        'icon': Icons.event_available_rounded,
        'title': s['cap_2_title']!,
        'subtitle': s['cap_2_sub']!,
      },
      {
        'icon': Icons.manage_accounts_rounded,
        'title': s['cap_3_title']!,
        'subtitle': s['cap_3_sub']!,
      },
      {
        'icon': Icons.analytics_rounded,
        'title': s['cap_4_title']!,
        'subtitle': s['cap_4_sub']!,
      },
    ];
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
