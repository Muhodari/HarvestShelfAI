/// Researcher: manages accounts and exports the evaluation log.
/// Seller: scans produce and sees their own history.
enum UserRole {
  researcher('researcher', 'Researcher'),
  seller('seller', 'Seller');

  const UserRole(this.id, this.label);

  final String id;
  final String label;

  static UserRole fromId(String id) =>
      UserRole.values.firstWhere((r) => r.id == id);
}

/// A local account on this phone (a row in `app_user`).
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.createdAt,
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  bool get isResearcher => role == UserRole.researcher;

  /// Up to two initials for the avatar.
  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName => displayName.trim().split(RegExp(r'\s+')).first;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
    id: m['id'] as int,
    username: m['username'] as String,
    displayName: m['display_name'] as String,
    role: UserRole.fromId(m['role'] as String),
    createdAt: DateTime.parse(m['created_at'] as String),
    lastLoginAt: m['last_login_at'] == null
        ? null
        : DateTime.parse(m['last_login_at'] as String),
  );
}
