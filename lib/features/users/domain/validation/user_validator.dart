class UserValidationException implements Exception {
  UserValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UserValidator {
  static void validate({
    required String name,
    required String email,
    String? job,
  }) {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();

    if (trimmedName.isEmpty) {
      throw UserValidationException('Name is required.');
    }
    if (trimmedName.length > 100) {
      throw UserValidationException('Name must be 100 characters or less.');
    }
    if (trimmedEmail.isEmpty) {
      throw UserValidationException('Email is required.');
    }
    if (!_isValidEmail(trimmedEmail)) {
      throw UserValidationException('Enter a valid email address.');
    }
    if (job != null && job.trim().length > 100) {
      throw UserValidationException('Job must be 100 characters or less.');
    }
  }

  static bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }
}
