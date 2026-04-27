import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class VerifyBusinessPage extends StatefulWidget {
  const VerifyBusinessPage({super.key});

  @override
  State<VerifyBusinessPage> createState() => _VerifyBusinessPageState();
}

class _VerifyBusinessPageState extends State<VerifyBusinessPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxBranchController = TextEditingController();

  String _dealerType = 'exempt'; // 'exempt' (פטור) or 'licensed' (מורשה)
  bool _isUploading = false;
  bool _isLoadingStatus = true;
  String? _currentStatus; // 'pending', 'verified', 'rejected', or null

  bool _acceptedTerms = false;
  bool _isLegalDeclarationSigned = false;
  bool _acceptedResponsibility = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('verifications')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _currentStatus = doc.data()?['status'];
          });
        }
      } catch (e) {
        debugPrint("Status check error: $e");
      }
    }
    if (mounted) setState(() => _isLoadingStatus = false);
  }

  @override
  void dispose() {
    _idController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    _taxBranchController.dispose();
    super.dispose();
  }

  Future<void> _submitVerification() async {
    final isHe =
        Provider.of<LanguageProvider>(
          context,
          listen: false,
        ).locale.languageCode ==
        'he';

    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms ||
        !_isLegalDeclarationSigned ||
        !_acceptedResponsibility) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isHe
                ? 'עליך לאשר את כל הצהרות החוקיות'
                : 'You must accept all legal declarations',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;

      final businessId = _idController.text.trim();
      final verificationData = {
        'userId': user.uid,
        'businessId': businessId,
        'businessName': _businessNameController.text.trim(),
        'address': _addressController.text.trim(),
        'taxBranch': _taxBranchController.text.trim(),
        'dealerType': _dealerType,
        'status': 'pending',
        'legalAccepted': true,
        'responsibilityAccepted': true,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Save to verifications collection
      await FirebaseFirestore.instance
          .collection('verifications')
          .doc(user.uid)
          .set(verificationData);

      // Update user document in unified 'users' collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'dealerType': _dealerType,
            'businessId': businessId,
            'businessVerificationStatus': 'pending',
          });

      if (mounted) {
        _showSuccessDialog(isHe);
      }
    } catch (e) {
      debugPrint("Verification submit error: $e");
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSuccessDialog(bool isHe) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Icon(Icons.verified_user, size: 50, color: Colors.green[600]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isHe ? 'הבקשה הוגשה בהצלחה' : 'Request Submitted!',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(
              isHe
                  ? 'המסמכים הועברו לבדיקה מול רשויות המס. סטטוס החשבון יעודכן תוך 48 שעות.'
                  : 'Documents submitted for tax authority review. Account status will be updated within 48 hours.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(isHe ? 'הבנתי' : 'Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale.languageCode;
    final isHe = locale == 'he';

    return Directionality(
      textDirection: isHe ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            isHe ? 'אימות זהות ועסק' : 'Identity & Business Verification',
          ),
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoadingStatus
            ? const Center(child: CircularProgressIndicator())
            : _isUploading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "מעלה מסמכים ומאמת...",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : _currentStatus == 'pending' || _currentStatus == 'verified'
            ? _buildStatusScreen(isHe)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_currentStatus == 'rejected')
                        _buildRejectedNotice(isHe),
                      _buildStepHeader(
                        1,
                        isHe
                            ? 'פרטי העסק והרישום'
                            : 'Business & Registration Details',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _businessNameController,
                        decoration: _inputStyle(
                          isHe ? 'שם העסק הרשום' : 'Registered Business Name',
                          Icons.business,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? (isHe ? 'חובה' : 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idController,
                        decoration: _inputStyle(
                          isHe
                              ? 'מספר עוסק / ח.פ / ת.ז'
                              : 'Business ID / VAT ID',
                          Icons.badge_outlined,
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v!.isEmpty ? (isHe ? 'חובה' : 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taxBranchController,
                        decoration: _inputStyle(
                          isHe ? 'סניף מע"מ / מס הכנסה' : 'Tax Office Branch',
                          Icons.account_balance_rounded,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? (isHe ? 'חובה' : 'Required') : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        decoration: _inputStyle(
                          isHe ? 'כתובת העסק המלאה' : 'Business Address',
                          Icons.location_on_outlined,
                        ),
                        validator: (v) =>
                            v!.isEmpty ? (isHe ? 'חובה' : 'Required') : null,
                      ),

                      const SizedBox(height: 24),
                      _buildStepHeader(
                        2,
                        isHe
                            ? 'סיווג עוסק לצרכי מס'
                            : 'Tax Dealer Classification',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isHe
                            ? 'שים לב: הגדרה זו תקבע את סוגי המסמכים (חשבונית/קבלה) שתוכל להפיק.'
                            : 'Note: This setting determines the document types (Invoice/Receipt) you can generate.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dealerTypeCard(
                              'exempt',
                              isHe ? 'עוסק פטור' : 'Exempt Dealer',
                              Icons.money_off,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dealerTypeCard(
                              'licensed',
                              isHe
                                  ? 'עוסק מורשה / חברה'
                                  : 'Licensed Dealer / Co.',
                              Icons.payments_outlined,
                            ),
                          ),
                        ],
                      ),
                      _buildStepHeader(
                        3,
                        isHe
                            ? 'אישורים והצהרות משפטיות'
                            : 'Legal Confirmations',
                      ),
                      const SizedBox(height: 12),
                      _buildLegalCheckbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v!),
                        label: isHe
                            ? 'קראתי ואני מסכים לתנאי השימוש וכללי האתיקה של הירו.'
                            : 'I have read and agree to the hiro Terms of Use and Code of Ethics.',
                      ),
                      _buildLegalCheckbox(
                        value: _isLegalDeclarationSigned,
                        onChanged: (v) =>
                            setState(() => _isLegalDeclarationSigned = v!),
                        label: isHe
                            ? 'אני מצהיר כי כל המידע שמסרתי נכון, תקף ומקורי.'
                            : 'I declare that all information provided is correct, valid, and original.',
                      ),
                      _buildLegalCheckbox(
                        value: _acceptedResponsibility,
                        onChanged: (v) =>
                            setState(() => _acceptedResponsibility = v!),
                        label: isHe
                            ? 'אני אחראי לכל מידע שגוי או מטעה שאמסור לכם.'
                            : 'I am responsible for any wrong or misleading information I provide.',
                      ),

                      const SizedBox(height: 40),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        onPressed: _submitVerification,
                        child: Text(
                          isHe ? 'שלח לאישור משפטי' : 'Submit for Legal Review',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildStatusScreen(bool isHe) {
    bool isPending = _currentStatus == 'pending';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending
                  ? Icons.hourglass_bottom_rounded
                  : Icons.verified_rounded,
              size: 80,
              color: isPending ? Colors.orange : Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              isPending
                  ? (isHe ? 'הבקשה בבדיקה' : 'Verification Pending')
                  : (isHe ? 'העסק מאומת' : 'Business Verified'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              isPending
                  ? (isHe
                        ? 'שלחת כבר בקשת אימות. הצוות שלנו בודק את המסמכים שלך. בדרך כלל זה לוקח עד 48 שעות.'
                        : 'You have already submitted a verification request. Our team is reviewing your documents. This usually takes up to 48 hours.')
                  : (isHe
                        ? 'מזל טוב! העסק שלך מאומת במערכת.'
                        : 'Congratulations! Your business is verified in our system.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(isHe ? 'חזור לפרופיל' : 'Back to Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedNotice(bool isHe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isHe
                  ? 'בקשת האימות הקודמת שלך נדחתה. אנא בדוק את המסמכים ושלח שוב.'
                  : 'Your previous verification request was rejected. Please check your documents and resubmit.',
              style: TextStyle(
                color: Colors.red[900],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(int step, String title) {
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF1976D2),
          child: Text(
            step.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.blueGrey, size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _dealerTypeCard(String type, String label, IconData icon) {
    bool isSelected = _dealerType == type;
    return InkWell(
      onTap: () => setState(() => _dealerType = type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1976D2).withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1976D2)
                : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF1976D2) : Colors.grey,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? const Color(0xFF1976D2) : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF1976D2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}
