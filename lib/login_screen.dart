import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/forgot_password_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:homesync/signup_screen.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homesync/homepage_screen.dart';
import 'package:homesync/email_otp_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _rememberMe = false;
  bool _passwordVisible = false;
  bool _isLoading = false;
  bool _showOTPModal = false;
  String? _userId;
  String? _userEmail;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final EmailOTPService _otpService = EmailOTPService();

  // Individual controllers for each OTP digit
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  int _otpResendSeconds = 30;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _loadRememberMe() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        _emailController.text = prefs.getString('saved_email') ?? '';
      }
    });
  }

  void _saveRememberMe(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', value);

    if (value) {
      await prefs.setString('saved_email', _emailController.text.trim());
    } else {
      await prefs.remove('saved_email');
    }
  }

  void _startResendTimer() {
    setState(() {
      _otpResendSeconds = 30;
    });

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_otpResendSeconds > 0) {
          _otpResendSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String _getOTPCode() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _clearOTPFields() {
    for (var controller in _otpControllers) {
      controller.clear();
    }
    if (_otpFocusNodes[0].canRequestFocus) {
      _otpFocusNodes[0].requestFocus();
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      if (userCredential.user != null) {
        _userId = userCredential.user!.uid;
        _userEmail = userCredential.user!.email!;

        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(_userId)
                .get();

        if (!userDoc.exists || !userDoc.data()!.containsKey('email')) {
          await FirebaseFirestore.instance.collection('users').doc(_userId).set(
            {'email': _userEmail, 'lastLogin': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        } else {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .update({'lastLogin': FieldValue.serverTimestamp()});
        }

        String generatedOtp = await _otpService.sendOTPToUser(
          _userId!,
          _userEmail!,
        );

        setState(() {
          _showOTPModal = true;
          _isLoading = false;
        });

        _startResendTimer();

        // Focus first OTP field after modal appears
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _otpFocusNodes[0].canRequestFocus) {
            _otpFocusNodes[0].requestFocus();
          }
        });

        _showSuccessMessage(
          'OTP sent to $_userEmail!',
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });

      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        default:
          errorMessage = e.message ?? 'Login failed.';
      }

      _showErrorMessage(errorMessage);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorMessage('Error: ${e.toString()}');
    }
  }

  Future<void> _verifyOTP() async {
    String otpCode = _getOTPCode();

    if (otpCode.length != 6) {
      _showErrorMessage('Please enter all 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      bool isValid = await _otpService.verifyOTP(_userId!, otpCode);

      if (isValid) {
        await _completeLogin();
      } else {
        setState(() {
          _isLoading = false;
        });
        _showErrorMessage('Invalid OTP. Please check and try again.');
        _clearOTPFields();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      String errorMessage = e.toString();
      if (errorMessage.contains('Exception:')) {
        errorMessage = errorMessage.replaceAll('Exception:', '').trim();
      }

      _showErrorMessage(errorMessage);
      _clearOTPFields();
    }
  }

  Future<void> _resendOTP() async {
    if (_otpResendSeconds > 0) {
      _showErrorMessage(
        'Please wait $_otpResendSeconds seconds before requesting a new code.',
      );
      return;
    }

    bool canRequest = await _otpService.canRequestNewOTP(_userId!);
    if (!canRequest) {
      int remaining = await _otpService.getRemainingCooldownSeconds(_userId!);
      _showErrorMessage(
        'Please wait $remaining seconds before requesting a new code.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String newOtp = await _otpService.sendOTPToUser(_userId!, _userEmail!);

      setState(() {
        _isLoading = false;
      });

      _clearOTPFields();
      _startResendTimer();

      _showSuccessMessage(
        'New OTP sent to your email!',
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorMessage('Failed to resend OTP. Please try again.');
    }
  }

  Future<void> _completeLogin() async {
    if (_rememberMe) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', _emailController.text.trim());
      await prefs.setBool('remember_me', true);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomepageScreen()),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
         content: Text(
      message,
      style: const TextStyle(color: Colors.black), // Add your desired color
    ),
        backgroundColor: const Color(0xFFE9E7E6),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildOTPInput(int index) {
    return Container(
      width: 38,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _otpControllers[index].text.isNotEmpty
              ? Colors.black
              : Colors.grey[400]!,
          width: _otpFocusNodes[index].hasFocus ? 2 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            height: 1.0,
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.only(bottom: 8),
            isDense: true,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            if (value.isNotEmpty && index < 5) {
              _otpFocusNodes[index + 1].requestFocus();
            } else if (value.isEmpty && index > 0) {
              _otpFocusNodes[index - 1].requestFocus();
            }

            if (index == 5 && value.isNotEmpty) {
              String fullOtp = _getOTPCode();
              if (fullOtp.length == 6) {
                _verifyOTP();
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: Stack(
        children: [
          // Main login form
          SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 5, top: 65),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          size: 50,
                          color: Colors.black,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const WelcomeScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Transform.translate(
                      offset: const Offset(0, -30),
                      child: Image.asset('assets/homebg.png', 
                        height: 200,
                        errorBuilder: (context, error, stackTrace) => const Text(
                          'HomeSync',
                          style: TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(-55, -250),
                    child: Text(
                      'LOG IN',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jaldi(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
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

                  // EMAIL FIELD
                  Transform.translate(
                    offset: const Offset(0, -100),
                    child: TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        prefixIcon: Icon(Icons.email, color: Colors.black),
                        hintText: 'Email Address',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email required';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),

                  // PASSWORD FIELD
                  Transform.translate(
                    offset: const Offset(0, -90),
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: !_passwordVisible,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.transparent,
                        prefixIcon: const Icon(Icons.lock, color: Colors.black),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordVisible ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                        ),
                        hintText: 'Password',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password required';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(100, -90),
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPasswordScreen(),
                        ),
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(-10, -135),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() => _rememberMe = value!);
                            _saveRememberMe(value!);
                          },
                        ),
                        Transform.translate(
                          offset: const Offset(-10, -1),
                          child: Text(
                            "Remember Me",
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(0, -80),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0),
                          side: const BorderSide(color: Colors.black),
                        ),
                        elevation: 5,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Log In',
                              style: GoogleFonts.judson(
                                fontSize: 24,
                                color: Colors.black,
                              ),
                            ),
                    ),
                  ),

                 Transform.translate(
                    offset: const Offset(0, -20),
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SignUpScreen(),
                      
                      ),
                    ),
                    child: Text(
                      'Don\'t have an account? SIGN UP',
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

         
          if (_showOTPModal) ...[
            
            GestureDetector(
              onTap: () {}, 
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black.withOpacity(0.3),
              ),
            ),

            // OTP Dialog 
            Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                     
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.security,
                          color: Colors.blue.shade700,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Two-Factor Authentication',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _userEmail ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
//box
                      SizedBox(
                        height: 55,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            6,
                            (index) => Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: index == 0 || index == 5 ? 0 : 2,
                              ),
                              child: _buildOTPInput(index),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
//resend
                      if (_otpResendSeconds > 0)
                        Text(
                          'Resend code in $_otpResendSeconds seconds',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        )
                      else
                        TextButton(
                          onPressed: _isLoading ? null : _resendOTP,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 16,
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Resend Code',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // btn
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _showOTPModal = false;
                                });
                                _clearOTPFields();
                                _resendTimer?.cancel();
                              },
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _verifyOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Verify',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}