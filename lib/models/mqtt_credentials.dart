class MqttCredentials {
  final String login;
  final String password;

  MqttCredentials({
    required this.login,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'login': login,
      'password': password,
    };
  }

  factory MqttCredentials.fromJson(Map<String, dynamic> json) {
    return MqttCredentials(
      login: json['login'] as String,
      password: json['password'] as String,
    );
  }
}