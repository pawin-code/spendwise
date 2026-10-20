enum TxnType { income, expense, transfer }

enum CategoryType { income, expense }

enum WalletKind { cash, bank, digital }

enum Frequency { once, daily, weekly, monthly, yearly }

enum ReminderKind { rent, utility, subscription, loan, other }

extension FrequencyLabel on Frequency {
  String get label => switch (this) {
    Frequency.once => 'One time',
    Frequency.daily => 'Daily',
    Frequency.weekly => 'Weekly',
    Frequency.monthly => 'Monthly',
    Frequency.yearly => 'Yearly',
  };
}

extension ReminderKindLabel on ReminderKind {
  String get label => switch (this) {
    ReminderKind.rent => 'Rent',
    ReminderKind.utility => 'Utility bill',
    ReminderKind.subscription => 'Subscription',
    ReminderKind.loan => 'Loan / EMI',
    ReminderKind.other => 'Other',
  };
}

extension WalletKindLabel on WalletKind {
  String get label => switch (this) {
    WalletKind.cash => 'Cash',
    WalletKind.bank => 'Bank account',
    WalletKind.digital => 'Digital wallet / UPI',
  };
}
