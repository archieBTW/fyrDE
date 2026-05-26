class WifiNetwork {
  final String ssid;
  final String signal;
  final String security;

  const WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.security,
  });

  bool get isSecure => security.isNotEmpty && security != '--';
}
