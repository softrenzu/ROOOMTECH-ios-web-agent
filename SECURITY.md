# Security

Do not commit Anthropic API keys or user credentials.

The prototype stores the Anthropic API key in iOS Keychain. For a production release, route model requests through an authenticated backend and keep provider secrets server-side.
