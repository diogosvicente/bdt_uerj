import 'package:flutter/material.dart';

class BdtPage extends StatelessWidget {
  const BdtPage({super.key});

  @override
  Widget build(BuildContext context) {
    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;

    return Scaffold(
      appBar: AppBar(
        title: Text("BDT #$bdtId"),
      ),
      body: const Center(
        child: Text(
          "BDT aberto.\nAqui depois vamos colocar viagens, localização e ocorrências.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
