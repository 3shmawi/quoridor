import 'package:flutter/material.dart';

class DrawerAppHeader extends StatelessWidget {
  const DrawerAppHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return DrawerHeader(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage('assets/icons/logo.png'),
          fit: BoxFit.cover,
        ),
        color: Theme.of(context).colorScheme.primary,
      ),
      child: const SizedBox(height: double.infinity, width: double.infinity),
    );
  }
}
