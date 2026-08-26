import 'package:flutter/material.dart';

void showCustomSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  Color bgColor = Colors.indigo.shade800;
  IconData icon = Icons.info_outline_rounded;
  
  if (isError) {
    bgColor = Colors.redAccent.shade700;
    icon = Icons.error_outline_rounded;
  } else if (isSuccess) {
    bgColor = Colors.green.shade600;
    icon = Icons.check_circle_outline_rounded;
  }

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      elevation: 10,
      duration: Duration(milliseconds: isError ? 3000 : 1500),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: Colors.yellowAccent,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
