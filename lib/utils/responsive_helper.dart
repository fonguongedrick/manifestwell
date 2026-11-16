import 'package:flutter/material.dart';

/// Breakpoint helpers, ported from BraidsTribe (utils/responsive_helper.dart).
class ResponsiveHelper {
  ResponsiveHelper._();

  static const double mobile = 480;
  static const double tablet = 800;

  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobile && w < tablet;
  }

  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= tablet;

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    required T tablet,
    required T desktop,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet;
    return desktop;
  }
}
