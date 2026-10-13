import 'package:flutter/material.dart';

import '../privacy_text.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacy policy')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: SelectableText(privacyPolicyText),
        ),
      );
}
