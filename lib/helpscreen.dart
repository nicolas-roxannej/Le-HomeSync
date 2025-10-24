import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 50,
                      color: Colors.black,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'HELP CENTER',
                    style: GoogleFonts.jaldi(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Welcome Card
            _buildWelcomeCard(),
            
            const SizedBox(height: 20),
            
            // Help Topics Section
            Text(
              'Help Topics',
              style: GoogleFonts.jaldi(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Getting Started
            _buildHelpCard(
              context,
              title: 'Getting Started',
              onTap: () => _showHelpDialog(
                context,
                'Getting Started',
                _getGettingStartedText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Profile & Navigation
            _buildHelpCard(
              context,
              title: 'Profile & Navigation',
              onTap: () => _showHelpDialog(
                context,
                'Profile & Navigation',
                _getProfileNavigationText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Device Management
            _buildHelpCard(
              context,
              title: 'Device Management',
              onTap: () => _showHelpDialog(
                context,
                'Device Management',
                _getDeviceManagementText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Rooms Management
            _buildHelpCard(
              context,
              title: 'Rooms Management',
              onTap: () => _showHelpDialog(
                context,
                'Rooms Management',
                _getRoomsManagementText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Electricity Dashboard
            _buildHelpCard(
              context,
              title: 'Electricity Dashboard',
              onTap: () => _showHelpDialog(
                context,
                'Electricity Dashboard',
                _getElectricityDashboardText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Notifications
            _buildHelpCard(
              context,
              title: 'Notifications',
              onTap: () => _showHelpDialog(
                context,
                'Notifications',
                _getNotificationsText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Alarm & Scheduling
            _buildHelpCard(
              context,
              title: 'Alarm & Scheduling',
              onTap: () => _showHelpDialog(
                context,
                'Alarm & Scheduling',
                _getAlarmSchedulingText(),
              ),
            ),
            
            const SizedBox(height: 12),
            
            const SizedBox(height: 30),
            
            // Support Section
            _buildSupportSection(),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.help_rounded,
            size: 50,
            color: Colors.black,
          ),
          const SizedBox(height: 12),
          Text(
            'HomeSync Help Center',
            style: GoogleFonts.jaldi(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your quick guide to navigating and using all the features of the HomeSync Home Automation App.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: Colors.black, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 3,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            const Icon(Icons.chevron_right, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'Need More Help?',
                style: GoogleFonts.jaldi(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'If you experience issues or have suggestions, you can reach out to our support team.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              const Icon(Icons.email, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'mrldtechsolutions.support@gmail.com',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Text(
            'We\'re always happy to assist you in keeping your home smart, safe, and energy efficient.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context, String title, String content) {
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
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildHelpContent(content),
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

  Widget _buildHelpContent(String content) {
    List<String> sections = content.split('\n\n');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.asMap().entries.map((entry) {
        int index = entry.key;
        String section = entry.value.trim();
        
        if (section.isEmpty) return SizedBox.shrink();
        
        // Check if it's a heading (starts with number followed by period)
        bool isNumberedHeading = RegExp(r'^\d+\.').hasMatch(section);
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0 && isNumberedHeading) 
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  height: 1,
                  color: Colors.black.withOpacity(0.1),
                ),
              ),
            
            Text(
              section.replaceAll('**', ''),
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 3,
              ),
            ),
            
            if (index < sections.length - 1 && !isNumberedHeading)
              const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  String _getGettingStartedText() {
    return '''1. Splash & Welcome Screen

When you first open HomeSync, you'll be greeted by our splash screen featuring the logo, followed by the main Welcome Page.

From here, you have two simple options to get started: Log In to your existing account or Sign Up to create a new one.

2. Create Your Account (Sign Up)


Ready to get started? Fill in the required details: your Email, unique Username, House Address, and a secure Password.

Once everything looks right, just tap Create Account.

Pro-Tip: Before you agree, please take a moment to review the End User License Agreement (EULA), Terms of Use, and Privacy Policy. Your trust and security are important to us!

3. Access Your Account (Log In)

To securely access your HomeSync dashboard, simply enter your registered Email and Password.

Forgot your password? No problem! Tap the Forgot Password link right below the login fields to quickly and easily reset it.''';
  }

  String _getProfileNavigationText() {
    return '''1. Your Profile Page
This is your personal hub. Easily manage your account by accessing your personal information, changing your display name, or updating your password anytime.

2. The Navigation Menu (Flyout)
Tap the house menu icon to open the Navigation Flyout. This side menu gives you quick access to the main areas of the app:


Profile: Manage your personal settings and account details.

Notifications: Review all recent alerts and activity.

About: Learn more about the HomeSync app version.

Help Center: Get support or find answers to your questions.

Log Out: Securely exit your HomeSync session.''';
  }

  String _getDeviceManagementText() {
    return '''
1. Seamlessly Add a Device

Easily connect a new appliance or gadget to your HomeSync system with these simple steps:

• Tap the Add Device (+) button

• Provide the essential details: the Appliance Name, its Wattage, and Assign a room for organization.

• Select the device type (e.g., socket or light).

• Set an automatic alarm (optional) to receive alerts based on its status.

• Tap Save. Your new device will instantly appear on the Devices page, ready to be controlled!

2. Device Control Page

This is where you take command! Manage each connected appliance directly and efficiently:

• Turn devices On/Off remotely.

• View real-time energy usage for each one.

• Rename or delete devices anytime.''';
  }

  String _getRoomsManagementText() {
    return '''1. Organize with Rooms
Create virtual rooms to organize your devices logically and make control effortless. Whether it's the Living Room, Kitchen, or Bedroom, each room holds its own set of appliances.
To add a new room:

• Tap the Add Room (+) button.
• Enter the room name (e.g., Master Bedroom).
• Tap Save.

    2.Rooms Page
This central page clearly displays all the rooms you've created within your home.
To view and control everything inside, simply tap on any room name. This instantly gives you access to the status and controls for all the devices assigned there.
    ''';
  }

  String _getElectricityDashboardText() {
    return '''The HomeSync Dashboard: Your Energy Hub The Dashboard is your control center, providing a powerful overview of your total energy usage and consumption trends.
Easily switch between Daily, Weekly, Monthly, and Yearly summaries to monitor precisely how your home consumes electricity over time.

What You Can Monitor:
Energy Usage Graph (kWh): A visual representation of your consumption patterns.

Estimated Cost: See the financial impact of your energy use.

Device Breakdown: A list of devices ranked by their individual power consumption.

Time Period Comparison: Benchmark your current usage against previous periods to track savings.

Power User Tip:
Regularly checking your Dashboard is key to savings! Use the device breakdown feature to instantly spot which appliances use the most power, allowing you to easily adjust your habits and dramatically lower your energy bill.''';
  }

  String _getNotificationsText() {
    return '''Stay instantly informed about everything happening in your smart home. HomeSync sends you timely alerts regarding:Device Activity: Get pinged immediately when a device turns On or Off.System Health: Stay up-to-date with essential System Updates and maintenance.Energy Insights: Receive critical Energy Alerts about unusual or unexpected consumption patterns.Customize Your Alerts: You have full control! Manage precisely which notifications you receive by navigating to Settings Notification Settings.''';
  }

  String _getAlarmSchedulingText() {
    return '''Use the powerful Alarm feature to create convenient schedules or timers for any of your devices, automating your routine and saving energy.

For example, you can schedule the system to automatically turn off the lights at 11:00 PM or start the fan every morning before you wake up. HomeSync handles the rest!

How to Create a Schedule:
Go to the Alarm section of the app.

Select a device and set the desired time for the action (e.g., On at 7:00 AM).

Save the schedule.

Once saved, your smart device will execute the action automatically, without any further input from you.''';
  }
}