
class AutomationPoint {
  double time;
  double value;
  AutomationPoint(this.time, this.value);
  Map<String, dynamic> toJson() => {'time': time, 'value': value};
  factory AutomationPoint.fromJson(Map<String, dynamic> json) =>
      AutomationPoint(json['time'], json['value']);
}
