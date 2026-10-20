import 'package:flutter/material.dart';
import 'package:spendwise/features/settings/legal_text.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = kind == 'privacy';
    return Scaffold(
      appBar: AppBar(
        title: Text(isPrivacy ? 'Privacy policy' : 'Terms of service'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            isPrivacy ? kPrivacyPolicyText : kTermsText,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.45),
          ),
        ),
      ),
    );
  }
}
