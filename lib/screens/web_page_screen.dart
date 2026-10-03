import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/config.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Shows a page of the BudgetMate website (Privacy Policy, Terms, Impressum …) inside
/// the app, so the reviewed legal text keeps a single source of truth. Links to other
/// sites open in the phone's browser.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.path, required this.title});
  final String path; // e.g. "/privacy" or "/privacy#ai"
  final String title;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  WebViewController? _controller;
  int _progress = 0;
  bool _failed = false;

  Uri get _url => Uri.parse('$siteUrl${widget.path}');

  @override
  void initState() {
    super.initState();
    if (siteUrl.isEmpty) return;
    final siteHost = Uri.parse(siteUrl).host;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // the website is a React app
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onPageStarted: (_) => mounted ? setState(() => _failed = false) : null,
        onWebResourceError: (e) {
          debugPrint('[web] ${e.errorType} ${e.errorCode} ${e.description} main=${e.isForMainFrame} ${e.url}');
          // Only a failed page load counts; a broken image or script shouldn't blank the page
          if ((e.isForMainFrame ?? true) && mounted) setState(() => _failed = true);
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || uri.host == siteHost || uri.scheme == 'about') return NavigationDecision.navigate;
          launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(_url);
  }

  Future<void> _back() async {
    // Go back inside the site first (e.g. Privacy → a linked page), then leave the screen
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else if (mounted) {
      context.canPop() ? context.pop() : context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.paper,
        appBar: AppBar(
          backgroundColor: c.card,
          leading: IconButton(icon: Icon(LucideIcons.arrowLeft, color: c.ink), tooltip: 'Back', onPressed: _back),
          title: Text(widget.title, style: inter(size: FontSizes.lg, weight: FontWeight.w600, color: c.ink)),
          actions: [
            if (_controller != null)
              IconButton(
                icon: Icon(LucideIcons.externalLink, size: 20, color: c.ink),
                tooltip: 'Open in browser',
                onPressed: () => launchUrl(_url, mode: LaunchMode.externalApplication),
              ),
          ],
          shape: Border(bottom: BorderSide(color: c.border)),
          bottom: _controller != null && _progress < 100 && !_failed
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: c.ink, backgroundColor: c.newsLight),
                )
              : null,
        ),
        body: _body(c),
      ),
    );
  }

  Widget _body(AppColors c) {
    if (_controller == null) {
      return _message(c, 'This page is available on the BudgetMate website.', null);
    }
    if (_failed) {
      return _message(c, "Couldn't load this page. Check your connection and try again.", () {
        setState(() => _failed = false);
        _controller!.loadRequest(_url);
      });
    }
    return WebViewWidget(controller: _controller!);
  }

  Widget _message(AppColors c, String text, VoidCallback? onRetry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
            Icon(LucideIcons.globe, size: 40, color: c.news),
            Text(text, textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: c.news)),
            if (onRetry != null) AppButton(onPressed: onRetry, label: 'Retry', radius: Radii.md),
          ]),
        ),
      );
}
