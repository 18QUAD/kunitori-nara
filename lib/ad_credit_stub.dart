import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AdCredit extends StatelessWidget {
  const AdCredit({super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap:
        () => launchUrl(
          Uri.parse('https://developers.rakuten.com/'),
          mode: LaunchMode.externalApplication,
        ),
    child: const Text(
      'Supported by Rakuten Developers',
      style: TextStyle(color: Color(0xFF72582A), fontSize: 9),
    ),
  );
}
