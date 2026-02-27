import 'dart:io';
import 'package:flutter/material.dart';
import 'package:untitled1/pages/subscription.dart';
import 'package:untitled1/pages/sighn_in.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({Key? key}) : super(key: key);

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

enum UserType { normal, worker }

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _optionalPhoneController = TextEditingController();

  UserType _userType = UserType.normal;
  String? _selectedTown;
  bool _agreedToPolicy = false;
  bool _isSubscribed = false;

  final List<String> _israeliTowns = [
    'Jerusalem',
    'Tel Aviv',
    'Haifa',
    'Rishon LeZion',
    'Petah Tikva',
    'Ashdod',
    'Netanya',
    'Beersheba',
    'Holon',
    'Bnei Brak',
    'Ramat Gan',
    'Rehovot',
  ];

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _optionalPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: const Color(0xFF1976D2),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTypeSelector(),
              const SizedBox(height: 24),
              _buildProfilePicturePlaceholder(),
              const SizedBox(height: 24),
              _buildTextField(_nameController, 'Full Name', Icons.person),
              const SizedBox(height: 16),
              _buildTextField(_emailPhoneController, 'Email or Phone Number', Icons.contact_mail),
              const SizedBox(height: 16),
              _buildTextField(_passwordController, 'Password', Icons.lock, obscureText: true),
              const SizedBox(height: 16),
              _buildTownDropdown(),
              
              if (_userType == UserType.worker) ...[
                const SizedBox(height: 16),
                _buildTextField(_phoneController, 'Worker Phone Number', Icons.phone),
                const SizedBox(height: 16),
                _buildTextField(_optionalPhoneController, 'Alternative Phone Number', Icons.phone_android, isRequired: false),
                const SizedBox(height: 16),
                _buildTextField(_idController, 'ID Number', Icons.badge),
                const SizedBox(height: 16),
                _buildTextField(_descriptionController, 'Description about yourself', Icons.description, maxLines: 3),
                const SizedBox(height: 24),
                _buildSubscriptionSection(),
              ],

              const SizedBox(height: 16),
              _buildPolicyCheckbox(),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_userType == UserType.worker ? 'Pay & Sign Up' : 'Sign Up'),
              ),
              const SizedBox(height: 32),
              _buildSocialLogins(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeButton('Normal User', UserType.normal),
          ),
          Expanded(
            child: _buildTypeButton('Worker', UserType.worker),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String label, UserType type) {
    final isSelected = _userType == type;
    return GestureDetector(
      onTap: () => setState(() => _userType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1976D2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildProfilePicturePlaceholder() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[300],
            child: const Icon(Icons.person, size: 50, color: Colors.white),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0xFF1976D2), shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, int maxLines = 1, bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: isRequired ? label : '$label (Optional)',
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (value) {
        if (isRequired && (value?.isEmpty ?? true)) {
          return 'This field is required';
        }
        return null;
      },
    );
  }

  Widget _buildTownDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTown,
      decoration: InputDecoration(
        labelText: 'Select your town',
        prefixIcon: const Icon(Icons.location_city),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _israeliTowns.map((town) {
        return DropdownMenuItem(value: town, child: Text(town));
      }).toList(),
      onChanged: (value) => setState(() => _selectedTown = value),
      validator: (value) => value == null ? 'Please select a town' : null,
    );
  }

  Widget _buildSubscriptionSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        children: [
          const Text(
            'Worker Subscription',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text('Joining as a worker requires a monthly subscription.'),
          if (_isSubscribed)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Subscription Paid', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            TextButton(
              onPressed: () async {
                // First validate all fields
                if (_formKey.currentState!.validate()) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SubscriptionPage(email: _emailPhoneController.text),
                    ),
                  );
                  if (result == true) {
                    setState(() {
                      _isSubscribed = true;
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields before proceeding to payment')),
                  );
                }
              },
              child: const Text('View Pricing Plans & Pay'),
            ),
        ],
      ),
    );
  }

  Widget _buildPolicyCheckbox() {
    return Row(
      children: [
        Checkbox(
          value: _agreedToPolicy,
          onChanged: (value) => setState(() => _agreedToPolicy = value ?? false),
        ),
        const Expanded(
          child: Text('I agree to the App Policy and Terms of Service'),
        ),
      ],
    );
  }

  Widget _buildSocialLogins() {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR JOIN WITH', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _socialButton('Gmail', Colors.red, Icons.mail),
            _socialButton('Facebook', Colors.blue[800]!, Icons.facebook),
            if (Platform.isIOS) _socialButton('Apple', Colors.black, Icons.apple),
          ],
        ),
      ],
    );
  }

  Widget _socialButton(String label, Color color, IconData icon) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      if (!_agreedToPolicy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must agree to the policy')),
        );
        return;
      }
      
      if (_userType == UserType.worker) {
        if (!_isSubscribed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please pay the subscription first')),
          );
          return;
        }
        // If subscribed, go to sign in
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => SignInPage(initialEmail: _emailPhoneController.text),
          ),
          (Route<dynamic> route) => false,
        );
      } else {
        // Normal user logic
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => SignInPage(initialEmail: _emailPhoneController.text),
          ),
          (Route<dynamic> route) => false,
        );
      }
    }
  }
}
