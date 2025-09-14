import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/forgot_password_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:homesync/signup_screen.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:homesync/homepage_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _rememberMe = false;
  bool _passwordVisible = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
    _checkAutoLogin(); // Check if user should be auto-logged in
    _passwordVisible = false;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Load remember me state and saved credentials
  void _loadRememberMe() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        // Load saved email if remember me is enabled
        _emailController.text = prefs.getString('saved_email') ?? '';
      }
    });
  }

  // Save remember me state and credentials
  void _saveRememberMe(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', value);
    
    if (value) {
      // Save email when remember me is checked
      await prefs.setString('saved_email', _emailController.text.trim());
      // Save login timestamp for auto-login expiration
      await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
    } else {
      // Clear saved data when remember me is unchecked
      await prefs.remove('saved_email');
      await prefs.remove('login_timestamp');
    }
  }

  // Check if user should be automatically logged in
  void _checkAutoLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool rememberMe = prefs.getBool('remember_me') ?? false;
    
    if (rememberMe) {
      int? loginTimestamp = prefs.getInt('login_timestamp');
      
      if (loginTimestamp != null) {
        // Check if login is still valid (e.g., within 30 days)
        DateTime loginTime = DateTime.fromMillisecondsSinceEpoch(loginTimestamp);
        DateTime now = DateTime.now();
        int daysDifference = now.difference(loginTime).inDays;
        
        // Auto-login if within 30 days and Firebase user is still authenticated
        if (daysDifference < 30 && FirebaseAuth.instance.currentUser != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomepageScreen()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      appBar: null,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 5, top: 65),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, size: 50, color: Colors.black),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => WelcomeScreen()),
                      );
                    },
                  ),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: Offset(0, -20),
                  child: Image.asset(
                    'assets/homesync_logo.png',
                    height: 120,
                    errorBuilder: (context, error, stackTrace) {
                      return Text('HomeSync', style: TextStyle(fontSize: 40));
                    },
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(-55, -170),
                child: Text(
                  'LOG IN',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jaldi(
                    textStyle: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                    color: Colors.black,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(1, -70),
                child: Text(
                  'HOMESYNC',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.instrumentSerif(
                    textStyle: TextStyle(fontSize: 25),
                    color: Colors.black,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -30),
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    prefixIcon: Icon(
                      Icons.email,
                      color: Colors.black,
                    ),
                    hintText: 'Email Address',
                    hintStyle: TextStyle(color: Colors.grey),
                    errorStyle: TextStyle(color: Colors.red),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email is required';
                    }
                    return null;
                  },
                ),
              ),
              Transform.translate(
                offset: Offset(0, -20),
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    prefixIcon: Icon(
                      Icons.lock,
                      color: Colors.black,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible 
                            ? Icons.visibility 
                            : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _passwordVisible = !_passwordVisible;
                        });
                      },
                    ),
                    hintText: 'Password',
                    hintStyle: TextStyle(color: Colors.grey),
                    errorStyle: TextStyle(color: Colors.red),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
              ),
              Transform.translate(
                offset: Offset(100, -25),
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ForgotPasswordScreen()),
                    );  
                  },
                  child: Text(
                    'Forgot Password?',
                    style: GoogleFonts.inter(
                      textStyle: TextStyle(
                        fontSize: 14,
                      ),
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(-10, -70),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (bool? value) {
                            setState(() {
                              _rememberMe = value!;
                            });
                            _saveRememberMe(value!);
                          },
                        ),
                        Transform.translate(
                          offset: Offset(-10, -1),
                          child: Text(
                            "Remember Me",
                            style: GoogleFonts.inter(
                              textStyle: TextStyle(fontSize: 14),
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: Offset(0, -20),
                child: ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      try {
                        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
                          email: _emailController.text.trim(),
                          password: _passwordController.text.trim(),
                        );
                        
                        if (userCredential.user != null) {
                          // Save login info if remember me is checked
                          if (_rememberMe) {
                            SharedPreferences prefs = await SharedPreferences.getInstance();
                            await prefs.setString('saved_email', _emailController.text.trim());
                            await prefs.setInt('login_timestamp', DateTime.now().millisecondsSinceEpoch);
                          }
                          
                          // Navigate to the next screen upon successful login
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => HomepageScreen()),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Login successful, but user data is unavailable. Please try again.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.message ?? 'An error occurred during login.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('An unexpected error occurred.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 13, horizontal: 10),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                      side: BorderSide(color: Colors.black, width: 1),
                    ),
                    elevation: 5,
                    shadowColor: Colors.black.withOpacity(0.5),
                  ),
                  child: Text(
                    'Log In',
                    style: GoogleFonts.judson(
                      fontSize: 24,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SignUpScreen()),
                  );
                },
                child: Text(
                  'Don\'t have an account? SIGN UP',
                  style: GoogleFonts.inter(
                    textStyle: TextStyle(
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
}