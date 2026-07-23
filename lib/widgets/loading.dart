import 'package:flutter/material.dart';

class Loading extends StatelessWidget {
  final String text;
  const Loading({super.key, this.text = "Carregando..."});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text),
      ],
    );
  }
}
