import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spendwise/core/widgets/brand_mark.dart';
import 'package:spendwise/core/widgets/common.dart';
import 'package:url_launcher/url_launcher.dart';

/// Set at build time: --dart-define=SPENDWISE_SUPPORT_EMAIL=help@yourdomain.com
const String kSupportEmail = String.fromEnvironment('SPENDWISE_SUPPORT_EMAIL');

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const Center(child: BrandMark(size: 88)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'SpendWise',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Center(
            child: Text(
              'Know Your Money. Own Your Future.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                snap.hasData
                    ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})'
                    : '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SectionHeader('Support'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kSupportEmail.isEmpty) ...[
                  const Text('Support contact not configured in this build.'),
                  const SizedBox(height: 4),
                  Text(
                    'Developer: set SPENDWISE_SUPPORT_EMAIL at build time (see README).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...[
                  const Text(
                    'Questions, bugs or feedback? We read every message.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Email support'),
                    onPressed: () => launchUrl(
                      Uri(
                        scheme: 'mailto',
                        path: kSupportEmail,
                        queryParameters: {'subject': 'SpendWise support'},
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Please do not include financial details in support emails.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SectionHeader('Good to know'),
          const AppCard(
            child: Text(
              'SpendWise is a bookkeeping tool. It does not connect to banks, move money, or give financial advice. Balances and Safe-to-Spend are estimates based only on what you record.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                showLicensePage(context: context, applicationName: 'SpendWise'),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    );
  }
}
