import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

const _legalTitles = {'/privacy': 'Privacy Policy', '/terms': 'Terms', '/imprint': 'Impressum'};

/// Opens one of the website's legal pages (/privacy, /terms, /imprint, optionally with
/// an #anchor) in the in-app web view (screens/web_page_screen.dart).
void openLegalPage(BuildContext context, String path) {
  final title = _legalTitles[path.split('#').first] ?? 'BudgetMate';
  context.push(Uri(path: '/legal', queryParameters: {'path': path, 'title': title}).toString());
}

/// Legal links + copyright (web: components/Footer.jsx). Mobile has no cookies,
/// so the web's "Cookie settings" link is not needed.
class Footer extends StatelessWidget {
  const Footer({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? context.colors.news;
    final style = inter(size: FontSizes.xs, color: textColor);
    Widget link(String label, String path) => InkWell(
          onTap: () => openLegalPage(context, path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(label, style: style),
          ),
        );
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 4, children: [
        link('Privacy Policy', '/privacy'),
        link('Impressum', '/imprint'),
        link('Terms', '/terms'),
      ]),
      const SizedBox(height: 8),
      Text('© ${DateTime.now().year} BudgetMate', style: style, textAlign: TextAlign.center),
    ]);
  }
}
