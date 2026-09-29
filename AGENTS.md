# Hotify

## Layout

Group code by feature. `CoolifyAPI` uses `Client`, `HTTP`, `Decoding`, and `Models`. The app uses `App`, `Dashboard`, `Instances`, and `Storage`.

Split a file when it has a second responsibility. A type and its endpoint group belong in their own file.

## Documentation

Add a `///` summary on every public type, and on a public method when its behavior is more than its name. Comment a branch when the reason is not visible in the code: a Coolify quirk, a keychain constraint, or a value chosen to avoid a side effect.

## Previews

Add a `#Preview` for a SwiftUI view that has its own state or layout. Pass plain values into the preview so it does not need a live instance.

## Tests

Add a test when the behavior is easy to break and costly to miss. Cover URL normalization, payload quirks, and the request shape of a write. Leave the rest to the build.

## Commits

Use a conventional subject: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, or `chore:`.
