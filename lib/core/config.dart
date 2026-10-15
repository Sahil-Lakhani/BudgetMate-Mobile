/// Origin of the deployed web app that hosts `POST /api/gemini` (Vercel). Override with
/// `--dart-define=API_BASE_URL=https://…` (e.g. a preview deployment).
/// Only used when [geminiApiKey] is empty; the server verifies the Firebase ID token.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://budget-mate-two.vercel.app');

/// Gemini API key (same as GEMINI_API_KEY in the web app's .env), read at build time from the
/// gitignored env.json: `flutter build apk --dart-define-from-file=env.json`. When set, receipt
/// scanning and AI tips call Gemini directly instead of going through [apiBaseUrl].
const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// Public legal pages on the website (Privacy / Terms / Contact).
const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: apiBaseUrl);

/// Google OAuth "Web client" id from the Firebase project (client_type 3 in
/// google-services.json). Android Credential Manager needs it to mint an ID token
/// that Firebase Auth accepts.
const googleServerClientId = '713587752268-r6sqla7754nvp1g3kpp21tkq5unoh8e9.apps.googleusercontent.com';
