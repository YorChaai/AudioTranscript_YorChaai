/// Application-wide constants to avoid magic numbers in the UI.
class AppConstants {
  // Breakpoints for Responsive Layout
  static const double mobileSmallBreakpoint = 360.0;
  static const double mobileMediumBreakpoint = 380.0;
  static const double mobileLargeBreakpoint = 420.0;
  static const double tabletBreakpoint = 640.0;
  
  // Padding & Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingExtraLarge = 32.0;
  static const double paddingDesktopHorizontal = 40.0;

  // Animation Durations
  static const Duration animationFast = Duration(milliseconds: 300);
  static const Duration animationMedium = Duration(milliseconds: 500);

  // Math/Conversion Constants
  static const int bytesInKB = 1024;
  static const int bytesInMB = 1024 * 1024;
}
