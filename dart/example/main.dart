import 'package:flutter/material.dart';
import 'package:qrmotion/qrmotion.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  QrEffect _effect = QrEffect.slide;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF5F2EA),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedQr(text: 'https://example.com', effect: _effect, size: 280),
            const SizedBox(height: 24),
            Wrap(spacing: 8, children: [
              for (final e in QrEffect.values)
                ChoiceChip(label: Text(e.name), selected: e == _effect, onSelected: (_) => setState(() => _effect = e)),
            ]),
          ]),
        ),
      );
}
