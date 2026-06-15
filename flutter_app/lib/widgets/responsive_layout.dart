import 'package:flutter/material.dart';

/// Responsive helpers yang lebih aman untuk Android, tablet, desktop,
/// dan perubahan orientasi.
///
/// Fokus utama:
/// - menghindari layout pecah saat rotate
/// - memberi helper spacing/padding yang konsisten
/// - membedakan phone / tablet / desktop dengan lebih stabil
/// - mendeteksi kondisi layar sempit, pendek, landscape, dan foldable-like
class Responsive {
  Responsive._();

  // Breakpoints utama
  static const double compactWidth = 360;
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;
  static const double largeDesktopBreakpoint = 1600;

  static MediaQueryData mq(BuildContext context) => MediaQuery.of(context);

  static Size screenSize(BuildContext context) => mq(context).size;

  static double screenWidth(BuildContext context) => screenSize(context).width;

  static double screenHeight(BuildContext context) => screenSize(context).height;

  static Orientation orientation(BuildContext context) => mq(context).orientation;

  static bool isPortrait(BuildContext context) =>
      orientation(context) == Orientation.portrait;

  static bool isLandscape(BuildContext context) =>
      orientation(context) == Orientation.landscape;

  static bool isVerySmallPhone(BuildContext context) =>
      screenWidth(context) < compactWidth;

  static bool isMobile(BuildContext context) =>
      screenWidth(context) < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      screenWidth(context) >= mobileBreakpoint &&
      screenWidth(context) < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      screenWidth(context) >= desktopBreakpoint;

  static bool isLargeDesktop(BuildContext context) =>
      screenWidth(context) >= largeDesktopBreakpoint;

  /// Wide layout aman untuk tablet/desktop.
  /// Di landscape phone tetap dianggap mobile supaya tidak pecah.
  static bool isWide(BuildContext context) =>
      !isPhoneLandscape(context) && screenWidth(context) >= tabletBreakpoint;

  /// Phone yang diputar landscape sering rawan overflow.
  static bool isPhoneLandscape(BuildContext context) =>
      isMobile(context) && isLandscape(context);

  /// Layar pendek, umum terjadi saat keyboard terbuka / split screen / rotate.
  static bool isShortHeight(BuildContext context) =>
      screenHeight(context) < 700;

  /// Kondisi sempit secara usable width.
  static bool isTight(BuildContext context) =>
      usableWidth(context) < 380;

  /// Safe area yang benar-benar bisa dipakai.
  static double usableWidth(BuildContext context) {
    final data = mq(context);
    return data.size.width - data.padding.left - data.padding.right;
  }

  static double usableHeight(BuildContext context) {
    final data = mq(context);
    return data.size.height -
        data.padding.top -
        data.padding.bottom -
        data.viewInsets.bottom;
  }

  /// Padding horizontal global yang aman untuk Android kecil sampai tablet.
  static double pageHorizontalPadding(BuildContext context) {
    final width = usableWidth(context);

    if (width >= 1400) return 40;
    if (width >= 1200) return 32;
    if (width >= 900) return 28;
    if (width >= 600) return 24;
    if (width >= 390) return 20;
    return 16;
  }

  /// Padding vertikal global.
  static double pageVerticalPadding(BuildContext context) {
    if (isDesktop(context)) return 24;
    if (isTablet(context)) return 20;
    if (isShortHeight(context)) return 14;
    return 16;
  }

  /// Gap kecil yang adaptif.
  static double gapSmall(BuildContext context) {
    if (isVerySmallPhone(context)) return 8;
    if (isShortHeight(context)) return 10;
    return 12;
  }

  /// Gap sedang yang adaptif.
  static double gapMedium(BuildContext context) {
    if (isVerySmallPhone(context)) return 12;
    if (isShortHeight(context)) return 14;
    return 16;
  }

  /// Gap besar yang adaptif.
  static double gapLarge(BuildContext context) {
    if (isVerySmallPhone(context)) return 16;
    if (isShortHeight(context)) return 18;
    if (isTablet(context)) return 24;
    return 20;
  }

  /// Max content width supaya tidak terlalu melebar di tablet/desktop.
  static double contentMaxWidth(BuildContext context) {
    if (isLargeDesktop(context)) return 1400;
    if (isDesktop(context)) return 1200;
    if (isTablet(context)) return 900;
    return double.infinity;
  }

  /// Column count yang aman untuk grid/card.
  static int adaptiveColumns(
    BuildContext context, {
    int mobile = 1,
    int mobileLandscape = 2,
    int tablet = 2,
    int desktop = 3,
    int largeDesktop = 4,
  }) {
    if (isLargeDesktop(context)) return largeDesktop;
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    if (isPhoneLandscape(context)) return mobileLandscape;
    return mobile;
  }

  /// Aspect ratio grid yang lebih aman saat rotate.
  static double adaptiveChildAspectRatio(
    BuildContext context, {
    double mobile = 1.0,
    double mobileLandscape = 1.35,
    double tablet = 1.25,
    double desktop = 1.35,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    if (isPhoneLandscape(context)) return mobileLandscape;
    return mobile;
  }

  /// Batas tinggi panel/sidebar di mobile agar tidak overflow.
  static double clampHeight(
    BuildContext context, {
    required double value,
    double min = 0,
    double? max,
  }) {
    final computedMax = max ?? usableHeight(context);
    return value.clamp(min, computedMax);
  }

  /// Ukuran icon adaptif.
  static double iconSize(BuildContext context,
      {double mobile = 20, double tablet = 22, double desktop = 24}) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Ukuran heading adaptif.
  static double headingSize(BuildContext context,
      {double mobile = 22, double tablet = 26, double desktop = 30}) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Ukuran body text adaptif.
  static double bodySize(BuildContext context,
      {double mobile = 13, double tablet = 14, double desktop = 15}) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }

  /// Lebar panel samping yang aman.
  static double sidePanelWidth(BuildContext context,
      {double mobile = double.infinity, double tablet = 320, double desktop = 360}) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet;
    return mobile;
  }
}

/// Widget responsive sederhana dengan fallback aman untuk Android rotate.
///
/// Aturan:
/// - desktop dipakai untuk layar besar
/// - tablet dipakai untuk tablet
/// - mobile dipakai untuk phone portrait maupun landscape phone
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileLayout;
  final Widget? tabletLayout;
  final Widget desktopLayout;

  const ResponsiveLayout({
    super.key,
    required this.mobileLayout,
    required this.desktopLayout,
    this.tabletLayout,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= Responsive.desktopBreakpoint) {
          return desktopLayout;
        }

        if (width >= Responsive.mobileBreakpoint &&
            !Responsive.isPhoneLandscape(context)) {
          return tabletLayout ?? desktopLayout;
        }

        return mobileLayout;
      },
    );
  }
}

/// Wrapper untuk memberi max width, padding, dan safe layout konsisten.
class ResponsivePage extends StatelessWidget {
  final Widget child;
  final bool centerContent;
  final EdgeInsets? padding;
  final double? maxWidth;
  final bool useSafeArea;

  const ResponsivePage({
    super.key,
    required this.child,
    this.centerContent = true,
    this.padding,
    this.maxWidth,
    this.useSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: Responsive.pageHorizontalPadding(context),
            vertical: Responsive.pageVerticalPadding(context),
          ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? Responsive.contentMaxWidth(context),
        ),
        child: child,
      ),
    );

    final body = centerContent
        ? Align(
            alignment: Alignment.topCenter,
            child: content,
          )
        : content;

    if (!useSafeArea) return body;

    return SafeArea(child: body);
  }
}

/// Helper scroll view aman untuk layar Android kecil / rotate / keyboard.
class ResponsiveScrollView extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final bool dismissKeyboardOnDrag;

  const ResponsiveScrollView({
    super.key,
    required this.child,
    this.padding,
    this.controller,
    this.dismissKeyboardOnDrag = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      keyboardDismissBehavior: dismissKeyboardOnDrag
          ? ScrollViewKeyboardDismissBehavior.onDrag
          : ScrollViewKeyboardDismissBehavior.manual,
      padding: padding ??
          EdgeInsets.only(
            left: Responsive.pageHorizontalPadding(context),
            right: Responsive.pageHorizontalPadding(context),
            top: Responsive.pageVerticalPadding(context),
            bottom: Responsive.pageVerticalPadding(context) +
                MediaQuery.of(context).viewInsets.bottom,
          ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: Responsive.usableHeight(context) - 24,
        ),
        child: child,
      ),
    );
  }
}
