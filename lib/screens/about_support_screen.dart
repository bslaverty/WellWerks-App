import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/app_header.dart';

class AboutSupportScreen extends StatelessWidget {
  const AboutSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'About & Support', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'App information and support tools for TestFlight builds.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _NavigationTile(
            icon: Icons.info_outline,
            title: 'About WellWerks Toolbox',
            subtitle: 'App summary, features, developer, and version',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          _NavigationTile(
            icon: Icons.support_agent,
            title: 'Support',
            subtitle: 'Developer contact and support details',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '--';
  String _build = '--';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
    });
  }

  String get _versionLabel => _build == '--' ? _version : '$_version ($_build)';

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'About WellWerks Toolbox', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WellWerks Toolbox',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Professional Oilfield Operations Toolkit',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  _infoRow('Developer', 'Brendan Laverty'),
                  _infoRow('Version', _versionLabel),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'WellWerks Toolbox is a field-ready mobile application designed for flowback, production, and well-testing professionals.\n\nThe app combines production reporting, text updates, engineering calculators, layout design, JSA management, history, charts, and field tools into one simple, powerful application that helps crews work faster, more accurately, and more consistently.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Features',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 12),
                  _FeatureBullet('Production Reports'),
                  _FeatureBullet('Text Updates'),
                  _FeatureBullet('Layout Designer'),
                  _FeatureBullet('Rate Calculator'),
                  _FeatureBullet('Bottoms Up Calculator'),
                  _FeatureBullet('Gas Accum Calculator'),
                  _FeatureBullet('Multiple Choke Calculator'),
                  _FeatureBullet('Tank Charts'),
                  _FeatureBullet('History'),
                  _FeatureBullet('JSA'),
                  _FeatureBullet('Field Utilities'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '© 2026 Brendan Laverty\nAll Rights Reserved.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const _developerName = 'Brendan Laverty';
  static const _supportEmail = 'bslaverty@gmail.com';
  static const _supportPhone = '(405) 205-3080';

  String _version = '--';
  String _build = '--';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
    });
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _versionLabel => _build == '--' ? _version : '$_version ($_build)';

  Widget _sectionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFCDA56A)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Support', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Support',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _infoRow('Developer', _developerName),
                  _infoRow('Email', _supportEmail),
                  _infoRow('Phone', _supportPhone),
                  const SizedBox(height: 10),
                  const Text(
                    'Questions, bug reports, feature requests, or suggestions are welcome.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  _infoRow('Email', _supportEmail),
                  _infoRow('Phone', _supportPhone),
                ],
              ),
            ),
          ),
          _sectionTile(
            icon: Icons.mail_outline,
            title: 'Copy Email',
            subtitle: _supportEmail,
            onTap: () => _copy(
              _supportEmail,
              'Support email copied.',
            ),
          ),
          _sectionTile(
            icon: Icons.phone_outlined,
            title: 'Copy Phone',
            subtitle: _supportPhone,
            onTap: () => _copy(
              _supportPhone,
              'Support phone copied.',
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Info',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Version: $_versionLabel'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text(
              '• ',
              style: TextStyle(
                color: Color(0xFFCDA56A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String _version = '--';
  String _build = '--';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
    });
  }

  String get _versionLabel => _build == '--' ? _version : '$_version ($_build)';

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFCDA56A))),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Privacy Policy', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Privacy Overview',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'WellWerks Toolbox is designed for local, on-device use.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  _bullet(
                      'Data collected: job setup, active job records, production shifts, JSAs, layouts, history, and app settings stored locally on this device.'),
                  _bullet('No cloud synchronization is enabled at this time.'),
                  _bullet(
                      'Exported job packages are written under the user\'s control and can be shared or saved locally.'),
                  _bullet(
                      'Future privacy information and website links can be added here before public release.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Details',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Version: $_versionLabel'),
                  const SizedBox(height: 6),
                  const Text(
                    'Website / privacy URL: placeholder for future release',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFCDA56A))),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Terms of Use', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tool Disclaimer',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'WellWerks Toolbox is an informational and workflow support tool. It does not replace site procedures, engineering judgment, or field supervision.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 18),
                  _bullet(
                      'Users remain responsible for operational decisions, calculations, and verification of field data.'),
                  _bullet(
                      'No warranty is provided, express or implied, to the fullest extent permitted by law.'),
                  _bullet(
                      'All information should be reviewed before being used for operational decisions.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '© 2026 WellWerks Toolbox',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFCDA56A)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        onTap: onTap,
      ),
    );
  }
}
