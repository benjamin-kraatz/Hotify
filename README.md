# Hotify

Mac and iPhone app for [Coolify](https://coolify.io). Point it at a self-hosted Coolify 4.3 instance and control it through the HTTP API, as far as that API goes.

Personal project. It will ship on the Mac App Store and the App Store.

## Current app

Save several instances. Each API token is stored in the Keychain. Name and URL are stored in UserDefaults.

The selected instance refreshes every 5 seconds. The screen shows the team name, Coolify version, whether the first server is reachable, and the services. Start, stop, and restart are on each service.

Paste the instance root, an `/api/v1` URL, or the MCP URL from Coolify's settings. The client normalizes all three. `http` and `https` both work, which matters when Coolify is on a LAN.

## API client

`CoolifyAPI` lives in this repo. `CoolifyClient` is one instance and one team-scoped token.

Calls cover version, health, teams, projects, servers, resources, applications, services, databases, deployments, previews, and logs. Actions cover start, stop, restart, deploy, and cancel.

The screen uses services. The other calls are already in the package.

## Next

Face ID will lock the connected servers. The UI still has to show applications, databases, deployments, previews, and logs. Downloads will pull files off the server onto the device.

## Build

Open `Hotify.xcodeproj` in Xcode and run the Hotify target. Swift 6.4. The app targets macOS 26.6 and iOS 18.6. The package supports macOS 15 and iOS 18.

An empty instance list seeds from the environment:

```text
COOLIFY_DEMO_INSTANCE_BASE_URL
COOLIFY_DEMO_INSTANCE_API_KEY
```

Copy `env.example` to `.env`. `.env` is gitignored. The key is a Coolify team API token.

```sh
cd CoolifyAPI
swift test
```

Live tests hit a real instance. Set `COOLIFY_LIVE_TESTS=1` plus the two variables above.

## Layout

- `Hotify/` is the SwiftUI app.
- `CoolifyAPI/` is the Coolify 4.3 client and its tests.
