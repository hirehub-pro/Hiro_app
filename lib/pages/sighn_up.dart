import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _optionalPhoneController = TextEditingController();

  UserType _userType = UserType.normal;
  String? _selectedTown;
  List<String> _selectedProfessions = [];
  bool _agreedToPolicy = false;
  bool _isSubscribed = false;
  bool _isLoading = false;
  File? _image;
  final ImagePicker _picker = ImagePicker();

  final List<String> _israeliTowns = [
    'Jerusalem', 'Tel Aviv', 'Haifa', 'Rishon LeZion', 'Petah Tikva', 'Ashdod',
    'Netanya', 'Beersheba', 'Holon', 'Bnei Brak', 'Ramat Gan', 'Rehovot',
  ];

  final List<String> _professions = [
    'Plumber', 'Carpenter', 'Electrician', 'Painter', 'Cleaner', 'Handyman', 
    'Landscaper', 'HVAC', 'Locksmith', 'Gardener', 'Mechanic', 'Photographer', 
    'Tutor', 'Tailor', 'Mover', 'Interior Designer', 'Beautician', 'Pet Groomer'
  ];

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _optionalPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the policy')));
      return;
    }
    if (_userType == UserType.worker) {
      if (!_isSubscribed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pay the subscription first')));
        return;
      }
      if (_selectedProfessions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one profession')));
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = userCredential.user;
      if (user == null) throw Exception('User creation failed');

      await user.updateDisplayName(_nameController.text.trim());

      String? imageUrl;
      if (_image != null) {
        final storageRef = FirebaseStorage.instance.ref().child('profile_pictures/${user.uid}.jpg');
        await storageRef.putFile(_image!);
        imageUrl = await storageRef.getDownloadURL();
      }

      Map<String, dynamic> userData = {
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'town': _selectedTown,
        'userType': _userType == UserType.worker ? 'worker' : 'normal',
        'createdAt': ServerValue.timestamp,
        'profileImageUrl': imageUrl ?? "",
      };

      if (_userType == UserType.worker) {
        userData.addAll({
          'phone': _phoneController.text.trim(),
          'optionalPhone': _optionalPhoneController.text.trim(),
          'idNumber': _idController.text.trim(),
          'description': _descriptionController.text.trim(),
          'isSubscribed': _isSubscribed,
          'professions': _selectedProfessions,
        });
      }

      final DatabaseReference dbRef = FirebaseDatabase.instanceFor(
        app: FirebaseAuth.instance.app,
        databaseURL: 'https://hire-hub-fe6c4-default-rtdb.firebaseio.com'
      ).ref();

      await dbRef.child('users').child(user.uid).set(userData);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created successfully!')));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => SignInPage(initialEmail: _emailController.text)),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Auth Error')));
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Database Error: ${e.message}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: const Color(0xFF1976D2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTypeSelector(),
                  const SizedBox(height: 24),
                  _buildProfilePicturePicker(),
                  const SizedBox(height: 24),
                  _buildTextField(_nameController, 'Full Name', Icons.person),
                  const SizedBox(height: 16),
                  _buildTextField(_emailController, 'Email', Icons.email),
                  const SizedBox(height: 16),
                  _buildTextField(_passwordController, 'Password', Icons.lock, obscureText: true),
                  const SizedBox(height: 16),
                  _buildTownDropdown(),

                  if (_userType == UserType.worker) ...[
                    const SizedBox(height: 16),
                    _buildMultiProfessionsDropdown(),
                    const SizedBox(height: 16),
                    _buildTextField(_phoneController, 'Worker Phone Number', Icons.phone),
                    const SizedBox(height: 16),
                    _buildTextField(_optionalPhoneController, 'Alternative Phone Number', Icons.phone_android, isRequired: false),
                    const SizedBox(height: 16),
                    _buildTextField(_idController, 'ID Number', Icons.badge),
                    const SizedBox(height: 16),
                    _buildTextField(_descriptionController, 'Description', Icons.description, maxLines: 3),
                    const SizedBox(height: 24),
                    _buildSubscriptionSection(),
                  ],

                  const SizedBox(height: 16),
                  _buildPolicyCheckbox(),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Sign Up', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _buildTypeButton('Normal User', UserType.normal)),
          Expanded(child: _buildTypeButton('Worker', UserType.worker)),
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
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildProfilePicturePicker() {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[300],
              backgroundImage: _image != null ? FileImage(_image!) : null,
              child: _image == null 
                ? const Icon(Icons.person, size: 50, color: Colors.white) 
                : null,
            ),
            Positioned(
              bottom: 0, 
              right: 0, 
              child: Container(
                padding: const EdgeInsets.all(4), 
                decoration: const BoxDecoration(color: Color(0xFF1976D2), shape: BoxShape.circle), 
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20)
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, int maxLines = 1, bool isRequired = true}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: isRequired ? label : '$label (Optional)', prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      validator: (value) => isRequired && (value?.isEmpty ?? true) ? 'Required' : null,
    );
  }

  Widget _buildTownDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedTown,
      decoration: InputDecoration(labelText: 'Select your town', prefixIcon: const Icon(Icons.location_city), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      items: _israeliTowns.map((town) => DropdownMenuItem(value: town, child: Text(town))).toList(),
      onChanged: (value) => setState(() => _selectedTown = value),
      validator: (value) => value == null ? 'Please select a town' : null,
    );
  }

  Widget _buildMultiProfessionsDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormField<List<String>>(
          initialValue: _selectedProfessions,
          validator: (value) => _selectedProfessions.isEmpty ? 'Select at least one profession' : null,
          builder: (state) {
            return InputDecorator(
              decoration: InputDecoration(
                labelText: 'Select your professions',
                prefixIcon: const Icon(Icons.work),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                errorText: state.errorText,
              ),
              child: Column(
                children: [
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Choose professions'),
                    underline: Container(),
                    items: _professions.map((p) {
                      return DropdownMenuItem<String>(
                        value: p,
                        child: StatefulBuilder(
                          builder: (context, setMenuState) {
                            return CheckboxListTile(
                              title: Text(p),
                              value: _selectedProfessions.contains(p),
                              onChanged: (bool? checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedProfessions.add(p);
                                  } else {
                                    _selectedProfessions.remove(p);
                                  }
                                });
                                state.didChange(_selectedProfessions);
                                setMenuState(() {});
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      );
                    }).toList(),
                    onChanged: (_) {},
                  ),
                  if (_selectedProfessions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _selectedProfessions.map((p) => Chip(
                          label: Text(p),
                          onDeleted: () {
                            setState(() {
                              _selectedProfessions.remove(p);
                            });
                            state.didChange(_selectedProfessions);
                          },
                        )).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSubscriptionSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[200]!)),
      child: Column(
        children: [
          const Text('Worker Subscription', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Joining as a worker requires a monthly subscription.'),
          if (_isSubscribed)
            const Padding(padding: EdgeInsets.only(top: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Subscription Paid', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]))
          else
            TextButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => SubscriptionPage(email: _emailController.text)));
                  if (result == true) setState(() => _isSubscribed = true);
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
        Checkbox(value: _agreedToPolicy, onChanged: (value) => setState(() => _agreedToPolicy = value ?? false)),
        const Expanded(child: Text('I agree to the Policy')),
      ],
    );
  }
}
