import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SoLoud.instance.init();
  try {
    var src = await SoLoud.instance.loadAsset('assets/samples/piano_c4.wav');
    print("SUCCESS: loaded ${src.soundHash}");
  } catch (e, st) {
    print("ERROR loading asset: $e\n$st");
  }
}
