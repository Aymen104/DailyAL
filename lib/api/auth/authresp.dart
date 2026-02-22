class AuthResponse {
  final String? tokenType;
  final int? expiresIn;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? createdTime;

  AuthResponse(
      {this.accessToken,
      this.expiresIn,
      this.refreshToken,
      this.tokenType,
      this.createdTime});

  factory AuthResponse.fromJson(Map<String, dynamic>? json) {
    return json != null
        ? AuthResponse(
            accessToken: json["access_token"] as String?,
            expiresIn: json["expires_in"] as int?,
            tokenType: json["token_type"] as String?,
            createdTime: json["created_time"] != null
                ? (DateTime.tryParse(json["created_time"] as String) ?? DateTime.now())
                : DateTime.now(),
            refreshToken: json["refresh_token"] as String?)
        : AuthResponse();
  }

  Map<String, dynamic> toJson() {
    return {
      "access_token": accessToken,
      "expires_in": expiresIn,
      "token_type": tokenType,
      "refresh_token": refreshToken,
      "created_time": createdTime.toString()
    };
  }
}
