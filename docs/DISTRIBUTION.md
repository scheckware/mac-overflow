# Distribution & notarization

Mac Overflow ships signed with **Developer ID Application: Ben Scheck (P8ME3DR3G6)**
+ hardened runtime, then **notarized + stapled** so it opens with no Gatekeeper
warning on any Mac. This doc covers the one-time credential setup for local and CI
notarization.

## One-time: create an App Store Connect API key

Notarization authenticates with an **App Store Connect API key** (`.p8`). Get one at
<https://appstoreconnect.apple.com> → **Users and Access** → **Integrations** tab →
**App Store Connect API** → **+** to generate a key.

- **Which type of key:** **Team key** (not an Individual key), under the **App Store
  Connect API** section.
- **Which role:** **Developer**. That is the minimum role allowed to notarize.
  (Roles below it — Customer Support, Finance, Marketing, Sales — can't. Admin/App
  Manager also work but grant far more than needed; use **Developer**.)
- After creating: **download the `.p8` once** (Apple only lets you download it a
  single time — store it safely), and note the **Key ID** and the **Issuer ID**
  (shown at the top of the Keys page).

You must be the **Account Holder or an Admin** of the Apple Developer account to
generate keys; the key it produces should be assigned the **Developer** role.

## Local notarization (your Mac)

Store the key once as a keychain profile named `MacOverflow`:

```sh
xcrun notarytool store-credentials "MacOverflow" \
  --key /path/to/AuthKey_XXXXXXXXXX.p8 \
  --key-id  <KEY_ID> \
  --issuer  <ISSUER_ID>
```

Then, to produce a fully shareable build:

```sh
make dist      # build + Developer ID sign + notarize + staple + DMG/ZIP
```

Individual steps are also available: `make app`, `make notarize`, `make dmg`.
`scripts/notarize.sh` uses the `MacOverflow` keychain profile by default (override
with `NOTARY_PROFILE`).

## CI notarization (GitHub Actions)

`release-workflow.yml` signs + notarizes automatically on release. Add these five
**repository secrets** (Settings → Secrets and variables → Actions):

| Secret | What it is | How to produce |
|---|---|---|
| `DEVELOPER_ID_CERT_P12` | Developer ID Application cert + private key, base64 | Export from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password you set on that `.p12` export | — |
| `NOTARY_KEY_P8` | The App Store Connect `.p8`, base64 | `base64 -i AuthKey_XXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | The key's **Key ID** | From App Store Connect |
| `NOTARY_ISSUER_ID` | The **Issuer ID** | From App Store Connect |

The workflow imports the cert into a temporary keychain, signs with Developer ID +
hardened runtime, notarizes + staples via `scripts/notarize.sh` (API-key mode), then
packages the stapled `.app` into the release ZIP + DMG.

## Verifying a build is shareable

```sh
spctl -a -vvv build/MacOverflow.app     # -> accepted / source=Notarized Developer ID
xcrun stapler validate build/MacOverflow.app
```

If `spctl` says `rejected / Unnotarized Developer ID`, the app is signed correctly
but not yet notarized — run `make notarize` (or `make dist`).
