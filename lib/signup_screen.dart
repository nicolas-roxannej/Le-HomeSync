import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/homepage_screen.dart';
import 'package:homesync/login_screen.dart';
import 'package:homesync/welcome_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // Agreement checkboxes
  bool _agreeToEULA = false;
  bool _agreeToTerms = false;
  bool _agreeToPrivacy = false;
  
  String? _emailError;
  String? _passwordError;
  String? _addressError;
  
  final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  
  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return _emailRegex.hasMatch(email);
  }
  
  bool _isValidAddress(String address) {
    return address.trim().isNotEmpty && address.trim().length >= 5;
  }

  void _showAgreementDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(0),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFFE9E7E6),
            ),
            child: Column(
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Text(
                    title,
                    style: GoogleFonts.jaldi(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                // divider
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildAgreementContent(content),
                  ),
                ),
                
                // Close Button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(1),
                          side: const BorderSide(color: Colors.black, width: 1),
                        ),
                        elevation: 5,
                        shadowColor: Colors.black.withOpacity(0.5),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.judson(
                          fontSize: 18,
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgreementContent(String content) {
    List<String> sections = content.split(RegExp(r'(?=\n\d+\.)'));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.asMap().entries.map((entry) {
        int index = entry.key;
        String section = entry.value;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) 
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.black12, thickness: 0.5),
              ),
            Text(
              section,
              style: GoogleFonts.inter(fontSize: 13, height: 1.5),
            ),
          ],
        );
      }).toList(),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back arrow
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5, top: 65),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, size: 50, color: Colors.black),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => WelcomeScreen()),
                      );
                    },
                  ),
                ),
              ),

              // Logo
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -30),
                  child: Image.asset(
                    'assets/homebg.png', 
                    height: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text('HomeSync', style: TextStyle(fontSize: 40));
                    },
                  ),
                ),
              ),

              // SIGN UP Title
              Transform.translate(
                offset: const Offset(-55, -250),
                child: Text(
                  'SIGN UP',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jaldi(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),

              // HOMESYNC 
              Transform.translate(
                offset: const Offset(1, -125),
                child: Text(
                  'HOMESYNC',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.mPlusRounded1c(
                    fontWeight: FontWeight.bold,
                    fontSize: 25,
                    color: Colors.black,
                  ),
                ),
              ),

              // Email Input
              Transform.translate(
                offset: const Offset(0, -100),
                child: _buildValidatedTextField(
                  controller: _emailController,
                  icon: Icons.email, 
                  hintText: 'Email Address',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email is required';
                    }
                    if (!_isValidEmail(value)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
              ),

              // Username Input
              Transform.translate(
                offset: const Offset(0, -95),
                child: _buildValidatedTextField(
                  controller: _usernameController,
                  icon: Icons.person, 
                  hintText: 'Username',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Username is required';
                    }
                    return null;
                  },
                ),
              ),

              // Address Input
              Transform.translate(
                offset: const Offset(0, -90),
                child: _buildValidatedTextField(
                  controller: _addressController,
                  icon: Icons.house, 
                  hintText: 'House Address',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'House address is required';
                    }
                    if (!_isValidAddress(value)) {
                      return 'Please enter a valid house address';
                    }
                    return null;
                  },
                ),
              ),

              // Password Input
              Transform.translate(
                offset: const Offset(0, -85),
                child: _buildPasswordField(
                  controller: _passwordController,
                  hintText: 'Password',
                  obscureText: _obscurePassword,
                  toggleVisibility: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters long';
                    }
                    return null;
                  },
                ),
              ),

              // Confirm Password Input
              Transform.translate(
                offset: const Offset(0, -80),
                child: _buildPasswordField(
                  controller: _confirmPasswordController,
                  hintText: 'Re-Enter Password',
                  obscureText: _obscureConfirmPassword,
                  toggleVisibility: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ),

              // Legal Agreements Section
              Transform.translate(
                offset: const Offset(0, -70),
                child: Column(
                  children: [
                    // EULA 
                    _buildAgreementCheckbox(
                      value: _agreeToEULA,
                      onChanged: (value) {
                        setState(() {
                          _agreeToEULA = value ?? false;
                        });
                      },
                      text: 'I agree to the ',
                      linkText: 'End User License Agreement (EULA)',
                      onTap: () {
                        _showAgreementDialog(
                          'End User License Agreement',
                          _getEULAText(),
                        );
                      },
                    ),
                    
                    // Terms of Use 
                    _buildAgreementCheckbox(
                      value: _agreeToTerms,
                      onChanged: (value) {
                        setState(() {
                          _agreeToTerms = value ?? false;
                        });
                      },
                      text: 'I agree to the ',
                      linkText: 'Terms of Use',
                      onTap: () {
                        _showAgreementDialog(
                          'Terms of Use',
                          _getTermsText(),
                        );
                      },
                    ),
                    
                    // Privacy Policy 
                    _buildAgreementCheckbox(
                      value: _agreeToPrivacy,
                      onChanged: (value) {
                        setState(() {
                          _agreeToPrivacy = value ?? false;
                        });
                      },
                      text: 'I agree to the ',
                      linkText: 'Privacy Policy',
                      onTap: () {
                        _showAgreementDialog(
                          'Privacy Policy',
                          _getPrivacyText(),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Create Account Button
              Transform.translate(
                offset: const Offset(0, -45),
                child: ElevatedButton(
                  onPressed: () async {
                    // Check if all agreements are accepted
                    if (!_agreeToEULA || !_agreeToTerms || !_agreeToPrivacy) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You must agree to all terms and conditions to create an account.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (_formKey.currentState!.validate()) {
                      try {
                        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                          email: _emailController.text.trim(),
                          password: _passwordController.text.trim(),
                        );

                        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
                          'email': _emailController.text.trim(),
                          'username': _usernameController.text.trim(),
                          'address': _addressController.text.trim(),
                          'createdAt': Timestamp.now(),
                          'agreedToEULA': true,
                          'agreedToTerms': true,
                          'agreedToPrivacy': true,
                          'agreementDate': Timestamp.now(),
                        });

                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => HomepageScreen()),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message ?? 'An error occurred during signup.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('An unexpected error occurred: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(1),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                    elevation: 5,
                    shadowColor: Colors.black.withOpacity(0.5),
                  ),
                  child: Text(
                    'Create Account',
                    style: GoogleFonts.judson(
                      fontSize: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              // Login Link
              Transform.translate(
                offset: const Offset(0, -15),
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LoginScreen()),
                    );
                  },
                  child: Text(
                    'Already have an account? LOG IN',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementCheckbox({
    required bool value,
    required Function(bool?) onChanged,
    required String text,
    required String linkText,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.black,
          ),
          Expanded(
            child: Wrap(
              children: [
                Text(
                  text,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.black87),
                ),
                GestureDetector(
                  onTap: onTap,
                  child: Text(
                    linkText,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidatedTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    required String? Function(String?) validator,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: validator,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: Icon(icon, color: Colors.black),
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          errorStyle: const TextStyle(color: Colors.red),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback toggleVisibility,
    required String? Function(String?) validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: validator,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.transparent,
          prefixIcon: const Icon(Icons.lock, color: Colors.black),
          suffixIcon: IconButton(
            icon: Icon(
              obscureText ? Icons.visibility : Icons.visibility_off,
              color: Colors.black54,
            ),
            onPressed: toggleVisibility,
          ),
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.grey),
          errorStyle: const TextStyle(color: Colors.red),
          border: const UnderlineInputBorder(),
        ),
      ),
    );
  }


  String _getEULAText() {
    return '''END USER LICENSE AGREEMENT (EULA)
Last updated: October 21, 2025

This End User License Agreement ("Agreement") is between MRLD Tech Solutions ("we," "us," or "our") and you ("user" or "you") for the use of the HomeSync mobile application ("App").

By installing or using HomeSync, you agree to this EULA. If you do not agree, please do not install or use the App.

1. LICENSE TO USE

We give you a personal, limited, and non-transferable license to download and use HomeSync on your device for personal and non-commercial use only. 

You do not own the app—you only have permission to use it while you follow these rules.

2. RESTRICTIONS

You agree not to:

• Copy, modify, or resell any part of the app.

• Reverse-engineer or decompile the code.

• Use the app for illegal or harmful activities.

• Share your login with others or use someone else's account.

If you break these rules, we may stop your access to the app.

3. ACCOUNT AND DATA

Some features of HomeSync may require you to sign up or log in. You agree to provide accurate information and keep your account secure. 

Our Privacy Policy explains how we collect and protect your data. By using HomeSync, you agree to those privacy terms.

4. UPDATES

We may release updates or improvements to fix bugs or add new features. You agree that we can update the app automatically or ask you to download updates when needed.

5. OWNERSHIP

HomeSync and everything inside it—including its name, logo, and design—belong to MRLD Tech Solutions. You are not allowed to claim or reuse them without our written permission.

6. DISCLAIMER

HomeSync is provided "as is", meaning we do our best to keep it working properly, but we can't guarantee it will always be perfect. We are not responsible for any data loss, errors, or problems caused by using the app.

7. LIMITATION OF LIABILITY

To the maximum extent allowed by law, we are not liable for any damages, losses, or issues that happen from using HomeSync. If you are unhappy with the app, your only option is to stop using it and uninstall it.

8. TERMINATION

You can stop using HomeSync at any time by uninstalling it. We may also suspend or remove your access if you violate this agreement or misuse the app.

9. GOVERNING LAW

This Agreement is governed by the laws of the Republic of the Philippines. Any legal matters will be handled in the courts of Cavite, Philippines.

10. CONTACT US

If you have any questions or concerns about this Agreement, please contact us at:

📧 mrldtechsolutions.support@gmail.com
📍 Dasmariñas City, Cavite, Philippines''';
  }

  String _getTermsText() {
    return '''TERMS OF USE
Last Updated: October 16, 2025

Welcome to HomeSync, a mobile application developed by MRLD Tech Solutions ("we," "us," or "our").

HomeSync is a mobile application that helps homeowners manage and control their home appliances with ease. It allows users to turn devices on or off, set schedules, monitor their status, and track energy consumption—all through a simple and reliable interface. Designed for comfort and convenience, HomeSync brings modern control and energy awareness to everyday living. 


These Legal Terms constitute a legally binding agreement made between you, whether personally or on behalf of an entity ("you"), and MRLD TECH, concerning your access to and use of the Services. By accessing the Services, you agree that you have read, understood, and agreed to be 
bound by all of these Legal Terms. 
IF YOU DO NOT AGREE WITH ALL OF THESE LEGAL TERMS, YOU ARE 
PROHIBITED FROM USING THE SERVICES AND MUST DISCONTINUE USE 
IMMEDIATELY.

1. USE OF OUR SERVICES

HomeSync is designed to help users manage, monitor, and control their home appliances conveniently. 
You may use the App solely for personal and non-commercial purposes and in accordance with these Terms and all applicable laws.

You agree not to use the App in any way that may:

• Violate local, national, or international laws or regulations; 

• Infringe on the rights of others; 

• Harm or attempt to harm the App, its users, or our systems.

2. ACCOUNT REGISTRATION

To access certain features, you may need to create an account. When doing so, you agree to:

• Provide accurate, complete, and up-to-date information

• Keep your login credentials secure

• Be fully responsible for all activities under your account

We reserve the right to suspend or terminate accounts that contain false information or are used in violation of these Terms.

3. INTELLECTUAL PROPERTY

All materials in HomeSync — including software, logos, design, databases, and content — are owned by MRLD Tech Solutions. 

You may not copy, modify, distribute, sell, or reverse-engineer any part of the App without our written consent.

Any feedback or suggestions you submit may be used by us freely for product 
improvement, without any obligation to compensate or credit you. 

4. PROHIBITED ACTIVITIES

You agree not to:

• Interfere with or disrupt the App's servers or networks;

• Attempt to gain unauthorized access to other accounts or data;

• Use the App to transmit viruses, malware, or harmful code;

• Copy, modify, or reverse-engineer any software component;

• Use the App for commercial purposes without prior approval;

• Access, monitor, or control devices you do not own or have authorization for. 

Violation of these restrictions may result in suspension, termination, or legal action.

5. PRIVACY AND DATA PROTECTION

Your privacy is very important to us. Please review our Privacy Policy, which explains how we collect, use, and protect your personal information.

By using HomeSync, you consent to the collection and use of your data as described in the Privacy Policy. 

Privacy Policy: https://yourusername.github.io/homesync-app/privacy

6. UPDATES AND SERVICE AVAILABILITY

We may release updates from time to time to enhance performance, fix bugs, or introduce new features. 

Some updates may be required for continued use of the App.

While we aim to maintain reliable service, HomeSync may occasionally be unavailable due to maintenance or technical issues, or factors beyond our control. We are not 
responsible for any loss or inconvenience caused by temporary downtime. 


7. TERMINATION OF USE

You may stop using HomeSync at any time by uninstalling the App. We reserve the right to suspend or terminate your account or access to the App if you violate these Terms or misuse our Services. Upon termination, your right to use the App 
will immediately end.

8. DISCLAIMER OF WARRANTIES

HomeSync and all related services are provided "as is" and "as available." We make no warranties, whether express or implied, regarding the App's performance, reliability, or fitness for a particular purpose.

While we strive to keep the App secure and functional, we do not guarantee that it will 
always be error-free, uninterrupted, or completely secure. 

9. LIMITATION OF LIABILITY

To the maximum extent permitted by law, MRLD Tech Solutions shall not be liable for any indirect, incidental, or consequential damages including but not limited to data loss, device malfunction, or service interruption resulting from your use of the App.

If we are found liable for any reason, our total liability shall not exceed ₱20,000 or the amount you paid (if any) for using the App, whichever is lower. 

10. THIRD-PARTY SERVICES 

HomeSync may rely on third-party services such as Firebase for hosting, authentication, or analytics. 
Your use of these services may be subject to their own terms and policies. We are not responsible for any issues or damages arising from third-party integrations.

11. GOVERNING LAW 

These Terms are governed by and interpreted under the laws of the Republic of the Philippines. Any disputes arising from or relating to these Terms shall be settled exclusively in the courts of Cavite, Philippines. 

12. CHANGES TO THESE TERMS 

We may update these Terms from time to time to reflect changes in our business or legal requirements. When we do, we will revise the “Last Updated” date and may notify you through the App or email. Continued use of HomeSync after any update means you accept the new Terms.

13. CONTACT US

If you have questions, feedback, or requests related to these Terms, please contact us at: 

📍 Dasmariñas City, Cavite, Philippines
📧 mrldtechsolutions.support@gmail.com''';
  }

  String _getPrivacyText() {
    return '''PRIVACY NOTICE
Last updated: October 16, 2025

This Privacy Notice for MRLD Tech Solutions ("we," "us," or "our") explains how and why we collect, store, use, and share ("process") your personal information when you use our mobile application HomeSync.(the “App”) and related services (the 
“Services”). 

By using HomeSync, you agree to this Privacy Notice. If you do not agree, please do not use our App or Services. 

1. WHAT INFORMATION DO WE COLLECT?

Personal Information You Provide 

We collect personal information that you voluntarily provide when you: 

• Register or log in to HomeSync 

• Create or update your account 

• Contact us for help or support 

This may include: 

•Name 

• Email address 

All personal information must be true, complete, and accurate. Please notify us if your information changes.

2. HOW DO WE PROCESS YOUR INFORMATION?

We process your information to: 

• Provide, maintain, and improve our Services

• Manage your account and preferences 

• Respond to your inquiries or support requests 

• Ensure the security and stability of our App 

• Comply with legal and regulatory obligations 

We only process personal information when we have a valid legal reason to do so. 

3. WHEN AND WITH WHOM DO WE SHARE YOUR INFORMATION?

We may share your personal information in the following limited cases: 

• Service Providers: We use trusted third parties (such as Firebase) to provide hosting, authentication, and data storage. 

• Legal Requirements: We may disclose your information if required by law or to respond to valid legal requests. 

We do not sell, rent, or trade your personal information to anyone. 

4. DO WE USE COOKIES OR TRACKING TECHNOLOGIES?

The HomeSync App itself does not use cookies. However, if we use third-party analytics tools (like Firebase Analytics), these services may automatically collect basic app-usage information to help us understand how users interact with HomeSync and improve performance. 

5. HOW LONG DO WE KEEP YOUR INFORMATION?

We keep your personal information only as long as needed for the purposes described in this Privacy Notice, unless a longer retention period is required by law. When your information is no longer needed, we securely delete or anonymize it. 

6. WHAT ARE YOUR PRIVACY RIGHTS?

• Access, update, or delete your personal data 

To exercise these rights, contact us using the details below.

7.  DO-NOT-TRACK FEATURES 

Most browsers and mobile operating systems include a Do-Not-Track (DNT) feature. We currently do not respond to DNT signals, but if a universal standard is adopted, we will follow it and update this Privacy Notice. 

8.  DO WE MAKE UPDATES TO THIS NOTICE? 

Yes. We may update this Privacy Notice from time to time. When we do, we’ll update the “Last updated” date and notify users in the App or via email if there are significant changes.

9. HOW CAN YOU REVIEW, UPDATE, OR DELETE YOUR DATA? 

To review, update, or delete your data collected through HomeSync, please email mrldtechsolutions.support@gmail.com We’ll respond in accordance with applicable privacy laws.

10. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?

If you have questions, feedback, or requests regarding this Privacy Notice, you may contact us at: 

📍 Dasmariñas City, Cavite, Philippines
📧 mrldtechsolutions.support@gmail.com
''';
  }
}