/// Account widgets: avatar and role.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/user.dart';
import '../l10n/app_text.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 22});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: Brand.green.withValues(alpha: 0.12),
    child: Text(
      user.initials,
      style: TextStyle(
        color: Brand.green,
        fontWeight: FontWeight.w800,
        fontSize: radius * 0.7,
      ),
    ),
  );
}

/// Plain role text, e.g. "Researcher".
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) => Text(
    AppText.of(context).role(role),
    style: Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
  );
}
