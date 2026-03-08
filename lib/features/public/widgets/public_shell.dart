import 'package:flutter/material.dart';

class PublicShell extends StatelessWidget {
  const PublicShell({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.title,
    this.subtitle,
    this.showBack = false,
    this.topRight,
    this.scrollableCard = false,
    this.showPoweredBy = false,
  });

  final Widget child;
  final double maxWidth;
  final String? title;
  final String? subtitle;
  final bool showBack;
  final Widget? topRight;
  final bool scrollableCard;
  final bool showPoweredBy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: (title != null || showBack)
          ? AppBar(
              automaticallyImplyLeading: showBack,
              title: title != null ? Text(title!) : null,
              actions: topRight != null ? [topRight!] : null,
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
      bottomNavigationBar: showPoweredBy
          ? const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Powered by KineticDx',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          : null,
    );
  }
}
