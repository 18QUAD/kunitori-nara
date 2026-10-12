import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class AdCredit extends StatelessWidget {
  const AdCredit({super.key});
  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'span',
    onElementCreated: (element) {
      final span = element as web.HTMLElement;
      span.style.cssText =
          'display:block;font:9px sans-serif;line-height:14px;';
      // Rakuten's required attribution snippet, unmodified.
      span.innerHTML =
          ('<!-- Rakuten Web Services Attribution Snippet FROM HERE -->'
                  '<a href="https://developers.rakuten.com/" target="_blank">Supported by Rakuten Developers</a>'
                  '<!-- Rakuten Web Services Attribution Snippet TO HERE -->')
              .toJS;
    },
  );
}
