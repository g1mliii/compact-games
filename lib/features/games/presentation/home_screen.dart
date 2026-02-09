import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          const Expanded(
            child: Center(
              child: Text(
                'Game grid coming soon',
                style: AppTypography.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: const Row(
        children: [
          Text('PressPlay', style: AppTypography.headingMedium),
          Spacer(),
          // Settings button, search, etc. will go here
        ],
      ),
    );
  }
}
