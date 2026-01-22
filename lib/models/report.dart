class CodeReport {
  final String gameName;
  final String code;
  final String reportType; // 'invalid' 或 'expired'
  final String reportTime;
  final String? userDevice;
  final String? userLocation;

  CodeReport({
    required this.gameName,
    required this.code,
    required this.reportType,
    required this.reportTime,
    this.userDevice,
    this.userLocation,
  });

  Map<String, dynamic> toJson() {
    return {
      'gameName': gameName,
      'code': code,
      'reportType': reportType,
      'reportTime': reportTime,
      'userDevice': userDevice,
      'userLocation': userLocation,
    };
  }

  factory CodeReport.fromJson(Map<String, dynamic> json) {
    return CodeReport(
      gameName: json['gameName'] as String,
      code: json['code'] as String,
      reportType: json['reportType'] as String,
      reportTime: json['reportTime'] as String,
      userDevice: json['userDevice'] as String?,
      userLocation: json['userLocation'] as String?,
    );
  }
}
