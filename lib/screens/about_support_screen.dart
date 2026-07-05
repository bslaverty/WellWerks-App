import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/app_header.dart';

class AboutSupportScreen extends StatefulWidget {
  const AboutSupportScreen({super.key});

  @override
  State<AboutSupportScreen> createState() => _AboutSupportScreenState();
}

class _AboutSupportScreenState extends State<AboutSupportScreen> {
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

  Future<void> _showPlaceholder(String title, String body) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
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
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'About & Support', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WellWerks',
                    style: TextStyle(
                      color: Color(0xFFCDA56A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Version: $_version'),
                  Text('Build: $_build'),
                  const SizedBox(height: 8),
                  const Text(
                    'Support Email: support@wellwerks.example',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          _actionTile(
            icon: Icons.bug_report_outlined,
            title: 'Report Bug',
            subtitle: 'Copy bug-report support details',
            onTap: () => _copy(
              'support@wellwerks.example\nSubject: WellWerks Bug Report\nVersion: $_version ($_build)',
              'Bug report details copied.',
            ),
          ),
          _actionTile(
            icon: Icons.lightbulb_outline,
            title: 'Feature Request',
            subtitle: 'Copy feature-request support details',
            onTap: () => _copy(
              'support@wellwerks.example\nSubject: WellWerks Feature Request\nVersion: $_version ($_build)',
              'Feature request details copied.',
            ),
          ),
          _actionTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'Placeholder policy text',
            onTap: () => _showPlaceholder(
              'Privacy Policy',
              'Privacy Policy placeholder. Replace with your final policy before App Store submission.',
            ),
          ),
          _actionTile(
            icon: Icons.description_outlined,
            title: 'Terms of Use',
            subtitle: 'Placeholder terms text',
            onTap: () => _showPlaceholder(
              'Terms of Use',
              'Terms of Use placeholder. Replace with your final terms before App Store submission.',
            ),
          ),
        ],
      ),
    );
  }
}
