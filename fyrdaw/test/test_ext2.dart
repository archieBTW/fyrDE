import 'package:flutter/material.dart';

class _MyWidget extends StatefulWidget {
  @override
  State<_MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<_MyWidget> {
  int _counter = 0;
  
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

extension MyExt on _MyWidgetState {
  void test() {
    setState(() {
      _counter++;
    });
  }
}

void main() {}
