import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class GpsDiagnosticDialog extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const GpsDiagnosticDialog({
    required this.errorMessage,
    required this.onRetry,
    super.key,
  });

  static bool isGpsError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('outside') ||
        lower.contains('gps') ||
        lower.contains('accuracy') ||
        lower.contains('stale') ||
        lower.contains('location') ||
        lower.contains('distance');
  }

  static Future<void> show(
    BuildContext context, {
    required String errorMessage,
    required VoidCallback onRetry,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => GpsDiagnosticDialog(
        errorMessage: errorMessage,
        onRetry: () {
          Navigator.of(ctx).pop();
          onRetry();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      icon: const Icon(
        Icons.location_off_rounded,
        color: AppColors.danger,
        size: 40,
      ),
      title: const Text(
        'Location Verification',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.medium),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              errorMessage,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          const Text(
            'Troubleshooting tips:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Move outdoors or near a window to acquire a stronger satellite fix.\n'
            '• Check that Location is set to High Accuracy on your device.\n'
            '• Ensure your mobile data is active to assist GPS location.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry Attendance'),
        ),
      ],
    );
  }
}
