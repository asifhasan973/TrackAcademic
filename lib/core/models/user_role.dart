enum UserRole {
  teacher,
  student;

  static UserRole? fromString(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'teacher') {
      return UserRole.teacher;
    }
    if (normalized == 'student') {
      return UserRole.student;
    }
    return null;
  }
}
