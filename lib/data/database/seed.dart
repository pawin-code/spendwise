import 'package:spendwise/domain/enums.dart';

class SeedCategory {
  const SeedCategory(this.id, this.name, this.type, this.icon, this.color);
  final String id;
  final String name;
  final CategoryType type;
  final String icon;
  final int color;
}

const List<SeedCategory> kDefaultCategories = [
  SeedCategory(
    'cat_food',
    'Food & groceries',
    CategoryType.expense,
    'restaurant',
    0xFFEF6C00,
  ),
  SeedCategory(
    'cat_transport',
    'Transport',
    CategoryType.expense,
    'directions_bus',
    0xFF1976D2,
  ),
  SeedCategory(
    'cat_shopping',
    'Shopping',
    CategoryType.expense,
    'shopping_bag',
    0xFF8E24AA,
  ),
  SeedCategory(
    'cat_bills',
    'Bills & utilities',
    CategoryType.expense,
    'receipt_long',
    0xFF00838F,
  ),
  SeedCategory(
    'cat_rent',
    'Rent & housing',
    CategoryType.expense,
    'home',
    0xFF6D4C41,
  ),
  SeedCategory(
    'cat_education',
    'Education',
    CategoryType.expense,
    'school',
    0xFF3949AB,
  ),
  SeedCategory(
    'cat_health',
    'Health',
    CategoryType.expense,
    'favorite',
    0xFFD32F2F,
  ),
  SeedCategory(
    'cat_entertainment',
    'Entertainment',
    CategoryType.expense,
    'movie',
    0xFFC2185B,
  ),
  SeedCategory(
    'cat_travel',
    'Travel',
    CategoryType.expense,
    'flight',
    0xFF0288D1,
  ),
  SeedCategory(
    'cat_personal',
    'Personal care',
    CategoryType.expense,
    'spa',
    0xFF7B1FA2,
  ),
  SeedCategory(
    'cat_family',
    'Family',
    CategoryType.expense,
    'family_restroom',
    0xFFF9A825,
  ),
  SeedCategory(
    'cat_other',
    'Other',
    CategoryType.expense,
    'category',
    0xFF546E7A,
  ),
  SeedCategory(
    'cat_salary',
    'Salary',
    CategoryType.income,
    'payments',
    0xFF2E7D32,
  ),
  SeedCategory(
    'cat_freelance',
    'Freelance',
    CategoryType.income,
    'laptop',
    0xFF00897B,
  ),
  SeedCategory(
    'cat_business',
    'Business',
    CategoryType.income,
    'storefront',
    0xFF558B2F,
  ),
  SeedCategory(
    'cat_interest',
    'Interest',
    CategoryType.income,
    'savings',
    0xFF0097A7,
  ),
  SeedCategory(
    'cat_gifts',
    'Gifts',
    CategoryType.income,
    'card_giftcard',
    0xFFAD1457,
  ),
  SeedCategory(
    'cat_other_income',
    'Other income',
    CategoryType.income,
    'add_circle',
    0xFF546E7A,
  ),
];

const String kDefaultWalletId = 'wallet_cash';
