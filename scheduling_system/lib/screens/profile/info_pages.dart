// screens/profile/info_pages.dart
//
// The Support & Legal pages opened from the guard Profile tab (all
// roles): Privacy Policy, Terms of Service, Help & Support and About
// Sched. All content is static and lives here.
import 'package:flutter/material.dart';

const Color _kBlue = Color(0xFF1034A6);
const Color _kInk = Color(0xFF1E293B);

void openPrivacyPolicy(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => _privacyPolicyPage()),
  );
}

void openTermsOfService(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => _termsOfServicePage()),
  );
}

void openHelpSupport(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => _helpSupportPage()),
  );
}

void openAboutSched(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const AboutSchedScreen()),
  );
}

// --- Page contents ---------------------------------------------------------

InfoPageScreen _privacyPolicyPage() {
  return const InfoPageScreen(
    title: 'Privacy Policy',
    tagline: 'Last updated July 2026',
    sections: [
      InfoSection(
        icon: Icons.person_outline,
        heading: 'Information We Collect',
        paragraphs: [
          'Sched stores the details your agency needs to schedule and '
              'manage security personnel:',
        ],
        bullets: [
          'Your name, employee ID and role (Regular, Reliever or Head Guard)',
          'Contact details — email address and phone number',
          'Station assignments, shift schedules and preferred stations',
          'Attendance records submitted by your head guard',
        ],
      ),
      InfoSection(
        icon: Icons.tune,
        heading: 'How Your Information Is Used',
        bullets: [
          'Generating and publishing duty schedules',
          'Recording daily attendance and arranging replacements for absences',
          'Sending you alerts such as duty calls and schedule updates',
          'Letting administrators contact you about your duties',
        ],
        paragraphs: [
          'Your information is used only to run the scheduling operation. '
              'It is never sold or shared outside your agency.',
        ],
      ),
      InfoSection(
        icon: Icons.lock_outline,
        heading: 'Data Storage & Security',
        paragraphs: [
          'Your records are kept in a secured cloud database that only '
              'your agency\'s administrators can access.',
          'Sign-in is handled by a dedicated authentication service. '
              'Administrators cannot see the password you set for yourself.',
        ],
      ),
      InfoSection(
        icon: Icons.fact_check_outlined,
        heading: 'Your Rights',
        bullets: [
          'Review the personal information shown in your Profile at any time',
          'Ask an administrator to correct outdated details such as your '
              'phone number',
          'Change your password anytime from Settings → Change Password',
        ],
        paragraphs: [
          'For any privacy concern, contact your scheduling administrator.',
        ],
      ),
    ],
  );
}

InfoPageScreen _termsOfServicePage() {
  return const InfoPageScreen(
    title: 'Terms of Service',
    tagline: 'Last updated July 2026',
    sections: [
      InfoSection(
        icon: Icons.gavel_outlined,
        heading: 'Acceptance of Terms',
        paragraphs: [
          'Sched is provided by your security agency to organize station '
              'duty schedules. By signing in you agree to use the app '
              'according to these terms and your agency\'s policies.',
        ],
      ),
      InfoSection(
        icon: Icons.badge_outlined,
        heading: 'Your Account',
        bullets: [
          'Your username and password are personal — never share them '
              'with anyone',
          'You are responsible for actions taken with your account',
          'Report a lost device or suspected unauthorized access to your '
              'administrator immediately',
        ],
      ),
      InfoSection(
        icon: Icons.rule_outlined,
        heading: 'Proper Use',
        bullets: [
          'Treat the published schedule as the official reference for '
              'your duties',
          'Head guards must report attendance truthfully and accurately',
          'Do not attempt to alter schedules or records you are not '
              'authorized to change',
        ],
      ),
      InfoSection(
        icon: Icons.event_available_outlined,
        heading: 'Schedules & Attendance',
        paragraphs: [
          'Published schedules are official duty assignments. If you '
              'cannot report for duty, inform your head guard or '
              'administrator as early as possible so a reliever can be '
              'arranged.',
          'Attendance reports are final once submitted and are used for '
              'replacement decisions and record keeping.',
        ],
      ),
      InfoSection(
        icon: Icons.update_outlined,
        heading: 'Changes to the Service',
        paragraphs: [
          'Your agency may update Sched and these terms from time to '
              'time. Accounts of personnel who leave the agency are '
              'deactivated by the administrator.',
        ],
      ),
    ],
  );
}

InfoPageScreen _helpSupportPage() {
  return const InfoPageScreen(
    title: 'Help & Support',
    tagline: 'Answers to common questions',
    sections: [
      InfoSection(
        icon: Icons.calendar_month_outlined,
        heading: 'My schedule is empty',
        paragraphs: [
          'You only see schedules the admin has published. Pull down on '
              'the Dashboard or Schedule tab to refresh. If it is still '
              'empty, the upcoming period may not be published yet — '
              'check with your administrator.',
        ],
      ),
      InfoSection(
        icon: Icons.swap_horiz_outlined,
        heading: 'My station or shift looks wrong',
        paragraphs: [
          'Station and shift assignments are managed by the scheduling '
              'administrator. If something looks wrong, tell your head '
              'guard or the admin office so it can be corrected.',
        ],
      ),
      InfoSection(
        icon: Icons.lock_outline,
        heading: 'I forgot my password',
        paragraphs: [
          'Ask your administrator to reset your password, then sign in '
              'with the new one and set your own from Settings → Change '
              'Password. On your very first sign-in, use the '
              'auto-generated password you were given.',
        ],
      ),
      InfoSection(
        icon: Icons.assignment_outlined,
        heading: 'Submitting the attendance report (Head Guards)',
        paragraphs: [
          'Open the Report tab, pick the shift you cover, mark anyone '
              'absent, then press Submit. Each shift\'s report can only '
              'be submitted once — review it before confirming.',
        ],
      ),
      InfoSection(
        icon: Icons.notifications_active_outlined,
        heading: 'Sudden duty calls (Relievers)',
        paragraphs: [
          'When the admin assigns you to cover an absence, the duty call '
              'appears in your Alerts tab and your schedule updates '
              'automatically. Keep notifications turned on so you never '
              'miss one.',
        ],
      ),
      InfoSection(
        icon: Icons.support_agent_outlined,
        heading: 'Still need help?',
        paragraphs: [
          'Contact your scheduling administrator or head office. Keep '
              'your employee ID ready so they can find your record '
              'quickly.',
        ],
      ),
    ],
  );
}

// --- Generic sectioned info page -------------------------------------------

class InfoSection {
  final IconData icon;
  final String heading;
  final List<String> paragraphs;
  final List<String> bullets;

  const InfoSection({
    required this.icon,
    required this.heading,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class InfoPageScreen extends StatelessWidget {
  final String title;
  final String tagline;
  final List<InfoSection> sections;

  const InfoPageScreen({
    super.key,
    required this.title,
    required this.tagline,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ...sections.map(_buildSectionCard),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1034A6),
            Color(0xFF1E4AD0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Balances the back button so the title sits centred.
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSectionCard(InfoSection section) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(section.icon, color: _kBlue, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.heading,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final paragraph in section.paragraphs) ...[
            Text(
              paragraph,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    decoration: const BoxDecoration(
                      color: _kBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.5,
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
}

// --- About Sched -----------------------------------------------------------

class AboutSchedScreen extends StatelessWidget {
  const AboutSchedScreen({super.key});

  static const List<(IconData, String, String)> _features = [
    (
      Icons.auto_awesome_outlined,
      'Automatic scheduling',
      'Fair bi-weekly duty schedules generated for every station.',
    ),
    (
      Icons.assignment_turned_in_outlined,
      'Attendance reporting',
      'Head guards file per-shift attendance straight from their phone.',
    ),
    (
      Icons.swap_horiz_outlined,
      'Fast replacements',
      'Absences are covered by ranked reliever suggestions in seconds.',
    ),
    (
      Icons.notifications_active_outlined,
      'Duty alerts',
      'Duty calls and schedule updates land right in your Alerts tab.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1034A6),
                    Color(0xFF1E4AD0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'About Sched',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Balances the back button so the title sits centred.
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Image.asset(
                      'assets/logo/kaizen_logo.png',
                      width: 88,
                      height: 88,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Sched',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _kInk,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kBlue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Sched keeps station security teams organized — from '
                    'generating duty schedules and tracking attendance to '
                    'covering absences with relievers, all in one place.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        for (final feature in _features) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _kBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  feature.$1,
                                  color: _kBlue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      feature.$2,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _kInk,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      feature.$3,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (feature != _features.last)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(height: 1),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      '© 2026 Sched · Built for station security teams',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
