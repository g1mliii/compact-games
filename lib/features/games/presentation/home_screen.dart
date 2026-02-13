import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import 'component_test_screen.dart';

const bool _showComponentTestScreen = bool.fromEnvironment(
  'PRESSPLAY_COMPONENT_TEST_SCREEN',
  defaultValue: false,
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          _HomeHeader(),
          Expanded(child: _HomeBody()),
        ],
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Text('PressPlay', style: AppTypography.headingMedium),
              Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return _showComponentTestScreen
        ? const ComponentTestScreen()
        : const Center(
            child: Text(
              'Game grid coming soon',
              style: AppTypography.bodyMedium,
            ),
          );
  }
}
