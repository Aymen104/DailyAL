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

  /// Whether this response can actually authorize a request.
  ///
  /// [fromJson] does not distinguish "a token with these fields" from "JSON that
  /// was not a token at all". MAL's OAuth endpoints answer a rejected refresh or
  /// a rejected code exchange with `200`-shaped JSON error bodies such as
  /// `{"error":"invalid_request","message":"The refresh token is invalid."}`,
  /// so every field lookup misses and the result is an [AuthResponse] with a
  /// null `accessToken`/`tokenType` - indistinguishable from an empty one.
  ///
  /// Callers that were storing whatever came back were therefore storing a
  /// phantom session: `status` was set to AUTHENTICATED, the phantom was
  /// persisted, and `tokenType! + accessToken!` then threw on the next write.
  /// This predicate is what makes that state detectable.
  bool get isUsable =>
      (accessToken != null && accessToken!.isNotEmpty) &&
      (tokenType != null && tokenType!.isNotEmpty);

  factory AuthResponse.fromJson(Map<String, dynamic>? json) {
    return json != null
        ? AuthResponse(
            accessToken: json["access_token"],
            expiresIn: json["expires_in"],
            tokenType: json["token_type"],
            createdTime: json["created_time"] != null
                ? (DateTime.tryParse(json["created_time"]))
                : DateTime.now(),
            refreshToken: json["refresh_token"])
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
