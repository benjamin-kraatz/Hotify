# Hotify

Hotify is a SwiftUI app for macOS and iOS that manages a self-hosted [Coolify](https://coolify.io) instance through its HTTP API. It is a personal project, not an official Coolify app. It targets Coolify 4.3.x. The [OpenAPI spec](https://github.com/coollabsio/coolify/blob/main/openapi.yaml) is the reference for endpoints and payloads, but the live API does not always match it.

## Project map

- `Hotify/` is the app target.
  - `App/` has the entry point.
  - `Dashboard/` shows the selected instance and its services.
  - `Instances/` adds, lists, and persists instances.
  - `Storage/` wraps the Keychain.
- `CoolifyAPI/` is a local Swift package the app depends on.
  - `Client/` has `CoolifyClient` and one `CoolifyClient+<Group>.swift` extension per endpoint group.
  - `HTTP/` has URL normalization and errors.
  - `Decoding/` has the lenient decoding helpers.
  - `Models/` has one file per Coolify type.

`Hotify/` is a synchronized folder in Xcode. New files there join the target on their own, so do not edit `project.pbxproj` to add them.

## Build and test

```sh
# Package tests. Run these after any change in CoolifyAPI/.
cd CoolifyAPI && swift test

# App build. Run this after any change in Hotify/.
xcodebuild -project Hotify.xcodeproj -scheme Hotify -destination 'platform=macOS' build
```

The live tests in `LiveCoolifyTests.swift` skip unless `COOLIFY_LIVE_TESTS=1` is set. They need a real instance and read `COOLIFY_DEMO_INSTANCE_BASE_URL` and `COOLIFY_DEMO_INSTANCE_API_KEY` from the environment or `.env`. Do not run them unless the user asks.

## Rules

### Code layout

- Group code by feature, following the map above. Put a new file in the folder that owns its feature.
- Give a file one responsibility. If you add a second one, split the file.
- A new Coolify type goes in `Models/<Type>.swift`. Its endpoints go in `Client/CoolifyClient+<Group>.swift`.
- Match the code around you. Read a neighboring file before you write a new one.

### Coolify API quirks

- The API returns the same field as a string, number, or bool depending on the endpoint, and booleans often come as `0` and `1`. Decode such fields with `flexString`, `flexInt`, and `flexBool` from `Decoding/FlexDecoding.swift`, not with plain `decode`.
- Use `CoolifyJSON.decoder()` for responses. It converts snake_case keys.
- Pass path parameters through `CoolifyURL.encodePathComponent`.
- When the live API disagrees with the OpenAPI spec, the live API wins. Leave a comment that names the quirk.

### Secrets

- API tokens live in the Keychain via `TokenStore`, never in UserDefaults, files, or logs.
- Do not print or log a token, and keep it out of any `description`.
- `.env` holds a real token. Never read it into output, commit it, or copy its values anywhere.

### Documentation

- Every public type gets a `///` summary.
- A public method gets a `///` summary when it does more than its name says, for example when it has default query flags or polls.
- Comment a branch when the reason is not visible in the code, such as a Coolify quirk, a Keychain constraint, or a value picked to avoid a side effect. Do not comment what the code already says.

### SwiftUI previews

- Add a `#Preview` to every view that has its own state or layout.
- Previews take plain values. They must not need a live instance, a token, or the network.

### Tests

Add a test when the behavior is easy to break and costly to miss. That means:

- URL normalization in `CoolifyURL`.
- Payload quirks, using a JSON fixture of the odd shape.
- The request shape of every write: method, path, query, and body. Use the `MockURLProtocol` setup in `CoolifyAPITests.swift`.

Skip tests for plain getters and views. The build covers those.

### Commits

- Use a conventional subject: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, or `chore:`.
- Keep the subject short, lowercase after the prefix, with no trailing period.
- Only commit or push when the user asks.
