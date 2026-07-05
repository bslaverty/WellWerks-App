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
            title: 'About WellWerks',
            subtitle: 'App summary, version, and local-data notice',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          _NavigationTile(
            icon: Icons.support_agent,
            title: 'Support',
            subtitle: 'Contact, feedback, bug reports, and app info',
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
      appBar: const AppHeader(title: 'About', showBack: true),
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
                    'WellWerks',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Field-ready flowback and production tools for oilfield crews.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  _infoRow('Version', _versionLabel),
                  _infoRow('Storage', 'Local-only data on this device'),
                  _infoRow('Copyright', '© 2026 WellWerks'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'WellWerks keeps active jobs, history, production records, JSAs, and layouts on-device. No cloud sync is enabled in this build.',
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
  static const _supportEmail = 'support@wellwerks.app';

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
                    'Support Contact',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'For support, feedback, or bug reports, use the placeholder email below for this build.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    _supportEmail,
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(
                        _supportEmail,
                        'Support email copied.',
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Support Email'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _sectionTile(
            icon: Icons.support_agent,
            title: 'Contact Support',
            subtitle: 'Copy the support email and app version details',
            onTap: () => _copy(
              '$_supportEmail\nSubject: WellWerks Support Request\nVersion: $_versionLabel',
              'Support request details copied.',
            ),
          ),
          _sectionTile(
            icon: Icons.lightbulb_outline,
            title: 'Feedback',
            subtitle: 'Copy a feedback template with app version info',
            onTap: () => _copy(
              '$_supportEmail\nSubject: WellWerks Feedback\nVersion: $_versionLabel',
              'Feedback details copied.',
            ),
          ),
          _sectionTile(
            icon: Icons.bug_report_outlined,
            title: 'Bug Report',
            subtitle: 'Copy a bug-report template with version details',
            onTap: () => _copy(
              '$_supportEmail\nSubject: WellWerks Bug Report\nVersion: $_versionLabel',
              'Bug report details copied.',
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
                  const SizedBox(height: 6),
                  const Text(
                    'This TestFlight build stores operational data locally on-device.',
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
