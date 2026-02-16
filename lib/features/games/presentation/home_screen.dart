import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/cinematic_background.dart';
import 'widgets/home_compression_banner.dart';
import 'widgets/home_game_grid.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _entered = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled = AppMotion.animationsEnabled(context);
    final visible = !animationsEnabled || _entered;
    final content = SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: HomeHeader(),
          ),
          const HomeCompressionBanner(),
          const Expanded(child: HomeGameGrid()),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CinematicBackground(
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: AppMotion.slow,
          curve: AppMotion.emphasizedCurve,
          child: AnimatedScale(
            scale: visible ? 1.0 : 0.985,
            duration: AppMotion.slow,
            curve: AppMotion.emphasizedCurve,
            child: content,
          ),
        ),
      ),
    );
  }
}
