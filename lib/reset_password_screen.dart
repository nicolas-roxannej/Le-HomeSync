import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ResetPasswordScreen extends StatelessWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: Stack(
        children: [
          // Background
          SingleChildScrollView(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 5, top: 65),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        size: 50,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        // Go back to login screen
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
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
              ],
            ),
          ),

          // Semi-transparent overlay
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withOpacity(0.5),
          ),

          // Success message modal
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 20),
              padding: EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Success icon
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_email_read,
                        color: Colors.green,
                        size: 70,
                      ),
                    ),

                    SizedBox(height: 24),

                    Text(
                      'Check Your Email!',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),

                    SizedBox(height: 16),

                    Text(
                      'We sent a password reset link to:',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.grey[700],
                      ),
                    ),

                    SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        email,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),

                    SizedBox(height: 10),

                    Text(
                      'From: noreply@homeautomation-b6d6d.firebaseapp.com',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),

                    SizedBox(height: 24),

                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange[200]!,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange[700],
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'IMPORTANT - CHECK:',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.orange[900],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          _buildCheckItem('Inbox (Primary)'),
                          _buildCheckItem(
                            'Spam/Junk folder ⚠️',
                            important: true,
                          ),
                          _buildCheckItem('Promotions tab'),
                          _buildCheckItem('Social tab'),
                          _buildCheckItem('Search "password reset"'),
                          _buildCheckItem('Wait 1-5 minutes for delivery'),
                        ],
                      ),
                    ),

                    SizedBox(height: 20),

                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Colors.grey[700],
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Click the link in your email to reset your password',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 20,
                                color: Colors.grey[700],
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'The link will expire in 1 hour',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Go back to login
                          Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Back to Login',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text, {bool important = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: important ? Colors.orange[700] : Colors.grey[700],
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: important ? Colors.orange[900] : Colors.grey[800],
                fontWeight: important ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
