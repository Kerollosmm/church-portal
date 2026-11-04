# Resolve GitHub Secret Scanning Alert #1 Implementation Plan

> Implementation plan reference document for resolving secret scanning alert #1.

**Goal:** Fix and resolve GitHub Secret Scanning Alert #1 (`https://github.com/Kerollosmm/church-portal/security/secret-scanning/1`) by eliminating raw secret strings from GitHub Actions workflows, clarifying public Firebase client API key configuration, documenting Google Cloud Console API key restriction best practices, and marking the GitHub Secret Scanning alert as resolved (`false_positive`).

**Architecture:** 
1. Avoid raw API key string literals in CI/CD workflows (`.github/workflows/seed.yml`) by sourcing the key via GitHub secrets/variables with an automated extraction fallback from `lib/firebase_options.dart`.
2. Keep `lib/firebase_options.dart` conforming to the FlutterFire standard where client API keys serve as public client identifiers, backed by Firebase Security Rules (`firestore.rules`) and Firebase App Check.
3. Resolve GitHub Secret Scanning Alert #1 via GitHub REST API (`PATCH /repos/Kerollosmm/church-portal/secret-scanning/alerts/1`) with the standard Google/Firebase `false_positive` classification.
4. Update `documentation/operations.md` and `docs/memory-bank/05-firebase.md` to document secret scanning resolution and GCP API key restrictions.

**Tech Stack:** GitHub Actions, GitHub REST API / GitHub CLI (`gh`), Flutter / Dart, Firebase / Google Cloud Platform.

**Spec:** GitHub Secret Scanning Alert #1 (`https://github.com/Kerollosmm/church-portal/security/secret-scanning/1`) & Firebase API keys security specification ([Firebase Docs: Use API keys with Firebase](https://firebase.google.com/docs/projects/api-keys)).

## Global Constraints
- Preserve Golden Rule 8: Keep `flutter analyze` clean and all tests green.
- Preserve Golden Rule 11: PR that changes workflows or operations must update matching Arabic documentation in `documentation/operations.md` and `docs/memory-bank/`.
- Do not break existing developer flows (`flutter run -d chrome`, seed workflow, hosting deployment).

## Review Focus
- Secret Scanning Alert #1 state transitions to `resolved` with resolution `false_positive`.
- No raw `AIza...` key hardcoded in `.github/workflows/seed.yml`.
- `.github/workflows/seed.yml` continues to successfully send password-reset emails if `admin_email` input is supplied.
- `lib/firebase_options.dart` remains valid Dart and compiles without analysis warnings.
- Documentation accurately reflects Google Cloud API key restrictions for the project.

---

## User Review Required
> [!NOTE]
> **Firebase Client API Keys are Public by Design**
> Per [Firebase Documentation](https://firebase.google.com/docs/projects/api-keys): Firebase API keys are not secrets used for server authorization. They identify the project to Google backend services and are compiled directly into public client JavaScript and mobile app bundles. Database security is strictly enforced by Firestore Security Rules and App Check.
> 
> GitHub Secret Scanning flags all strings matching `AIza...` generically as "Google API Key". Resolving this alert on GitHub as `false_positive` is the official and recommended resolution for Firebase client options.

> [!TIP]
> **Recommended GCP Console Action (Optional, in Google Cloud Console)**
> For defense in depth, we recommend verifying in Google Cloud Console -> APIs & Services -> Credentials for the Browser Key:
> 1. **Application restrictions**: Restrict HTTP referrers to `https://maximos-domadios-church.web.app/*`, `https://maximos-domadios-church.firebaseapp.com/*`, `https://asafra-church-portal.web.app/*`, `https://asafra-church-portal.firebaseapp.com/*`, and `http://localhost:*`.
> 2. **API restrictions**: Restrict APIs to Identity Toolkit API, Token Service API, Cloud Firestore API, and Firebase App Check API.

---

## Open Questions
*None. The GitHub secret scanning alert and repository requirements are fully defined.*

---

## Proposed Changes

### Component 1: CI/CD Workflows (`.github/workflows/`)

#### [MODIFY] `.github/workflows/seed.yml`
- Remove the hardcoded raw key `AIzaSyBEHiTY84sHSgLeV_cZ8p-kiKX-IWivByU` from line 70.
- Read `FIREBASE_WEB_API_KEY` from `secrets.FIREBASE_WEB_API_KEY || vars.FIREBASE_WEB_API_KEY`, falling back dynamically to extracting the key from `lib/firebase_options.dart` if not provided in the environment.
- This prevents GitHub Secret Scanning from detecting raw key literals in GitHub Actions workflow files.

```yaml
      - name: Email set-password link to admin
        if: inputs.admin_email != ''
        env:
          ADMIN_EMAIL: ${{ inputs.admin_email }}
          ENV_API_KEY: ${{ secrets.FIREBASE_WEB_API_KEY || vars.FIREBASE_WEB_API_KEY }}
        run: |
          # Public web API key (defined in lib/firebase_options.dart); Firebase emails the reset link.
          case "$ADMIN_EMAIL" in *[!A-Za-z0-9@._+-]*) echo "invalid email"; exit 1;; esac
          API_KEY="$ENV_API_KEY"
          if [ -z "$API_KEY" ]; then
            API_KEY=$(sed -n "s/.*apiKey: *['\"]\([^'\"]*\)['\"].*/\1/p" lib/firebase_options.dart | head -1)
          fi
          if [ -z "$API_KEY" ]; then
            echo "::error::Could not determine Firebase web API key"
            exit 1
          fi
          curl -sf -X POST "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${API_KEY}" \
            -H 'Content-Type: application/json' \
            -d "{\"requestType\":\"PASSWORD_RESET\",\"email\":\"$ADMIN_EMAIL\"}" > /dev/null && echo "Set-password email sent"
```

---

### Component 2: GitHub Secret Scanning Alert Resolution

#### [ACTION] Resolve Alert #1 via GitHub REST API
- Execute:
```bash
gh api --method PATCH /repos/Kerollosmm/church-portal/secret-scanning/alerts/1 \
  -f state=resolved \
  -f resolution=false_positive \
  -f resolution_comment="Firebase client API key (AIzaSy...) is a public client identifier by design (per Google/Firebase documentation https://firebase.google.com/docs/projects/api-keys). Access is enforced by Firebase Security Rules and App Check."
```

---

### Component 3: Documentation & Memory Bank

#### [MODIFY] `docs/memory-bank/05-firebase.md`
- Document GitHub Secret Scanning Alert #1 resolution and explain why GitHub flags `AIza...` keys.
- Document GCP Console API key restriction guidelines (HTTP referrers and API restrictions).

#### [MODIFY] `documentation/operations.md`
- In Section 1 (الأسرار والمتغيرات) and Section 5 (أمان ومشاكل شائعة):
- Add an Arabic guide explaining GitHub Secret Scanning alerts for Firebase keys, confirming it is a public identifier, and noting the resolution as `false_positive` alongside GCP API key restrictions.

---

## Verification Plan

### Automated Tests
1. Verify Flutter analysis passes:
   ```bash
   flutter analyze
   ```
2. Verify all Flutter unit tests pass:
   ```bash
   flutter test
   ```
3. Verify Secret Scanning alert status via GitHub API:
   ```bash
   gh api /repos/Kerollosmm/church-portal/secret-scanning/alerts/1
   ```
   *Expected output: `"state": "resolved"`, `"resolution": "false_positive"`.*

### Manual Verification
1. Inspect `git diff` to ensure no unintended changes.
2. Confirm `.github/workflows/seed.yml` syntax is valid YAML.
3. Review `https://github.com/Kerollosmm/church-portal/security/secret-scanning/1` to verify the alert is closed on GitHub.
