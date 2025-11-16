import 'package:flutter/material.dart';

void showSnackBar(
    bool mounted, BuildContext context, String message, Color color) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ),
  );
}
