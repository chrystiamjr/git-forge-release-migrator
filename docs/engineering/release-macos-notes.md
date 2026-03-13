# Release and macOS Notes

Use this document when changing release workflows or macOS packaging behavior.

## macOS Artifacts

- `gfrm-macos-intel.zip`
- `gfrm-macos-silicon.zip`

CI must continue validating:

- `gfrm-macos-intel` -> `x86_64`
- `gfrm-macos-silicon` -> `arm64`

## Security Modes

- `MACOS_RELEASE_SECURITY_MODE=permissive`
  - warn when signing or notarization credentials are missing
- `MACOS_RELEASE_SECURITY_MODE=strict`
  - fail macOS jobs when signing or notarization credentials are missing or notarization fails

## Notarization Credential Precedence

Preferred App Store Connect API key:

- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_P8_BASE64`

Fallback Apple ID flow:

- `APPLE_NOTARY_APPLE_ID`
- `APPLE_NOTARY_TEAM_ID`
- `APPLE_NOTARY_APP_PASSWORD`

## Related References

- workflow details: `website/docs/project/ci-and-release.md`
- public macOS artifact guidance: `website/docs/guides/macos-release-artifacts.md`
- release workflow: `.github/workflows/release.yml`
