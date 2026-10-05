<div align="center">

<img src="Hotify/Resources/Assets.xcassets/Logo.imageset/logo.png" alt="Hotify" width="160">

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

- **Instances.** Connect as many Coolify instances as you like, over `https` or plain `http` on your LAN. Tokens live in the Keychain. Instances sync between your devices through iCloud.
- **Dashboard.** Your team, Coolify version, and servers, then every application, database, and service by project and environment. Filter by name, state, kind, or tag. A resource's settings can assign its tags. Opening a server validates it, runs Docker cleanup, restarts the proxy, and edits the proxy's redirect and configuration. A server page can add, rename, and delete a Docker network. A server can be marked as using a Cloudflare Tunnel, and Hotify does not install cloudflared.
- **Actions.** Start, stop, restart, and deploy, or cancel a deployment that is running. One container in a service can be started, stopped, or restarted on its own. Roll an application back to an image Coolify kept from an earlier deployment, or deploy any commit or image tag, once or pinned.
- **Resources.** Logs per container, deployment history, and a database's backups. Create a schedule there, or run Back Up Now. S3 backup stores are in Settings. A resource's Storage tab manages volumes and file mounts and can schedule a volume backup. Edit the name, domains, health check, an application's branch, pinned commit, or image tag, and a database's public port. An application's settings can edit its proxy labels.
- **Place.** A resource can be moved to another environment, cloned, or migrated to another server.
- **Scheduled tasks.** Applications and services can run a command on a schedule. Each task keeps its history, and Run Now starts one immediately.
- **Projects.** A page per project with its resources, recent deployments, previews, and shared variables. Shared variables also exist for the team and for a server, and values stay behind the same lock. Add environments, rename things, and give projects and environments a color.
- **Removal.** A resource, project, or environment can be deleted, and volume deletion stays off until you turn it on.
- **New services and databases.** Pick one of Coolify's one-click templates, place it, set its domains, and watch its first start. Or create a database of any engine Coolify offers, and copy its connection string once Face ID allows. Or create an application from a public repository, a Dockerfile, a Docker image, a GitHub App, or a deploy key.
- **Pull request previews.** Deploy a preview for a pull request, browse the live ones, and read their logs. A GitHub token is optional, for private repositories.
- **Variables.** Edit them, with values hidden until Face ID, Touch ID, or your passcode unlocks them. Copy them from one resource to another, across instances too.
- **Failed deployments.** Apple Intelligence explains what went wrong. It runs on the device, so the log never leaves it.
- **Widgets.** Up to six pinned resources you can start and stop, an instance's status, what needs attention, recent deployments, and backups. Control Center gets a toggle and a restart button.
- **Menu bar.** On the Mac, keep an eye on chosen resources from the menu bar.
- **Notifications.** On the Mac, hear when a deploy fails or finishes, a resource stops or turns unhealthy, a backup fails or runs late, or a server drops, per instance and per event. A failed deploy offers Explain and Roll Back. Hotify checks while it runs. On iPhone, a deploy you start shows as a Live Activity on the Lock Screen and in the Dynamic Island.

Hotify supports Coolify 4.3.x. Older versions aren't tested. It uses Coolify's HTTP API, so it can do what the API can do. The [OpenAPI spec](https://github.com/coollabsio/coolify/blob/main/openapi.yaml) lists what that is.

## What's next

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
Hotify/          SwiftUI app
HotifyWidgets/   Widgets and controls, a WidgetKit extension
Shared/          Code and colors that both the app and the widgets build
CoolifyAPI/      Swift package with the Coolify client and its tests
```
