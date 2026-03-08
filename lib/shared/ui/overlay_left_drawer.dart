import 'package:flutter/material.dart';

class OverlayLeftDrawer extends StatelessWidget {
  const OverlayLeftDrawer({
    super.key,
    this.visible = false,
    required this.child,
    this.width = 280,
    this.onDismiss,
    this.isOpen = false,
    this.topOffset = 0,
    this.drawerLeftOffset = 0,
    this.tabTopOffset = 0,
    this.tabLeftOffset = 0,
    this.showScrim = false,
    this.onScrimTap,
    this.tab,
  });

  final bool visible;
  final Widget child;
  final double width;
  final VoidCallback? onDismiss;
  final bool isOpen;
  final double topOffset;
  final double drawerLeftOffset;
  final double tabTopOffset;
  final double tabLeftOffset;
  final bool showScrim;
  final VoidCallback? onScrimTap;
  final Widget? tab;

  @override
  Widget build(BuildContext context) {
    final show = visible || isOpen;
    return Stack(
      children: [
        if (show && showScrim)
          Positioned.fill(
            child: GestureDetector(
              onTap: onScrimTap ?? onDismiss,
              child: Container(color: Colors.black26),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          left: show ? drawerLeftOffset : -width,
          top: topOffset,
          bottom: 0,
          width: width,
          child: Material(
            elevation: show ? 8 : 0,
            child: child,
          ),
        ),
        if (tab != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: tabLeftOffset,
            top: tabTopOffset,
            child: tab!,
          ),
      ],
    );
  }
}
