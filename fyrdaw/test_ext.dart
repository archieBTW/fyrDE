class _MyClass {
  final int _privateField = 42;
}

extension MyExt on _MyClass {
  void test() {
    print(_privateField);
  }
}

void main() {
  _MyClass().test();
}
