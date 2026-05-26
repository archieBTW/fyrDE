class WifiNetwork {
  final String ssid;
  final String security;
  final String signal;

  const WifiNetwork({
    required this.ssid,
    required this.security,
    required this.signal,
  });

  bool get isSecure => security.isNotEmpty && security != '--';
}
