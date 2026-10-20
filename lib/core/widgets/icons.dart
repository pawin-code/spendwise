import 'package:flutter/material.dart';

/// Icons users can pick for categories. Keys are stored in the database.
const Map<String, IconData> kCategoryIcons = {
  'restaurant': Icons.restaurant,
  'local_grocery_store': Icons.local_grocery_store,
  'directions_bus': Icons.directions_bus,
  'two_wheeler': Icons.two_wheeler,
  'local_gas_station': Icons.local_gas_station,
  'shopping_bag': Icons.shopping_bag,
  'receipt_long': Icons.receipt_long,
  'bolt': Icons.bolt,
  'phone_android': Icons.phone_android,
  'wifi': Icons.wifi,
  'home': Icons.home,
  'school': Icons.school,
  'favorite': Icons.favorite,
  'medication': Icons.medication,
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'flight': Icons.flight,
  'spa': Icons.spa,
  'family_restroom': Icons.family_restroom,
  'pets': Icons.pets,
  'category': Icons.category,
  'payments': Icons.payments,
  'laptop': Icons.laptop,
  'storefront': Icons.storefront,
  'savings': Icons.savings,
  'card_giftcard': Icons.card_giftcard,
  'add_circle': Icons.add_circle,
  'account_balance': Icons.account_balance,
  'trending_up': Icons.trending_up,
  'volunteer_activism': Icons.volunteer_activism,
};

IconData categoryIcon(String key) => kCategoryIcons[key] ?? Icons.category;

const List<int> kPaletteColors = [
  0xFF047857,
  0xFF0369A1,
  0xFF6D28D9,
  0xFFC2410C,
  0xFFBE123C,
  0xFF0F766E,
  0xFF1D4ED8,
  0xFF7E22CE,
  0xFFB45309,
  0xFF4D7C0F,
  0xFF334155,
  0xFFDB2777,
];
