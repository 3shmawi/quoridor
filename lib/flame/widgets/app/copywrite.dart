import 'package:flutter/material.dart';

class AppCopyWrite extends StatelessWidget {
  const AppCopyWrite({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text.rich(
          textDirection: TextDirection.ltr,
          TextSpan(
            children: [
              TextSpan(
                text: "@copyWrite",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const TextSpan(text: " "),
              const TextSpan(
                text: "MO",
                style: TextStyle(color: Colors.cyan),
              ),
              TextSpan(
                text: "RE",
                style: TextStyle(color: Theme.of(context).dividerColor),
              ),
              const TextSpan(
                text: " H",
                style: TextStyle(color: Colors.cyan),
              ),
            ],
          ),
        ),
        Text(
          "ASHMAWY",
          style: TextStyle(
            color: Theme.of(context).dividerColor,
            letterSpacing: 1.2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
