import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/organization_profile_service.dart';

class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    this.logoPath,
    this.size = 40,
    this.radius = 10,
    this.backgroundColor,
  });

  final String? logoPath;
  final double size;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      OrganizationProfileService.defaultLogoAsset,
      fit: BoxFit.contain,
    );
    final image = logoPath == null || logoPath!.trim().isEmpty
        ? fallback
        : Image.file(
            File(logoPath!),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback,
          );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .08),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
