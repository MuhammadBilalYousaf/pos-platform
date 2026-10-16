import 'dart:io';

import 'package:flutter/material.dart';

import 'admin_ui_kit.dart';

/// Product thumbnail: network URL, local file path, or placeholder icon.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    this.imageUrl,
    this.localPath,
    this.size = 40,
    this.borderRadius = 8,
    this.iconSize,
  });

  final String? imageUrl;
  final String? localPath;
  final double size;
  final double borderRadius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kAdminAccentSoft,
        borderRadius: radius,
      ),
      child: Icon(Icons.icecream_outlined, color: kAdminAccent, size: iconSize ?? size * 0.45),
    );

    final path = localPath?.trim() ?? '';
    if (path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: radius,
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      }
    }

    final url = imageUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }

    return placeholder;
  }
}
