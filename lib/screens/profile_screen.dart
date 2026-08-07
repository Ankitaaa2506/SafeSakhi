import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/emergency_contact.dart';
import '../providers/auth_provider.dart';
import '../services/emergency_service.dart';
import '../services/firestore_service.dart';
import '../theme/constants.dart';
import 'emergency_contact_screen.dart';
import 'my_reviews_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _reviewCount = 0;
  bool _loadingStats = true;
  EmergencyContact? _emergencyContact;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadEmergencyContact();
  }

  Future<void> _loadEmergencyContact() async {
    final c = await EmergencyService.instance.getContact();
    if (mounted) setState(() => _emergencyContact = c);
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    if (user == null) {
      debugPrint('[Profile] No user — skipping stats load');
      setState(() => _loadingStats = false);
      return;
    }

    debugPrint('[Profile] Loading stats for uid=${user.uid}');

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('userReviews')
          .get();

      debugPrint('[Profile] Found ${snap.docs.length} userReviews');

      if (snap.docs.isEmpty) {
        debugPrint('[Profile] userReviews empty — running migration...');
        final migrated = await FirestoreService().migrateExistingReviews(user.uid);
        debugPrint('[Profile] Migration complete: $migrated reviews migrated');

        final retrySnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('userReviews')
            .get();
        debugPrint('[Profile] After migration: ${retrySnap.docs.length} userReviews');

        if (mounted) {
          setState(() {
            _reviewCount = retrySnap.docs.length;
            _loadingStats = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _reviewCount = snap.docs.length;
            _loadingStats = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Profile] Failed to load review count: $e');
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final user = auth.appUser;
        final isLoggedOut = !auth.isLoggedIn;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          appBar: AppBar(
            title: Text('Profile', style: AppStyles.appBarTitleStyle),
            backgroundColor: AppColors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Avatar
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryBlue,
                          AppColors.primaryBlue.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: user?.photoUrl != null
                        ? ClipOval(
                            child: Image.network(
                              user!.photoUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(Icons.person, color: Colors.white, size: 40),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user?.displayName ?? 'Guest User',
                  style: AppStyles.headingStyle.copyWith(fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'Sign in to sync your data',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),

                // 1. Community Contributions
                if (!isLoggedOut && user != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildContributionsCard(),
                  ),
                  const SizedBox(height: 10),
                ],

                // 2. Account Information
                if (!isLoggedOut && user != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(Icons.email_outlined, 'Email',
                                user.email ?? '-'),
                            const SizedBox(height: 8),
                            _infoRow(Icons.verified_user, 'Signed in via',
                                user.authProvider?.toUpperCase() ?? '-'),
                            const SizedBox(height: 8),
                            _infoRow(Icons.calendar_today, 'Joined',
                                _formatDate(user.createdAt)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 3. Emergency Contact
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildEmergencyContactCard(),
                ),
                const SizedBox(height: 10),

                // 4. My Reviews (solid blue)
                if (!isLoggedOut && user != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MyReviewsScreen(userId: user.uid),
                            ),
                          );
                        },
                        icon: const Icon(Icons.reviews_outlined, size: 20),
                        label: const Text(
                          'My Reviews',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (!isLoggedOut && user != null)
                  const SizedBox(height: 10),

                // 5. Sign In / Sign Out (solid colors, always last)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: isLoggedOut
                      ? SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () => _signInWithGoogle(context),
                            icon: const Icon(Icons.login, size: 20),
                            label: const Text(
                              'Sign in with Google',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        )
                      : SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () => _signOut(context),
                            icon: const Icon(Icons.logout, size: 20),
                            label: const Text(
                              'Sign out',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.errorRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContributionsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlue.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.volunteer_activism,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Community Contributions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statBlock(
                _loadingStats ? '...' : '$_reviewCount',
                'Reviews',
              ),
              const SizedBox(width: 24),
              _statBlock(
                _reviewCount >= 5
                    ? 'Active'
                    : _reviewCount >= 1
                        ? 'Starter'
                        : 'New',
                'Status',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              Text(value,
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildEmergencyContactCard() {
    final hasContact = _emergencyContact != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasContact
            ? AppColors.errorRed.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasContact
              ? AppColors.errorRed.withValues(alpha: 0.15)
              : AppColors.borderColor,
        ),
        boxShadow: AppStyles.standardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.emergency,
                  color: AppColors.errorRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Emergency Contact',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasContact) ...[
            Row(
              children: [
                const Text('👤', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _emergencyContact!.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('📞', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  _emergencyContact!.phone,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (_emergencyContact!.relationship.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('❤️', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    _emergencyContact!.relationship,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _contactAction(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmergencyContactScreen(),
                        ),
                      );
                      _loadEmergencyContact();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contactAction(
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    color: AppColors.errorRed,
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: const Text('Delete Contact?'),
                          content: const Text(
                              'Your emergency contact will be removed.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text('Delete',
                                  style: TextStyle(
                                      color: AppColors.errorRed)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await EmergencyService.instance.deleteContact();
                        if (mounted) {
                          setState(() => _emergencyContact = null);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'No emergency contact added.\nAdd one trusted contact for SOS alerts.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmergencyContactScreen(),
                    ),
                  );
                  _loadEmergencyContact();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Add Contact',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactAction({
    required String label,
    required IconData icon,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: (color ?? AppColors.primaryBlue).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color ?? AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color ?? AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    await auth.signInWithGoogle();
  }

  void _signOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) Navigator.of(context).pop();
            },
            child:
                Text('Sign out', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
  }
}
