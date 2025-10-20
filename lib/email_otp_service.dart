import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailOTPService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ⚠️ IMPORTANT: Replace these with your actual email credentials
  // For Gmail: You need to use App Password, not your regular password
  // Generate App Password: Google Account > Security > 2-Step Verification > App passwords
  static const String _senderEmail =
      'homesync.noreply@gmail.com'; // Replace with your email
  static const String _senderPassword =
      'ptadxxqjyyjruhgj'; // Replace with App Password
  static const String _senderName = 'HomeSync';

  // Generate 6-digit OTP
  String _generateOTP() {
    final random = Random();
    final otp = (100000 + random.nextInt(900000)).toString();
    return otp;
  }

  // Send OTP to user's email
  Future<String> sendOTPToUser(String userId, String s) async {
    try {
      // Get user's email from Firebase Auth
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();

      if (userData == null || !userData.containsKey('email')) {
        throw Exception('User email not found');
      }

      final userEmail = userData['email'] as String;
      final otp = _generateOTP();
      final expiryTime = DateTime.now().add(
        Duration(minutes: 5),
      ); // OTP valid for 5 minutes

      // Store OTP in Firestore
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('otp_verification')
          .doc('current')
          .set({
            'otp': otp,
            'expiryTime': expiryTime,
            'createdAt': FieldValue.serverTimestamp(),
            'isUsed': false,
          });

      // Send email
      await _sendEmail(userEmail, otp);

      print('OTP sent successfully to $userEmail');
      return otp; // Return for development mode display
    } catch (e) {
      print('Error sending OTP: $e');
      throw Exception('Failed to send OTP: ${e.toString()}');
    }
  }

  // Send email using SMTP
  Future<void> _sendEmail(String recipientEmail, String otp) async {
    try {
      // Configure SMTP server (Gmail example)
      final smtpServer = gmail(_senderEmail, _senderPassword);

      // Alternative SMTP configurations:
      // For other email providers, use:
      // final smtpServer = SmtpServer(
      //   'smtp.your-provider.com',
      //   port: 587,
      //   username: _senderEmail,
      //   password: _senderPassword,
      // );

      // Create email message
      final message =
          Message()
            ..from = Address(_senderEmail, _senderName)
            ..recipients.add(recipientEmail)
            ..subject = 'HomeSync - Your Login Verification Code'
            ..html = '''
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; background-color: #f4f4f4; margin: 0; padding: 0; }
              .container { max-width: 600px; margin: 50px auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
              .header { text-align: center; color: #333; margin-bottom: 30px; }
              .otp-box { background: #f8f9fa; border: 2px dashed #007bff; padding: 20px; text-align: center; border-radius: 8px; margin: 20px 0; }
              .otp-code { font-size: 36px; font-weight: bold; color: #007bff; letter-spacing: 8px; margin: 10px 0; }
              .info { color: #666; font-size: 14px; line-height: 1.6; margin: 20px 0; }
              .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; color: #856404; }
              .footer { text-align: center; color: #999; font-size: 12px; margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>🏠 HomeSync</h1>
                <h2>Login Verification Code</h2>
              </div>
              
              <p class="info">Hello,</p>
              <p class="info">You have requested to log in to your HomeSync account. Please use the verification code below:</p>
              
              <div class="otp-box">
                <p style="margin: 0; color: #666; font-size: 14px;">Your OTP Code</p>
                <p class="otp-code">$otp</p>
              </div>
              
              <div class="warning">
                <strong>⏱️ Important:</strong> This code will expire in <strong>5 minutes</strong>. 
                You can request a new code after <strong>30 seconds</strong>.
              </div>
              
              <p class="info">
                If you didn't request this code, please ignore this email and ensure your account is secure.
              </p>
              
              <div class="footer">
                <p>This is an automated message from HomeSync.</p>
                <p>Please do not reply to this email.</p>
                <p>&copy; 2025 HomeSync. All rights reserved.</p>
              </div>
            </div>
          </body>
          </html>
        ''';

      // Send email
      final sendReport = await send(message, smtpServer);
      print('Email sent: ${sendReport.toString()}');
    } on MailerException catch (e) {
      print('Email sending failed: ${e.message}');
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
      throw Exception('Failed to send email: ${e.message}');
    } catch (e) {
      print('Unexpected error sending email: $e');
      throw Exception('Failed to send email: ${e.toString()}');
    }
  }

  // Verify OTP
  Future<bool> verifyOTP(String userId, String enteredOTP) async {
    try {
      final otpDoc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('otp_verification')
              .doc('current')
              .get();

      if (!otpDoc.exists) {
        throw Exception('No OTP found. Please request a new one.');
      }

      final otpData = otpDoc.data()!;
      final storedOTP = otpData['otp'] as String;
      final expiryTime = (otpData['expiryTime'] as Timestamp).toDate();
      final isUsed = otpData['isUsed'] as bool;

      // Check if OTP is already used
      if (isUsed) {
        throw Exception(
          'This OTP has already been used. Please request a new one.',
        );
      }

      // Check if OTP is expired
      if (DateTime.now().isAfter(expiryTime)) {
        throw Exception('OTP has expired. Please request a new one.');
      }

      // Verify OTP
      if (storedOTP == enteredOTP) {
        // Mark OTP as used
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('otp_verification')
            .doc('current')
            .update({'isUsed': true});

        print(' OTP verified successfully');
        return true;
      } else {
        print('Invalid OTP entered');
        return false;
      }
    } catch (e) {
      print('Error verifying OTP: $e');
      throw Exception(e.toString());
    }
  }

  // Check if user can request new OTP (30 seconds cooldown)
  Future<bool> canRequestNewOTP(String userId) async {
    try {
      final otpDoc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('otp_verification')
              .doc('current')
              .get();

      if (!otpDoc.exists) {
        return true; // No previous OTP, can request
      }

      final createdAt = (otpDoc.data()!['createdAt'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(createdAt);

      return difference.inSeconds >= 30; // 30 seconds cooldown
    } catch (e) {
      print('Error checking OTP cooldown: $e');
      return true; // Allow request on error
    }
  }

  // Get remaining cooldown seconds
  Future<int> getRemainingCooldownSeconds(String userId) async {
    try {
      final otpDoc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('otp_verification')
              .doc('current')
              .get();

      if (!otpDoc.exists) {
        return 0;
      }

      final createdAt = (otpDoc.data()!['createdAt'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(createdAt);
      final remaining = 30 - difference.inSeconds;

      return remaining > 0 ? remaining : 0;
    } catch (e) {
      print('Error getting cooldown seconds: $e');
      return 0;
    }
  }

  // Clean up expired OTPs (optional, can be called periodically)
  Future<void> cleanupExpiredOTPs(String userId) async {
    try {
      final otpDocs =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('otp_verification')
              .get();

      for (var doc in otpDocs.docs) {
        final data = doc.data();
        final expiryTime = (data['expiryTime'] as Timestamp).toDate();

        if (DateTime.now().isAfter(expiryTime)) {
          await doc.reference.delete();
          print('🗑️ Deleted expired OTP');
        }
      }
    } catch (e) {
      print('Error cleaning up expired OTPs: $e');
    }
  }
}
