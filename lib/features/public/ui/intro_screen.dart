// lib/features/public/ui/intro_screen.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_routes.dart';

/// ----------------------------------------------------------------------------
/// Clinic branding model (UI-only)
/// ----------------------------------------------------------------------------
class ClinicBranding {
  final String? clinicLogoAsset; // e.g. assets/fundamental_recovery.png
  final String poweredByText;
  final String? poweredByLogoAsset; // e.g. assets/kineticdx_logo.png
  final String sloganText;
  final String brandBodyText;
  final String bookButtonAsset; // assets/book_online.png
  final String priceButtonAsset; // assets/Price_List.png
  final Color navy;

  const ClinicBranding({
    this.clinicLogoAsset,
    this.poweredByText = 'Powered by ',
    this.poweredByLogoAsset,
    this.sloganText = 'Where Insight Meets Recovery',
    this.brandBodyText =
        'Begin the work. Build better movement.\nOne session at a time.\nThis will only take a few minutes.',
    this.bookButtonAsset = 'assets/book_online.png',
    this.priceButtonAsset = 'assets/Price_List.png',
    this.navy = const Color(0xFF0B1B3B),
  });

  static const ClinicBranding defaults = ClinicBranding(
    clinicLogoAsset: 'assets/fundamental_recovery.png',
    poweredByLogoAsset: 'assets/kineticdx_logo.png',
    sloganText: 'Where Insight Meets Recovery',
    brandBodyText:
        'Begin the work. Build better movement.\nOne session at a time.\nThis will only take a few minutes.',
    bookButtonAsset: 'assets/book_online.png',
    priceButtonAsset: 'assets/Price_List.png',
    navy: Color(0xFF0B1B3B),
  );

  ClinicBranding merge(ClinicBranding? other) {
    if (other == null) return this;
    return ClinicBranding(
      clinicLogoAsset: other.clinicLogoAsset ?? clinicLogoAsset,
      poweredByText: other.poweredByText,
      poweredByLogoAsset: other.poweredByLogoAsset ?? poweredByLogoAsset,
      sloganText: other.sloganText,
      brandBodyText: other.brandBodyText,
      bookButtonAsset: other.bookButtonAsset,
      priceButtonAsset: other.priceButtonAsset,
      navy: other.navy,
    );
  }
}

/// ----------------------------------------------------------------------------
/// Intro timeline:
/// 1) Video plays 6.5s
/// 2) Fade out video
/// 3) Message fades in, holds 3.0s, fades out
/// 4) Navigate to /public/home (BrandIntro)
///
/// IMPORTANT:
/// - Navigation MUST preserve clinicId (and corp) via query OR args.
/// - /public/home MUST be routed to PublicHomeScreen (NOT IntroScreen),
///   otherwise you'll loop the video.
/// ----------------------------------------------------------------------------
class IntroScreen extends StatefulWidget {
  static const String routeName = AppRoutes.publicIntro;

  final String? clinicId;
  final String? corporateCode;
  final ClinicBranding? brandingOverride;

  const IntroScreen({
    super.key,
    this.clinicId,
    this.corporateCode,
    this.brandingOverride,
  });

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  late final ClinicBranding _branding =
      ClinicBranding.defaults.merge(widget.brandingOverride);

  // Resolved context
  String? _clinicId;
  String? _corporateCode;
  String? _resolveError;

  // Opacity controls
  double _videoOpacity = 1.0;
  double _messageOpacity = 0.0;

  // Timing constants
  static const Duration _fade = Duration(milliseconds: 800);
  static const Duration _videoDuration = Duration(milliseconds: 6500);
  static const Duration _messageHold = Duration(milliseconds: 3000);
  static const Duration _smallGap = Duration(milliseconds: 120);

  Timer? _timelineTimer;

  // Cancellation token for async timeline
  int _timelineRunId = 0;

  bool get _canNavigate =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      _clinicId != null;

  void _cancelTimeline() {
    _timelineRunId++; // invalidates any running async timeline
    _timelineTimer?.cancel();
    _timelineTimer = null;
  }

  String _resolveClinicIdFromUrlOrArgsOrThrow() {
    final fromCorpWidget = (widget.corporateCode ?? '').trim();
    if (fromCorpWidget.isNotEmpty) _corporateCode = fromCorpWidget;

    final fromWidget = (widget.clinicId ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final aClinic = (args['clinicId'] ?? '').toString().trim();
      if (aClinic.isNotEmpty) {
        final aCorp = (args['corporateCode'] ?? '').toString().trim();
        if (aCorp.isNotEmpty) _corporateCode = aCorp;
        return aClinic;
      }

      final aCorp = (args['corporateCode'] ?? '').toString().trim();
      if (aCorp.isNotEmpty) _corporateCode = aCorp;
    }

    final qp = Uri.base.queryParameters;

    final c = (qp['c'] ?? qp['clinicId'] ?? '').trim();
    final corp =
        (qp['corp'] ?? qp['corporate'] ?? qp['corpCode'] ?? qp['code'] ?? '')
            .trim();

    if (corp.isNotEmpty) _corporateCode = corp;
    if (c.isNotEmpty) return c;

    throw StateError(
      'Missing clinicId. Open the public portal with ?c=<clinicId> (or pass clinicId as route args).',
    );
  }

  Map<String, dynamic> _routeArgs() {
    final out = <String, dynamic>{'clinicId': _clinicId!};
    final corp = (_corporateCode ?? '').trim();
    if (corp.isNotEmpty) out['corporateCode'] = corp;
    return out;
  }

  /// ✅ Build a named route string that preserves query params for web refresh/share.
  String _publicHomeRouteWithQuery() {
    final qp = <String, String>{};
    final c = (_clinicId ?? '').trim();
    final corp = (_corporateCode ?? '').trim();

    if (c.isNotEmpty) qp['c'] = c;
    if (corp.isNotEmpty) qp['corp'] = corp;

    return Uri(path: AppRoutes.publicHome, queryParameters: qp).toString();
  }

  void _goToPublicHome() {
    if (!_canNavigate) return;

    _cancelTimeline();

    Navigator.of(context).pushReplacementNamed(
      _publicHomeRouteWithQuery(),
      arguments: _routeArgs(),
    );
  }

  Future<void> _runTimeline(int runId) async {
    bool stillActive() =>
        mounted &&
        runId == _timelineRunId &&
        (ModalRoute.of(context)?.isCurrent ?? true);

    await Future.delayed(_videoDuration);
    if (!stillActive()) return;

    setState(() => _videoOpacity = 0.0);
    await Future.delayed(_fade + _smallGap);
    if (!stillActive()) return;

    setState(() => _messageOpacity = 1.0);
    await Future.delayed(_fade);
    if (!stillActive()) return;

    await Future.delayed(_messageHold);
    if (!stillActive()) return;

    setState(() => _messageOpacity = 0.0);
    await Future.delayed(_fade + _smallGap);
    if (!stillActive()) return;

    _goToPublicHome();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_clinicId != null || _resolveError != null) return;

    try {
      _clinicId = _resolveClinicIdFromUrlOrArgsOrThrow();

      _cancelTimeline();
      final runId = _timelineRunId;

      _timelineTimer = Timer(const Duration(milliseconds: 10), () {
        if (!mounted) return;
        _runTimeline(runId);
      });
    } catch (e) {
      _resolveError = e.toString();
    }
  }

  @override
  void deactivate() {
    _cancelTimeline();
    super.deactivate();
  }

  @override
  void dispose() {
    _cancelTimeline();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _branding;

    if (_resolveError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'Unable to open public portal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(_resolveError!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _videoOpacity,
            duration: _fade,
            child: _IntroVideo(
              assetPath: 'assets/intro_h264.mp4',
              onInitFailed: () {
                if (!mounted) return;
                setState(() => _videoOpacity = 0.0);
                _goToPublicHome();
              },
            ),
          ),
          IgnorePointer(
            ignoring: _messageOpacity == 0.0,
            child: AnimatedOpacity(
              opacity: _messageOpacity,
              duration: _fade,
              child: Container(
                color: Colors.white,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  b.sloganText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: b.navy,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: _goToPublicHome,
                child: const Text('Skip'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// Intro video widget (asset) — autoplay-safe for mobile browsers
/// ----------------------------------------------------------------------------
class _IntroVideo extends StatefulWidget {
  final String assetPath;
  final VoidCallback onInitFailed;

  const _IntroVideo({
    required this.assetPath,
    required this.onInitFailed,
  });

  @override
  State<_IntroVideo> createState() => _IntroVideoState();
}

class _IntroVideoState extends State<_IntroVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.asset(widget.assetPath);
    _controller = c;

    try {
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(0.0); // muted autoplay
      await c.play();

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      widget.onInitFailed();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.white);
    }

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// Public Home route host (reads args OR query) -> renders BrandIntroScreen
/// ----------------------------------------------------------------------------
class PublicHomeScreen extends StatelessWidget {
  static const String routeName = AppRoutes.publicHome;

  const PublicHomeScreen({super.key});

  String _asTrimmed(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final map = (args is Map) ? args : <dynamic, dynamic>{};

    var clinicId = _asTrimmed(map['clinicId']);
    var corporateCode = _asTrimmed(map['corporateCode']);

    if (clinicId.isEmpty) {
      final qp = Uri.base.queryParameters;
      clinicId = _asTrimmed(qp['c'] ?? qp['clinicId'] ?? qp['clinic']);
      corporateCode = _asTrimmed(
        corporateCode.isNotEmpty
            ? corporateCode
            : (qp['corp'] ?? qp['corporate'] ?? qp['corpCode'] ?? qp['code']),
      );
    }

    if (clinicId.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('Missing clinicId')),
      );
    }

    final branding = ClinicBranding.defaults;

    return BrandIntroScreen(
      clinicId: clinicId,
      corporateCode: corporateCode.isEmpty ? null : corporateCode,
      branding: branding,
    );
  }
}

/// ----------------------------------------------------------------------------
/// Brand intro screen — logo above text + two buttons + powered-by footer
/// + ✅ Top-right contact icons pulled from PUBLIC config doc
/// ----------------------------------------------------------------------------
class BrandIntroScreen extends StatefulWidget {
  final String clinicId;
  final String? corporateCode;
  final ClinicBranding branding;

  const BrandIntroScreen({
    super.key,
    required this.clinicId,
    this.corporateCode,
    required this.branding,
  });

  @override
  State<BrandIntroScreen> createState() => _BrandIntroScreenState();
}

class _BrandIntroScreenState extends State<BrandIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _buttonsCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scalePop;

  bool _showPowered = false;

  @override
  void initState() {
    super.initState();
    _buttonsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _buttonsCtrl.forward();
    });

    _buttonsCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() => _showPowered = true);
        });
      }
    });

    _fadeIn = CurvedAnimation(parent: _buttonsCtrl, curve: Curves.easeOut);

    _scalePop = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.00)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 35,
      ),
    ]).animate(_buttonsCtrl);
  }

  @override
  void dispose() {
    _buttonsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _routeArgs() {
    final args = <String, dynamic>{'clinicId': widget.clinicId};
    final corp = (widget.corporateCode ?? '').trim();
    if (corp.isNotEmpty) args['corporateCode'] = corp;
    return args;
  }

  Future<void> _goToPriceList() async {
    if (!mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.priceList,
      arguments: _routeArgs(),
    );
  }

  Future<void> _goToBooking() async {
    if (!mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.patientBookSimple,
      arguments: _routeArgs(),
    );
  }

  Widget _buildClinicLogoAsset(double height) {
    final b = widget.branding;
    return Image.asset(
      b.clinicLogoAsset ?? ClinicBranding.defaults.clinicLogoAsset!,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _buildClinicLogo(double height, {String? logoUrl}) {
    final url = (logoUrl ?? '').trim();

    if (url.isNotEmpty) {
      return Image.network(
        url,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildClinicLogoAsset(height),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            height: height,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    return _buildClinicLogoAsset(height);
  }

  DocumentReference<Map<String, dynamic>> _publicConfigDoc() {
    return FirebaseFirestore.instance
        .collection('clinics')
        .doc(widget.clinicId)
        .collection('public')
        .doc('config')
        .collection('publicBooking')
        .doc('publicBooking');
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.branding;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _publicConfigDoc().snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? const <String, dynamic>{};

            final logoUrl = _s(data['logoUrl']);

            final landingUrl = _s(data['landingUrl']);
            final websiteUrl = _s(data['websiteUrl']);
            final email = _s(data['email']);
            final whatsapp = _s(data['whatsapp']);
            final phone = _s(data['phone']);

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 680;

                final double contentMaxWidth =
                    isWide ? 900 : constraints.maxWidth;
                final double horizontalPad = isWide ? 32 : 24;

                final double prevCardSide = isWide
                    ? (contentMaxWidth - 24 - 24 - 24) / 2
                    : constraints.maxWidth - 48;

                final double diameter =
                    (prevCardSide * 0.40).clamp(110.0, 180.0);
                final double gap = isWide ? diameter * 0.25 : 18;
                final double logoHeight = isWide ? 120.0 : 100.0;

                return Stack(
                  children: [
                    // ✅ Top-right action icons
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SafeArea(
                        child: _PublicActionIcons(
                          landingUrl: landingUrl.isEmpty ? null : landingUrl,
                          websiteUrl: websiteUrl.isEmpty ? null : websiteUrl,
                          email: email.isEmpty ? null : email,
                          whatsapp: whatsapp.isEmpty ? null : whatsapp,
                          phone: phone.isEmpty ? null : phone,
                        ),
                      ),
                    ),

                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: horizontalPad),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 8),
                              _buildClinicLogo(
                                logoHeight,
                                logoUrl: logoUrl.isEmpty ? null : logoUrl,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                b.brandBodyText,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: b.navy,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 28),
                              FadeTransition(
                                opacity: _fadeIn,
                                child: ScaleTransition(
                                  scale: _scalePop,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 24),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: gap,
                                      runSpacing: 18,
                                      children: [
                                        _CircleImageButton(
                                          key:
                                              const ValueKey('book_online_btn'),
                                          diameter: diameter,
                                          imageAsset: b.bookButtonAsset,
                                          semanticLabel: 'Book Online',
                                          onTap: _goToBooking,
                                        ),
                                        _CircleImageButton(
                                          key: const ValueKey('price_list_btn'),
                                          diameter: diameter,
                                          imageAsset: b.priceButtonAsset,
                                          semanticLabel: 'Price list',
                                          onTap: _goToPriceList,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 22,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _showPowered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                b.poweredByText,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                              ),
                              if ((b.poweredByLogoAsset ?? '').isNotEmpty)
                                Image.asset(
                                  b.poweredByLogoAsset!,
                                  height: 48,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// Top-right public action icons (globe/email/whatsapp/phone)
/// Uses url_launcher (already in your pubspec).
/// ----------------------------------------------------------------------------
class _PublicActionIcons extends StatelessWidget {
  final String? landingUrl;
  final String? websiteUrl;
  final String? email;
  final String? whatsapp;
  final String? phone;

  const _PublicActionIcons({
    this.landingUrl,
    this.websiteUrl,
    this.email,
    this.whatsapp,
    this.phone,
  });

  bool _hasValue(String? v) => v != null && v.trim().isNotEmpty;

  String get _bestWebUrl {
    final l = (landingUrl ?? '').trim();
    if (l.isNotEmpty) return l;
    return (websiteUrl ?? '').trim();
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $uri')),
      );
    }
  }

  Uri _safeParseWeb(String raw) {
    final s = raw.trim();
    if (s.toLowerCase().startsWith('http://') ||
        s.toLowerCase().startsWith('https://')) {
      return Uri.parse(s);
    }
    // allow "example.com"
    return Uri.parse('https://$s');
  }

  Uri _whatsappUri(String raw) {
    final s = raw.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return Uri.parse(s);
    }
    if (lower.startsWith('wa.me/')) {
      return Uri.parse('https://$s');
    }
    final digits = _digitsOnly(s);
    return Uri.parse('https://wa.me/$digits');
  }

  Uri _telUri(String raw) {
    // tel: works best with digits/+ only
    final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    return Uri(scheme: 'tel', path: cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    final web = _bestWebUrl;
    if (_hasValue(web)) {
      buttons.add(
        IconButton(
          tooltip: 'Website',
          icon: const Icon(Icons.public),
          onPressed: () => _openUrl(context, _safeParseWeb(web)),
        ),
      );
    }

    if (_hasValue(email)) {
      buttons.add(
        IconButton(
          tooltip: 'Email',
          icon: const Icon(Icons.email_outlined),
          onPressed: () => _openUrl(
            context,
            Uri(scheme: 'mailto', path: email!.trim()),
          ),
        ),
      );
    }

    if (_hasValue(whatsapp)) {
      final digits = _digitsOnly(whatsapp!);
      if (digits.isNotEmpty) {
        buttons.add(
          IconButton(
            tooltip: 'WhatsApp',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => _openUrl(context, _whatsappUri(whatsapp!)),
          ),
        );
      }
    }

    if (_hasValue(phone)) {
      buttons.add(
        IconButton(
          tooltip: 'Call',
          icon: const Icon(Icons.call_outlined),
          onPressed: () => _openUrl(context, _telUri(phone!)),
        ),
      );
    }

    // If nothing configured, render nothing (prevents empty pill)
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.white.withValues(alpha: 0.90),
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }
}

/// Circular image button component
class _CircleImageButton extends StatelessWidget {
  final double diameter;
  final String imageAsset;
  final String semanticLabel;
  final VoidCallback onTap;

  const _CircleImageButton({
    super.key,
    required this.diameter,
    required this.imageAsset,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double padding = diameter * 0.12;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  offset: Offset(6, 10),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
            ),
            padding: EdgeInsets.all(padding),
            alignment: Alignment.center,
            child: SizedBox.square(
              dimension: diameter - (padding * 2),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Image.asset(
                  imageAsset,
                  errorBuilder: (context, _, __) =>
                      const Icon(Icons.image_not_supported),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
