import 'package:flutter/material.dart';
import 'widgets/home_compression_banner.dart';
import 'widgets/home_game_grid.dart';
import 'widgets/home_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const HomeHeader(),
          const HomeCompressionBanner(),
          const Expanded(child: HomeGameGrid()),
        ],
      ),
    );
  }
}
