import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Back Button and Title
            Padding(
              padding: const EdgeInsets.only(left: 5, top: 65),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 22,
                        color: Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'ABOUT & LEGAL',
                    style: GoogleFonts.jaldi(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 35),
            
            // App Info Section
            _buildAppInfoCard(),
            
            const SizedBox(height: 30),
            
            // Legal Documents Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Legal Documents',
                style: GoogleFonts.jaldi(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
    
            _buildAgreementCard(
              context,
              title: 'About Us',
              icon: Icons.info_outline,
              onTap: () => _showAgreementDialog(
                context,
                'About Us',
                _getAboutUsText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // EULA Card
            _buildAgreementCard(
              context,
              title: 'End-User License Agreement',
              icon: Icons.description_outlined,
              onTap: () => _showAgreementDialog(
                context,
                'End-User License Agreement (EULA)',
                _getEULAText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Terms of Service Card
            _buildAgreementCard(
              context,
              title: 'Terms of Service',
              icon: Icons.gavel_outlined,
              onTap: () => _showAgreementDialog(
                context,
                'Terms of Service',
                _getTermsText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Privacy Policy Card
            _buildAgreementCard(
              context,
              title: 'Privacy Policy',
              icon: Icons.privacy_tip_outlined,
              onTap: () => _showAgreementDialog(
                context,
                'Privacy Policy',
                _getPrivacyText(),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Contact Section
            _buildContactSection(),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoCard() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 80),
            
            // App Name with gradient effect
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [Colors.black87, Colors.black54],
              ).createShader(bounds),
              child: Text(
                'HomeSync',
                style: GoogleFonts.jaldi(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Version Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E7E6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Version 1.0.0',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            const SizedBox(height: 14),
            
            Text(
              'Smart Home Management System',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE9E7E6).withOpacity(0.5),
                    const Color(0xFFE9E7E6).withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Developed by MRLD Tech Solutions',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        Positioned(
          top: -70,
          left: 0,
          right: 0,
          child: Center(
            child: Image.asset(
              'assets/homebg.png',
              height: 220,
              width: 220,
            ),
          ),
        ),
      ],
    ),
  );
}
  Widget _buildAgreementCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFE9E7E6),
                        const Color(0xFFE9E7E6).withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9E7E6).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildContactSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFE9E7E6),
                      const Color(0xFFE9E7E6).withOpacity(0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.contact_support_outlined,
                  size: 22,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Contact Information',
                style: GoogleFonts.jaldi(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE9E7E6).withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dasmariñas City, Cavite, Philippines',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE9E7E6).withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 20,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'mrldtechsolutions.support@gmail.com',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w500,
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
  
  void _showAgreementDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: BoxDecoration(
              color: const Color(0xFFE9E7E6),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Title with close icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.jaldi(
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            color: Colors.black87,
                            letterSpacing: 0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    physics: const BouncingScrollPhysics(),
                    child: _buildAgreementContent(content),
                  ),
                ),
                
                // Close Button
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white.withOpacity(0.95),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            alignment: Alignment.center,
                            child: Text(
                              'Close',
                              style: GoogleFonts.judson(
                                fontSize: 17,
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                section,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.6,
                  color: Colors.grey[800],
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _getAboutUsText() {
    return '''At MRLDTech, we believe that technology should make everyday living smarter, simpler, and more secure. Our mission is to bring the future of home automation into today's households by providing innovative IoT-based solutions that connect and  control our home devices with just a tap.''';
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

We may update these Terms from time to time to reflect changes in our business or legal requirements. When we do, we will revise the "Last Updated" date and may notify you through the App or email. Continued use of HomeSync after any update means you accept the new Terms.

13. CONTACT US

If you have questions, feedback, or requests related to these Terms, please contact us at: 

📍 Dasmariñas City, Cavite, Philippines
📧 mrldtechsolutions.support@gmail.com''';
  }

  String _getPrivacyText() {
    return '''PRIVACY NOTICE
Last updated: October 16, 2025

This Privacy Notice for MRLD Tech Solutions ("we," "us," or "our") explains how and why we collect, store, use, and share ("process") your personal information when you use our mobile application HomeSync.(the "App") and related services (the 
"Services"). 

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

Yes. We may update this Privacy Notice from time to time. When we do, we'll update the "Last updated" date and notify users in the App or via email if there are significant changes.

9. HOW CAN YOU REVIEW, UPDATE, OR DELETE YOUR DATA? 

To review, update, or delete your data collected through HomeSync, please email mrldtechsolutions.support@gmail.com We'll respond in accordance with applicable privacy laws.

10. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?

If you have questions, feedback, or requests regarding this Privacy Notice, you may contact us at: 

📍 Dasmariñas City, Cavite, Philippines
📧 mrldtechsolutions.support@gmail.com
''';
  }
}