import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../ui/widgets.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 18),
              Text(
                'Regles du jeu',
                style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              const RuleCard(
                title: 'Gagner',
                description: 'Aligne 3 symboles sur une ligne. Partie terminee.',
                icon: Icons.emoji_events_outlined,
                iconColor: AppColors.accentOrange,
              ),
              const SizedBox(height: 14),
              const RuleCard(
                title: 'Perdre',
                description: 'L\'adversaire aligne 3 symboles. Partie terminee.',
                icon: Icons.thumb_down_alt_outlined,
                iconColor: AppColors.accentRed,
              ),
              const SizedBox(height: 14),
              const RuleCard(
                title: 'Match nul',
                description: 'Grille pleine sans vainqueur. Partie terminee.',
                icon: Icons.balance_outlined,
                iconColor: AppColors.accentBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
