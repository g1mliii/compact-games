import 'package:flutter/material.dart';
import '../../../core/widgets/cinematic_background.dart';
import 'widgets/home_compression_banner.dart';
import 'widgets/home_game_grid.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CinematicBackground(
        child: SafeArea(
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
        ),
      ),
    );
  }
}
