# BudgetMate Mobile

Flutter (Android-first, iOS-ready) version of the BudgetMate web app: track expenses,
scan receipts with AI and split bills with friends. It uses the same Firebase project and
data as the website, so everything stays in sync between phone and browser.

## Features

- Google sign-in (Firebase Auth)
- Dashboard with budget overview, spending breakdown and insights
- Expenses by month with search and category filters; add / view / delete transactions
- Receipt scanning via the website's `/api/gemini` endpoint (no API key in the app)
- Groups and bill splitting with live balances and settle-up
- Analytics (monthly trend, top categories)
- Profile: currency, budget, dark/light mode, AI insights opt-in, data export, account deletion
- Legal pages (Privacy, Terms, Impressum) shown from the website in an in-app web view

## Run

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://your-domain
```

`API_BASE_URL` is the deployed web app (hosts `/api/gemini` and the legal pages).
Without it the app works, but receipt scanning, AI tips and legal pages are unavailable.

## Build

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-domain
```

## Checks

```bash
flutter analyze
flutter test
```
