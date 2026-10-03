# Hotify

Hotify is a SwiftUI app for macOS and iOS that manages a self-hosted [Coolify](https://coolify.io) instance through its HTTP API. It is a personal project, not an official Coolify app. It targets Coolify 4.3.x. The [OpenAPI spec](https://github.com/coollabsio/coolify/blob/main/openapi.yaml) is the reference for endpoints and payloads, but the live API does not always match it.

## Project map

- `Hotify/` is the app target.
  - `App/` has the entry point.
  - `Design/` has the app's look: the stokable flame and its fire, heat edges, wells, and the filter field.
  - `Configuration/` is a resource's Settings tab: its name and description, an application's source (branch, pinned commit, deploy on push, or image tag), its domains, a database's public port, and its health check, in one form with one Save.
  - `Dashboard/` shows the selected instance, its applications, databases, and services, and the deployments and logs for one resource.
  - `Intelligence/` explains a failed deployment with the on-device Apple Intelligence model. Nothing in it may send a log off the device.
  - `Instances/` adds, lists, and persists instances, and shows the welcome screen.
  - `Previews/` deploys, lists, and manages an application's pull request previews. It opens from the Previews toolbar menu and takes over the detail column.
  - `Notifications/` tells you, on the Mac, when a deploy fails or finishes, a resource stops or turns unhealthy, a backup fails or runs late, or a server drops. It checks each instance whose notifications are on every 30 seconds while Hotify runs, and a click opens the place through a `hotify://` link. `LocalActions` remembers what this device started, which tells your own deploys from a push.
  - `Projects/` shows one project: its resources by environment, the previews of all its applications, and the variables the project and its environments share. It opens from the project's head in the dashboard and takes the detail column. A resource opened from it offers the way back. It also holds the colors you give projects and environments: `PlaceColors` keeps them per instance, on the device and in iCloud key-value storage, since Coolify has no such field.
  - `Versions/` changes which version of an application runs. The toolbar's Versions menu rolls back to an image Coolify kept, and Roll Back to This does the same from a deployment. Deploy a Version deploys any commit or image tag, once or pinned, and lists a GitHub branch's recent commits to pick from.
  - `Provisioning/` creates services from Coolify's one-click templates: a gallery, then placement, setup, and the first start, in one sheet that opens from a project page's New Service button, its ⇧⌘N in the Project menu, or an empty dashboard. From a project, the sheet starts in that project, on the server that runs most of it.
  - `Variables/` lists and edits a resource's environment variables, and holds `VariableLock`, which hides their values behind Face ID, Touch ID, or the passcode.
  - `Settings/` has the Settings window on the Mac and the Settings sheet on iOS.
  - `Storage/` holds the GitHub token.
- `HotifyWidgets/` is the WidgetKit extension: the Pinned Resources, Instance, Needs Attention, Recent Deployments, and Backups widgets, and two Control Center controls.
  - `Status/` reads pinned resources from Coolify and keeps `WidgetLedger`, what the widgets remember between timelines in the App Group.
  - `Configuration/` has the entities a widget or control is set up with.
  - `Actions/` runs a widget's buttons. Stop arms on the first tap and goes on the second.
  - `Pinned/`, `Pulse/`, `Attention/`, `Deployments/`, `Backups/`, and `Controls/` each hold one widget kind and its views.
- `Shared/` is built into both the app and the extension. Keep it free of anything only the app has.
  - `Design/` has the brand look both draw with: the flame glyph, `Heat`, the heat strip, and the display font. The brand colors are in `Colors.xcassets`.
  - `Resource/` has `ResourceSummary`, its route, place, actions, and transitions, and how a deployment's status reads.
  - `Backups/` reads backup runs and schedules, including when one is overdue.
  - `Storage/` wraps the Keychain and the App Group.
  - `Widgets/` has the `hotify://` resource link, which can point at a place inside a resource, such as one deployment or the rollback confirmation, and the call that reloads every widget.
- `CoolifyAPI/` is a local Swift package the app depends on.
  - `Client/` has `CoolifyClient` and one `CoolifyClient+<Group>.swift` extension per endpoint group.
  - `HTTP/` has URL normalization and errors.
  - `Decoding/` has the lenient decoding helpers.
  - `Templates/` reads Coolify's template catalog from its CDN, since the API has no template endpoint, and outlines a template's compose file.
  - `Models/` has one file per Coolify type.

`Hotify/`, `HotifyWidgets/`, and `Shared/` are synchronized folders in Xcode. New files join their targets on their own, so do not edit `project.pbxproj` to add them.

## Build and test

```sh
# Package tests. Run these after any change in CoolifyAPI/.
cd CoolifyAPI && swift test

# App build. Run this after any change in Hotify/.
xcodebuild -project Hotify.xcodeproj -scheme Hotify -destination 'platform=macOS' build

# Format, then lint. CI does not check formatting, so run these before you commit. The config is in .swift-format.
swift format format -i --recursive --parallel Hotify HotifyWidgets Shared CoolifyAPI/Sources CoolifyAPI/Tests CoolifyAPI/Package.swift
swift format lint --strict --recursive --parallel Hotify HotifyWidgets Shared CoolifyAPI/Sources CoolifyAPI/Tests CoolifyAPI/Package.swift
```

GitHub Actions (`.github/workflows/ci.yml`) validates releases and publishes tags. Xcode Cloud owns app builds on main and iOS/macOS distribution from tags. GitHub tagging does not wait for Xcode Cloud builds. Run the local checks above when changing app or API code.

The app target runs `scripts/write_build_info.sh` on every build and archive to embed `BuildInfo.json`. The About view reads its commit SHA separately from the marketing version and Cloud-managed build number.

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
- The widgets read tokens through the shared Keychain group, not the App Group. Other apps share the App Group, so put nothing secret there, and start every key with `hotify.`.
- `.env` holds a real token. Never read it into output, commit it, or copy its values anywhere.

### Documentation

- Every public type gets a `///` summary.
- A public method gets a `///` summary when it does more than its name says, for example when it has default query flags or polls.
- Comment a branch when the reason is not visible in the code, such as a Coolify quirk, a Keychain constraint, or a value picked to avoid a side effect. Do not comment what the code already says.

### Look and feel

- The window has three columns: instances, the selected instance's resources, then the open resource or project. iPhone pushes them as a stack.
- The dashboard groups by project, then by environment. A project's head has the name on a line of its own, so it is the last thing cut short, with a bar of heat under it, and opens the project's page. Each environment is named above its own resources, with how many of them run. On the Mac a `ProjectGroup` draws the head on the column and one panel per environment, in a scroll view, and the open row shows as a tinted pill so the flames keep their colors. iOS draws the same sections as a grouped list.
- Move inside the detail column by swapping the screen in place. The view that owns the column's toolbar lists a `DetailNavigation` first, with the screen's title and where back leads. A navigation stack nested in the detail column loses its `.task` on iPhone.
- On the Mac, a column's toolbar items pack at its leading edge. `DetailNavigation` ends in a flexible spacer that sends the actions after it to the trailing edge. A `.searchable` field would take that edge and add a spacer of its own, which leaves the actions in the middle, so the Mac filters the dashboard with a `FilterField` in a `safeAreaBar` above the list. Keep that field out of the list's rows, where a text field draws a box behind its text while it is edited.
- A `FilterField` icon that opens a menu has to filter something. The dashboard's narrows the list by state and by kind, and lights up while a filter is on.
- Show status through `Heat` and `FlameGlyph`. A lit red flame means running, and a grey outline means stopped. Anything starting, unhealthy, or failed glows amber. Never use red for an error.
- Use the asset colors `ember`, `glow`, and `core`, not raw hex. The accent is `ember`.
- A project's or environment's own color, a `PlaceTint`, says where something lives, never how it is doing. Show it as a `PlaceMark` dot beside the name, or wash an `EnvironmentBadge` in it, and read it from the `placePalette` environment value. Anywhere a project or environment is created or edited offers a `PlaceTintPicker`.
- Pull request previews burn blue, like a pilot light. Pass `tone: .preview` to `FlameGlyph` and `heatEdge`, and use `pilot` and `pilotCore` for preview marks, never for production. A building preview keeps its blue body with an amber core. A failed one glows amber like anything else.
- `Font.display` is the only custom type style. Use it for names that head a screen and nothing else.
- Animate a state change the user can act on or should notice. Respect Reduce Motion.

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

### Releases

- For a request to cut or prepare a release, or continue one through merging, read `.agents/skills/hotify-release/SKILL.md`.
- Release operation and recovery details are in `docs/releases.md`. GitHub CI publishes version tags after a marketing-version increase passes release validation on main; agents prepare the PR and merge only when asked.
