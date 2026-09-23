# Split: an offline Splitwise clone for Android

A Flutter app that works like Splitwise but runs entirely on your phone. It has no accounts, no cloud, no ads and no analytics. The release build doesn't even request the Internet permission. All data lives in a local SQLite database on the device.

## Features

- **Groups and members.** Create a group and type in people's names. You can add, rename or remove members later.
- **Expenses.** Enter a description, amount, date and who paid. Split it **equally** between any subset of members, or by **exact amounts** (a live counter shows how much is still unassigned). Tap an expense to edit or delete it.
- **Who owes who.** Every member's net balance ("gets back" / "owes") and the **simplified list of payments** that settles the whole group.
- **Settle up.** Tap **Settle** on a suggested payment, or record any payment by hand.
- Material 3 UI in Splitwise green, with light and dark mode and a per-group currency symbol.

## Debt simplification

The code is in `lib/debt_simplifier.dart`.

1. The app computes each member's net balance in integer cents: what they paid, minus their shares, adjusted for recorded payments.
2. It finds the **largest number of zero-sum subgroups** using an O(2ⁿ·n) bitmask DP. A subgroup of k people settles in k−1 payments, so the total `n − subgroups` is the true minimum. The classic greedy approach alone doesn't always reach it.
3. Inside each subgroup it applies the greedy step: the biggest debtor pays the biggest creditor, then repeat.
4. Groups with more than 16 people who have non-zero balances use greedy only (at most n−1 payments).

`test/debt_simplifier_test.dart` checks the result against a brute-force optimum on 300 random groups.

## Get the APK

### Option A: download a ready-made APK (no setup)
Every push to this repo runs `.github/workflows/build-apk.yml` on GitHub. The workflow runs the tests, builds a release APK and attaches it to a GitHub Release.

1. On your phone, open **github.com/IbnSinan/Splitwise_Clone/releases**.
2. Download **SplitOffline.apk** from the latest release.
3. Open it. If Android asks, allow *Install unknown apps* for your browser, then tap **Install**.

> **Keeping your data across updates:** Android installs an update over an existing app only when both are signed with the same key. Without a key configured, every CI build has a different debug key, so installing a newer build means uninstalling the old one, which deletes its data. To avoid this, create a key once and add it as repository secrets:
> ```bash
> keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias split
> base64 -w0 release.jks   # paste the output into the KEYSTORE_BASE64 secret
> ```
> Then add the secrets `KEYSTORE_PASSWORD`, `KEY_ALIAS` (`split`) and `KEY_PASSWORD` under *Settings → Secrets and variables → Actions*.

### Option B: build it yourself (about 5 minutes)
You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.47+) and the Android SDK. Installing Android Studio once gives you the Android SDK.

```bash
git clone https://github.com/IbnSinan/Splitwise_Clone.git
cd Splitwise_Clone
flutter pub get
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```
To install it directly, plug in your phone with USB debugging enabled and run `flutter install`. You can also copy the APK to the phone and open it there.

## Project layout

```
lib/
  main.dart                 app entry and theme
  models.dart               Group, Member, Expense, Settlement
  database_helper.dart      SQLite schema and all queries (sqflite)
  debt_simplifier.dart      balances, equal split, minimum-transfer algorithm
  format.dart               money parsing and formatting (integer cents)
  widgets.dart              avatars and dialogs
  screens/
    home_screen.dart        list of groups
    create_group_screen.dart
    group_screen.dart       Balances / Expenses / Members tabs, settle up
    add_expense_screen.dart add or edit an expense (equal or exact split)
test/                       algorithm, database and end-to-end UI tests
```

Run the tests with `flutter test --concurrency=1`.
