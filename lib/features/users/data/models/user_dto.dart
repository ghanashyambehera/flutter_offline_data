import 'dart:convert';

class UserDto {
  UserDto({
    required this.name,
    required this.email,
    this.job,
    required this.clientRequestId,
  });

  final String name;
  final String email;
  final String? job;
  final String clientRequestId;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      if (job != null && job!.isNotEmpty) 'job': job,
      'clientRequestId': clientRequestId,
    };
  }

  static UserDto fromUserFields({
    required String name,
    required String email,
    String? job,
    required String localId,
  }) {
    return UserDto(
      name: name,
      email: email,
      job: job,
      clientRequestId: localId,
    );
  }

  String toPayloadJson() => jsonEncode(toJson());

  static Map<String, dynamic> parsePayload(String payloadJson) {
    return jsonDecode(payloadJson) as Map<String, dynamic>;
  }

  static String? parseServerId(Map<String, dynamic> response) {
    final id = response['id'];
    if (id == null) return null;
    return id.toString();
  }
}
