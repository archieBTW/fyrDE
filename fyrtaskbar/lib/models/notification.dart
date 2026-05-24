class FyrNotification {
  final int id;
  final String appName;
  final String title;
  final String body;
  final String icon;
  final DateTime timestamp;
  final List<String> actions;
  final int timeout;

  FyrNotification({
    required this.id,
    required this.appName,
    required this.title,
    required this.body,
    required this.icon,
    required this.timestamp,
    this.actions = const [],
    this.timeout = 5000,
  });
}
