# Quota

Quota is a minimal SwiftUI app for checking API balances and organization usage across multiple AI providers.

## Supported providers

- DeepSeek
- Kimi / Moonshot
- OpenRouter
- xAI
- OpenAI
- OpenAI Codex (ChatGPT plan usage)
- Anthropic
- Qwen
- Google Gemini

API provider credentials are stored in the iOS Keychain. Configure and enable providers in Settings before they appear on the Usage page. To add Codex, open **Settings → OpenAI**, sign in with the ChatGPT device code, then enable each account you want to show on the Usage page. Codex accounts have independent usage switches and can be signed out individually.

Codex stores OAuth credentials in the iOS Keychain and shows account details when the sign-in token provides them. Its quota cards read Codex's internal usage endpoint, which may change without notice; they do not read token activity logs. OpenAI API organization costs remain a separate provider entry.

## Requirements

- Xcode 15 or newer
- iOS 15.6 or newer

Open `Quota.xcodeproj` in Xcode and run the `Quota` scheme.

## License

This project is released under the [MIT License](LICENSE).
