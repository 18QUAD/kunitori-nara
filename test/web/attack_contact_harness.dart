import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:kunitori/attack_button_web.dart';

void main() => runApp(const MaterialApp(home: ContactHarness()));

class ContactHarness extends StatefulWidget {
  const ContactHarness({super.key});
  @override
  State<ContactHarness> createState() => _ContactHarnessState();
}

class _ContactHarnessState extends State<ContactHarness> {
  int taps = 0;
  bool enabled = true;
  web.HTMLButtonElement? toggle;

  @override
  void initState() {
    super.initState();
    toggle = web.HTMLButtonElement()..id = 'harness-toggle';
    toggle!.textContent = 'toggle';
    toggle!.style.cssText = 'position:absolute;top:0;left:0;z-index:100';
    toggle!.addEventListener(
      'click',
      ((web.Event _) {
        setState(() => enabled = !enabled);
      }).toJS,
    );
    web.document.body!.append(toggle!);
    web.document.body!.setAttribute('data-taps', '0');
  }

  @override
  void dispose() {
    toggle?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 160,
        height: 160,
        child: protectAttackTap(
          onPressed:
              enabled
                  ? () {
                    web.document.body!.setAttribute('data-taps', '${++taps}');
                    setState(() {});
                  }
                  : null,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}
