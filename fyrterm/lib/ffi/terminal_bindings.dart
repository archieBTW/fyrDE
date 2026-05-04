import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

final DynamicLibrary _lib = () {
  if (Platform.isLinux) {
    final libPath = path.join(
      Directory.current.path,
      'linux/lib/libterminal.so',
    );
    print('Loaded: ${libPath}');

    // try {
    //   startShell();
    //   print('Shell started!');
    // } catch (e) {
    //   print('Error starting shell: $e');
    // }

    return DynamicLibrary.open(libPath);
  } else {
    throw UnsupportedError('Only Linux is supported for now.');
  }
}();

final void Function() startShell = _lib
    .lookup<NativeFunction<Void Function()>>('StartShell')
    .asFunction();

final void Function(Pointer<Utf8>) writeToShell = _lib
    .lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('WriteToShell')
    .asFunction();

final int Function(Pointer<Int8>, int) readFromShell = _lib
    .lookup<NativeFunction<Int32 Function(Pointer<Int8>, Int32)>>(
      'ReadFromShell',
    )
    .asFunction();
