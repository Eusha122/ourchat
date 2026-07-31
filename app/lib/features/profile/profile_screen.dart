import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme_mode_controller.dart';
import '../auth/data/auth_models.dart';
import '../auth/state/auth_controller.dart';
import '../users/data/users_api.dart';
import '../users/state/users_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isEditing = false;
  bool _isSavingProfile = false;
  bool _isUploadingAvatar = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _startEditing(PublicUser user) {
    _displayNameController.text = user.displayName ?? '';
    _bioController.text = user.bio ?? '';
    setState(() {
      _isEditing = true;
      _error = null;
    });
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSavingProfile = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(usersApiProvider)
          .updateProfile(
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
          );
      ref.read(authControllerProvider.notifier).updateUser(updated);
      if (mounted) setState(() => _isEditing = false);
    } on UsersApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _isUploadingAvatar = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(usersApiProvider)
          .uploadAvatar(picked.path);
      ref.read(authControllerProvider.notifier).updateUser(updated);
    } on UsersApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value?.user;

    if (user == null) {
      return const Center(
        child: SizedBox(
          width: 8,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF5D4EF5),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ProfileIconButton(
              onTap: () => ref.read(themeModeProvider.notifier).toggle(),
              icon: themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            const SizedBox(width: 9),
            _ProfileIconButton(
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
              icon: Icons.logout_rounded,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x14332D69),
                        blurRadius: 50,
                        offset: Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Color(0x0A332D69),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: user.avatarUrl == null
                        ? const ColoredBox(
                            color: Color(0xFFE8E5FF),
                            child: Icon(
                              Icons.person_rounded,
                              color: Color(0xFF5D4EF5),
                              size: 42,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                if (_isUploadingAvatar)
                  const Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: 9,
                        height: 9,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF5D4EF5),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 29,
                    height: 29,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5D4EF5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 17),
        Center(
          child: Text(
            '@${user.username}',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFF1B1B1B),
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            user.email,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFF8A8A8A),
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 23),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Color(0xFFD94A5B),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_isEditing) ...[
          _ProfileField(
            controller: _displayNameController,
            label: 'Display name',
          ),
          const SizedBox(height: 13),
          _ProfileField(
            controller: _bioController,
            label: 'Bio',
            maxLength: 160,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProfileButton(
                  label: 'Cancel',
                  onTap: _isSavingProfile
                      ? null
                      : () => setState(() => _isEditing = false),
                  filled: false,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: _ProfileButton(
                  label: _isSavingProfile ? 'Saving...' : 'Save',
                  onTap: _isSavingProfile ? null : _saveProfile,
                  filled: true,
                ),
              ),
            ],
          ),
        ] else ...[
          if (user.displayName != null && user.displayName!.isNotEmpty)
            Center(
              child: Text(
                user.displayName!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF4B4657),
                  fontSize: 12,
                ),
              ),
            ),
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 7),
            Center(
              child: Text(
                user.bio!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Color(0xFF8A8A8A),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: 17),
          _ProfileButton(
            label: 'Edit profile',
            onTap: () => _startEditing(user),
            filled: false,
          ),
        ],
      ],
    );
  }
}

class _ProfileIconButton extends StatelessWidget {
  const _ProfileIconButton({required this.onTap, required this.icon});

  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1B1B1B), width: 1),
        ),
        child: Icon(icon, color: const Color(0xFF1B1B1B), size: 17),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10332D69),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x08332D69),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        cursorColor: const Color(0xFF5D4EF5),
        style: const TextStyle(
          fontFamily: 'Poppins',
          color: Color(0xFF1B1B1B),
          fontSize: 12,
        ),
        decoration: InputDecoration(
          filled: false,
          labelText: label,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            color: Color(0xFF8A8A8A),
            fontSize: 11,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? const Color(0xFF5D4EF5) : Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: filled
                ? null
                : Border.all(color: const Color(0x335D4EF5), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14332D69),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: Color(0x0A332D69),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: filled ? Colors.white : const Color(0xFF5D4EF5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
