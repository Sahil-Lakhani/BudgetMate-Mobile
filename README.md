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
cp env.example.json env.json   # put the GEMINI_API_KEY from the web app's .env here
flutter run --dart-define-from-file=env.json
```

With `GEMINI_API_KEY` in `env.json` (gitignored), receipt scanning and AI tips call Gemini
directly. Without it they go through the web app's `/api/gemini`
(`https://budget-mate-two.vercel.app`, override with `--dart-define=API_BASE_URL=…`), which
also serves the legal pages.

## Build

```bash
flutter build apk --release --dart-define-from-file=env.json
```

## Checks

```bash
flutter analyze
flutter test
```
