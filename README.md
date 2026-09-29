<div align="center">

# Hotify

A Mac and iPhone app for your self-hosted [Coolify](https://coolify.io).

![macOS 26.6](https://img.shields.io/badge/macOS-26.6-black?logo=apple)
![iOS 18.6](https://img.shields.io/badge/iOS-18.6-black?logo=apple)
![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![Coolify 4.3](https://img.shields.io/badge/Coolify-4.3-6B16ED)

</div>

> [!NOTE]
> Hotify is not an official Coolify app, and the Coolify team has nothing to do with it. I started it because I wanted it for my own servers. The plan is to put it on the App Store and the Mac App Store.

## What it does

Point Hotify at a Coolify 4.3 instance and manage it from your Mac or iPhone, as far as the HTTP API allows.

You can add several instances. Each API token goes into the Keychain.

The selected instance refreshes every 5 seconds. You see the team name, the Coolify version, whether the first server is reachable, and your services. Every service has start, stop, and restart.

Hotify accepts any of these as the instance URL:

| You paste | Example |
| --- | --- |
| The instance root | `https://coolify.example.com` |
| The API URL | `https://coolify.example.com/api/v1` |
| The MCP URL from Coolify's settings | `https://coolify.example.com/mcp` |

Plain `http` works too, which you'll want if Coolify runs on your LAN.

## What's next

- [ ] Face ID to lock connected servers
- [ ] Applications, databases, deployments, previews, and logs in the UI. The API client already supports them.
- [ ] Downloading files from the server to the device

## Building

Open `Hotify.xcodeproj` in Xcode and run the Hotify target.

If the instance list is empty, the app adds one from these environment variables. Set them in the Xcode scheme. The key is a Coolify team API token.

```text
COOLIFY_DEMO_INSTANCE_BASE_URL
COOLIFY_DEMO_INSTANCE_API_KEY
```

## Tests

```sh
cd CoolifyAPI
swift test
```

The live tests talk to a real instance and only run with `COOLIFY_LIVE_TESTS=1`. They read the two variables above from the environment or from a `.env` file. Copy `env.example` to `.env` to get started. Git ignores it.

## Layout

```text
Hotify/       SwiftUI app
CoolifyAPI/   Swift package with the Coolify client and its tests
```
