<div align="center">

# Hotify

A Mac and iPhone app for your self-hosted [Coolify](https://coolify.io).

![macOS 26.6](https://img.shields.io/badge/macOS-26.6-black?logo=apple)
![iOS 18.6](https://img.shields.io/badge/iOS-18.6-black?logo=apple)
![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![Coolify 4.3.x](https://img.shields.io/badge/Coolify-4.3.x-6B16ED)

</div>

> [!NOTE]
> Hotify is not an official Coolify app, and the Coolify team has nothing to do with it. I started it because I wanted it for my own servers.

## What it does

- Connect as many Coolify instances as you like. Tokens live in the Keychain.
- See your team, Coolify version, server status, and services at a glance.
- Start, stop, and restart services.
- Works over plain `http` on your LAN too.

Hotify supports Coolify 4.3.x. Older versions aren't tested. It uses Coolify's HTTP API, so it can do what the API can do. The [OpenAPI spec](https://github.com/coollabsio/coolify/blob/main/openapi.yaml) lists what that is.

## What's next

- [ ] Face ID to lock connected servers
- [ ] Applications, databases, deployments, previews, and logs
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
