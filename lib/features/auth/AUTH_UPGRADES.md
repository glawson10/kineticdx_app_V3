# Clinician Auth Upgrades

## What was implemented

- **Email/password** sign-in and **Forgot password** (unchanged behaviour; reset now via `AuthController.sendPasswordReset`).
- **Google Sign-In**: "Continue with Google" on the login page; cancellation is handled without error spam.
- **Magic link**: "Email me a sign-in link" sends a link; **MagicLinkSentScreen** shows confirmation; opening the link completes sign-in (via **DeepLinkService** at startup and stored email in SharedPreferences).
- **MFA (SMS)**: If the user has MFA enabled, **MfaChallengeScreen** is shown after first factor; user enters SMS code and sign-in completes. **SecurityScreen** (under Clinic settings → Security) allows enrolling/unenrolling a phone second factor.
- **Membership enforcement**: After any sign-in, **AuthGate** checks clinic membership (for portal `/c/{clinicId}`). If not a member → sign out and show "Not authorised for this clinic." No change to global data or `/public/**` writes.

## Files touched

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `google_sign_in`, `app_links` |
| `lib/features/auth/auth_controller.dart` | Extended: `SignInResult` (success/failure/requiresMfa), `sendPasswordReset`, `signInWithGoogle`, `sendSignInLink` / `signInWithEmailLink`, magic-link email storage |
| `lib/features/auth/login_page.dart` | Uses `SignInResult`, adds Google + magic link buttons, pushes **MfaChallengeScreen** on MFA required |
| `lib/features/auth/magic_link_sent_screen.dart` | New: confirmation after sending magic link |
| `lib/features/auth/mfa/mfa_challenge_screen.dart` | New: SMS code entry and `resolver.resolveSignIn` |
| `lib/features/settings/security_screen.dart` | New: MFA enroll (phone) and unenroll |
| `lib/services/deep_link_service.dart` | New: `handleInitialLink()` for email link at app start; web fallback using `Uri.base` |
| `lib/main.dart` | Calls `DeepLinkService().handleInitialLink()` before `runApp` |
| `lib/features/clinic_settings/clinic_profile_screen.dart` | Added Security list tile → **SecurityScreen** |

## Membership enforcement

- Implemented in **AuthGate** (`lib/app/auth_gate.dart`): after sign-in, `_runAfterSignIn` calls `MembershipsRepository.getClinicMembership(clinicId, uid)` when `AuthGate.clinicId` is set (clinic portal). If no active member → `FirebaseAuth.instance.signOut()` and `_notAuthorisedError = 'Not authorised for this clinic.'`; **LoginPage** shows that message.
- Canonical path: `clinics/{clinicId}/members/{uid}`; legacy: `clinics/{clinicId}/memberships/{uid}` (repo checks both). No global patient data; no client writes to `/public/**`.

---

## Firebase Console setup checklist

### Google Sign-In

1. **Authentication → Sign-in method**: enable **Google**.
2. **Android**: Add your app’s **SHA-1** and **SHA-256** (and any build variants) in Project settings → Your apps.
3. **iOS**: Ensure **GoogleService-Info.plist** is in the app and **REVERSED_CLIENT_ID** is in **Info.plist** (URL scheme for Google sign-in).

### Email link (magic link)

1. **Authentication → Sign-in method**: enable **Email/Password** and turn on **Email link (passwordless sign-in)**.
2. **Authorized domains**: Add the domain that will open the link (e.g. `kineticdx-app-v3.web.app`, and for local dev `localhost` if you test there).
3. **ActionCodeSettings**: The app uses a single link domain (see `AuthController._defaultLinkDomain`). For local dev you can pass a custom `linkDomain` when calling `sendSignInLink` (e.g. `http://localhost:port`).

### MFA (SMS second factor)

1. **Authentication → Sign-in method → Advanced**: enable **SMS Multi-factor Authentication**.
2. **Phone authentication**: Ensure **Phone** is enabled (used for SMS codes).
3. (Recommended) Add **test phone numbers** to avoid throttling during development.
4. **Web**: Add your app domain under **Authorized domains** (and **OAuth redirect domains** if applicable).
5. **Note**: MFA is not supported on **Windows** in Flutter Firebase Auth.

---

## Testing checklist

- [ ] **Email/password**: Sign in with valid credentials; wrong password shows error.
- [ ] **Forgot password**: Enter email → "Forgot password?" → password reset email sent and snackbar shown.
- [ ] **Google**: "Continue with Google" → success; cancel picker → no error spam.
- [ ] **Magic link**: Request link → open email link on same device → sign-in completes; open link without stored email → user can request link again.
- [ ] **MFA**: Enroll in Security screen → sign out → sign in → MFA challenge → enter code → signed in.
- [ ] **Membership**: Sign in with a user that is **not** in `clinics/{portalClinicId}/members` (or memberships) → forced sign out and "Not authorised for this clinic."
