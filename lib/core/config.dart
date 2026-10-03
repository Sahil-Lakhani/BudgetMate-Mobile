/// Origin of the deployed web app that hosts `POST /api/gemini` (Vercel), e.g.
/// `flutter run --dart-define=API_BASE_URL=https://budgetmate.example`.
/// No Gemini key lives in the app: the server verifies the Firebase ID token.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Public legal pages on the website (Privacy / Terms / Impressum).
const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: apiBaseUrl);

/// Google OAuth "Web client" id from the Firebase project (client_type 3 in
/// google-services.json). Android Credential Manager needs it to mint an ID token
/// that Firebase Auth accepts.
const googleServerClientId = '713587752268-r6sqla7754nvp1g3kpp21tkq5unoh8e9.apps.googleusercontent.com';
