import '../entities/user.dart';

abstract class UserRepository {
  Stream<List<User>> watchUsers();

  Future<User> createUser({
    required String name,
    required String email,
    String? job,
  });

  Future<User> updateUser({
    required String localId,
    required String name,
    required String email,
    String? job,
  });
}
