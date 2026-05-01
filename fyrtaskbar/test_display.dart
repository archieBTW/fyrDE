import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(home: TestScreen()));
}

class TestScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(builder: (c) {
          final s = MediaQuery.of(c).size;
          return Text('Size: $s');
        }),
      ),
    );
  }
}
