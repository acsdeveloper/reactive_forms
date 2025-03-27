import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reactiveform/components/app_colours.dart';

class AppTypography {
  static TextStyle regularCaption01 = GoogleFonts.montserrat(
    fontSize: 12,
    fontWeight: FontWeight.w200,
  );

  static TextStyle regularCaption02 = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w200,
  );

  static TextStyle regularCaption03 = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w200,
    color: AppColors.appGrey,
  );

  static TextStyle boldTitle01 = GoogleFonts.montserrat(
    fontSize: 28,
    fontWeight: FontWeight.w700,
  );

  static TextStyle boldTitle02 = GoogleFonts.montserrat(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  );

  static TextStyle boldBodyAndHeadline = GoogleFonts.montserrat(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  static TextStyle bottomSheetTitle = GoogleFonts.montserrat(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimaryBlack,
    letterSpacing: 0.15,
  );

  static TextStyle searchInput = GoogleFonts.montserrat(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimaryBlack,
    letterSpacing: 0.15,
  );

  static TextStyle searchHint = GoogleFonts.montserrat(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.searchHintGrey,
    letterSpacing: 0.15,
  );

  static TextStyle actionButtonEnabled = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.doneButtonBlue,
    letterSpacing: 0.5,
  );

  static TextStyle actionButtonDisabled = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.doneButtonBlue.withOpacity(0.5),
    letterSpacing: 0.5,
  );

  static TextStyle clearButtonEnabled = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.clearButtonGrey,
    letterSpacing: 0.5,
  );

  static TextStyle clearButtonDisabled = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.clearButtonGrey.withOpacity(0.5),
    letterSpacing: 0.5,
  );

  static TextStyle listTileTitle = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimaryBlack,
    letterSpacing: 0.15,
    height: 1.3,
  );

  static TextStyle listTileSubtitle = GoogleFonts.montserrat(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
    height: 1.2,
  );

  static TextStyle dropdownItem = GoogleFonts.montserrat(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: AppColors.textPrimaryBlack,
  );

  static TextStyle noItemsFound = GoogleFonts.montserrat(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 0.15,
  );
}
