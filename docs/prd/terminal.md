# Terminal

Status: phases 1 and 2 built on `feat/terminal`, 2026-10-17, then polished the same day (see "Polish"). Waiting on Benjamin's live check. Cloudflare Tunnel servers are out of scope for now.

## Goal

Open a shell inside a running container, or on a server itself, from Hotify on the Mac and on iPhone. The result should match what Coolify's web terminal gives you.

## Why Hotify goes around Coolify

Coolify 4.3 has no terminal endpoint in its API. Its web terminal runs in a separate Node service at `/terminal/ws`. That service only accepts a browser session cookie and an XSRF token, and only for team admins and owners. An API token can't get in.

So Hotify does what Coolify does behind that WebSocket. It opens SSH to the server and runs `docker exec -it <container> sh`. Coolify's API gives Hotify everything it needs for the connection except the key.

## What the API already gives us

- `GET /servers/{uuid}` returns `ip`, `user`, `port`, and the uuid of the key Coolify connects with. `Server.swift` decodes all of these today.
- `settings.is_terminal_enabled` is in the spec's server settings. Hotify should honor it and offer no terminal on a server where it's off. Coolify enforces that flag in `TerminalSessionService.redeem`.
- `GET /servers/{uuid}/cloudflare-tunnel` says whether the server sits behind a tunnel. Hotify reads this already, and uses it to turn the terminal off for tunneled servers.
- `GET /security/keys/{uuid}` returns the key with `private_key` in the spec. Server responses sometimes nest the material too. `Server.swift` throws it away on purpose today. Coolify hides sensitive fields from tokens without the `read:sensitive` or `root` permission, so even on 4.3 the field may be missing for some tokens.

## Connection

### Libraries

- SSH: Apple's [swift-nio-ssh](https://github.com/apple/swift-nio-ssh), wrapped in a local package, `HotifySSH/`. Citadel was the plan, but it depends on a third-party fork of swift-nio-ssh, and it can't run a command in a PTY, only a shell. Apple's package has no RSA, so the install step only reads Coolify's key when it's ed25519, which Coolify generates by default. Anything else falls back to the manual step. The device key is always ed25519.
- Terminal view: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), pinned to 1.18.x. From 1.19 on it runs a build tool plugin, which Xcode and Xcode Cloud would each have to be told to trust. It runs on AppKit and UIKit, and on iOS it has a key bar for Esc, Ctrl, Tab, and the arrows.

`HotifySSH/` knows nothing about Coolify. The Coolify side, the label filters, the shell lines, and the address, lives in `CoolifyAPI/Sources/CoolifyAPI/Terminal/`, with tests.

### Address

Use `server.ip` and `server.port` as they are, with one exception. The server Coolify itself runs on reports `host.docker.internal` or `localhost`, which only means something from inside Coolify's container. When the address is one of those, or empty, Hotify swaps in the host of the instance's base URL. A Coolify host with a real address keeps it.

Any server's address can be overridden, per server. Each server has its own SSH address, and an instance-wide setting would only ever help the Coolify host. The override holds a host and a port, is keyed by server uuid, and lives in the app's own defaults. It isn't secret, and the widgets don't need it, so it stays out of the App Group. The terminal's connection error offers the override directly, since a wrong address is the likeliest first failure.

### Host key

Coolify connects with `StrictHostKeyChecking=no`. Hotify shouldn't copy that. On the first connection it shows the fingerprint and remembers it per server. Later, if the key changes, it refuses to connect until the user accepts the new one. A fingerprint isn't secret, but it stays out of the App Group anyway because the widgets don't need it.

### Non-root users

When `server.user` isn't `root`, prefix `docker` with `sudo`, as Coolify does.

## The key

Decided: option 1, with the hybrid install step below. The other two options stay here for the record.

1. **A key Hotify makes on the device.** Hotify generates an ed25519 key per device. It goes in the Keychain as this-device-only, not synced, and opens with Face ID, Touch ID, or the passcode through the same `LAContext` path `VariableLock` uses. Hotify shows the public key so you can add it to `authorized_keys`. A lost phone means removing one line on the server. Coolify's own key is untouched.
2. **Use Coolify's key.** Fetch `private_key` from `/security/keys/{uuid}` for each session, keep it in memory only, and drop it when the session ends. There's nothing to set up. But that key is usually root on every server the team has. Hotify would be pulling it onto a phone, and you can't revoke it for one device without breaking Coolify.
3. **Import a key file.** The user picks an existing private key. It's flexible, but it puts private key handling on the user, and on iPhone that's awkward.

A hybrid fixes the setup cost of option 1. On the first terminal to a server, Hotify offers "Install Hotify's key". It fetches Coolify's key once and connects with it. It then appends the device's public key to `~/.ssh/authorized_keys`, tagged with a comment like `hotify-<device name>`, and throws Coolify's key away. Every later session uses the device key. Coolify's key only ever sits in memory for those few seconds, and only when the user asks.

The install step asks for Face ID or the passcode before it fetches Coolify's key, and says what it is about to do on the server.

The install step needs the API to return `private_key`. Hotify doesn't decide this ahead of time. It fetches the key, and if the field is missing or empty, it falls back to the manual step. That step shows the public key with a Copy button and the one-line command to add it. The same fallback covers a token without `read:sensitive`, so the feature never depends on how the API behaves here.

### Unlocking

The device key is the lock. Its Keychain item requires biometry or the passcode, and Hotify asks every time a session starts, reusing no earlier unlock. A terminal gets no `VariableLock` of its own on top. Two prompts in a row for one action would only teach people to tap through them. The key stays in memory from the unlock until a shell opens, so setup steps in between, such as trusting the host key or adding the key, don't ask again. The install step itself asks once more before it fetches Coolify's key.

While a terminal is open, Escape belongs to the shell, so the back button gives up its Escape shortcut there.

## Finding the container

Ask Docker on the server, with the same filters Coolify uses in `dockerPsByOwnerCommands`, tried in order:

- `docker ps --filter label=coolify.<type>Uuid=<uuid>`, for anything deployed by a recent Coolify.
- `--filter label=coolify.<type>Id --filter label=com.docker.compose.project=<uuid>`, for older deploys.
- For applications only, `--filter label=coolify.applicationId --filter name=<uuid>`.

`<type>` is `application`, `service`, or `database`. Add `--format '{{json .}}'` and decode one container per line.

Previews carry `coolify.pullRequestId=<n>`. Production is `0`.

Only running containers get a shell. If a resource has more than one, as a service or a compose app does, Hotify asks which one, as Coolify's page does.

The shell command is Coolify's too. Source `~/.profile` if it's there, then run `$SHELL`, and fall back to `sh` for images without one.

## Who may open it

Hotify doesn't gate the terminal on the API token's permissions. The SSH key in `authorized_keys` decides who gets a shell, as with any SSH client. Coolify limits its web terminal to team admins and owners, but Hotify can't see a user's team role, and a token's permissions say nothing about SSH access. Hotify only hides the terminal where Coolify says it's off, through `is_terminal_enabled`, and on servers behind a Cloudflare Tunnel.

## Where it opens

- A resource's toolbar gets Terminal for applications and databases. It swaps into the detail column like Previews, with a `DetailNavigation` leading back.
- A service's Containers tab gets Open Terminal on each running container.
- The server page gets Terminal for a shell on the host.
- On the Mac, a terminal could also open in its own window, so you can keep it beside the dashboard. That's worth doing once the detail-column version works.

New code lives in `Hotify/Terminal/`, and AGENTS.md's project map gets a line for it.

## Cloudflare Tunnel: deferred

Not in this feature. On a server with `is_cloudflare_tunnel` on, Terminal shows as unavailable with the line "Terminal doesn't support servers behind a Cloudflare Tunnel yet." The wording is "not supported yet", not "not verified". A direct connection to a tunneled server can't work, so nothing is left to verify. Hotify checks the flag before it connects, so a tunneled server never shows a connection error or a timeout.

The rest of this section is the plan for when it comes back.

When `is_cloudflare_tunnel` is on, `server.ip` holds a hostname like `ssh.example.com`. Port 22 is usually closed to the internet. Cloudflare's edge receives the traffic and passes it through the tunnel to `sshd`.

Coolify connects with `ProxyCommand cloudflared access ssh --hostname %h`. cloudflared opens a WebSocket to `https://<hostname>` and carries the raw SSH bytes in binary frames. If a Cloudflare Access policy protects the hostname, the request also needs a `Cf-Access-Token` header, or a service token's `CF-Access-Client-Id` and `CF-Access-Client-Secret`.

Hotify can't run cloudflared. iOS has no subprocesses, and the Mac app is sandboxed. A plain TCP connection to the hostname reaches Cloudflare's edge and gets no SSH on the other side.

So a tunneled server needs its own transport. Hotify opens a `URLSessionWebSocketTask` to `wss://<hostname>` and hands its frames to swift-nio-ssh as the byte stream in place of a TCP socket. That covers a tunnel without Access. With Access, a service token is the practical route. The user creates one in Cloudflare and pastes it into Hotify, which keeps it in the Keychain. Cloudflare's browser login, which `cloudflared access login` does, is possible with `ASWebAuthenticationSession`, but I'd leave it for later.

## Things that will behave differently on iPhone

- iOS suspends the app soon after it leaves the foreground, and the SSH connection dies with it. The terminal should say the session ended and offer to reconnect, not pretend it's still there.
- No hardware keyboard means the SwiftTerm key bar is required, not optional.

## Polish

Built on top of phases 1 and 2, on 2026-10-17, after Benjamin asked for "the best terminal experience". What's there, and why:

- **Keepalive and latency.** `SSHConnection.probe` and `keepAlive(every:timeout:)` send a global request the server has to answer. NIOSSH's generic global request is internal, and OpenSSH's `keepalive@openssh.com` isn't one it knows, so the probe cancels a port forward that was never set up: sshd answers with a failure, which is all a keepalive needs, and logs it only at debug level. Verified against a real sshd in Docker: the reply comes, and sshd's own `ClientAliveInterval` keepalives get a reply from NIOSSH, so a strict server doesn't drop us. Every 15 seconds, 10 seconds to answer. The header shows the round trip. Tests run against an in-process NIOSSH server (`TestServer.swift`).
- **Reconnect over the scrollback.** The canvas stays through a reconnect. When a shell ends, the model prints a dim divider with the reason and the time, after leaving the alternate screen and soft-resetting modes, so a shell that died inside vim doesn't leave the terminal in a strange state. A reconnect goes back into the same container without asking. On iPhone, a shell that was running when the app left reconnects on its own when the app comes back, after one probe to check whether the socket survived.
- **Theme.** `TerminalTheme` has Ember (warm dark, warm light with the app), Ember always dark, and Plain (xterm). The palette uses `ember` for red and the cursor, `glow` for yellow, `pilot` for blue. The chrome inside the canvas (find bar, ended bar) takes the palette's lightness, not the app's, through `colorScheme`.
- **Header.** `TerminalHeader`: `FlameGlyph` for the link (lit connected, amber connecting or dropped, cold exited), container, server · user@host, the OSC 0/2 title when a program sets one, the OSC 7 directory, latency, and the actions.
- **Find** (`FindBar`, ⌘F through Edit > Find on the Mac, the header button everywhere), with "n of m". SwiftTerm's own find bar is bypassed by `HotifyTerminalView`.
- **Paste check** (`PasteCheck`): a paste with more than one line or a control character asks first, with the line count. Newlines go out as Return, like iTerm2. Bracketed paste is honored. Off in Settings.
- **OSC 52** writes to the clipboard (tmux and vim yanks over SSH), never reads it.
- **Bell**: the canvas flashes amber and the phone taps; nothing beeps.
- **Run menu** (`TerminalSnippets`): ps, top, env, df, listening ports, os-release, pwd+ls. Typed with Return. No history; it wasn't worth the state.
- **Text size**: ⌘+ ⌘- ⌘0 on the Mac from the Terminal menu, pinch on iPhone, stepper in Settings. ⌘K clears the scrollback and sends Ctrl-L. ⇧⌘T opens the terminal of the resource on screen.
- **iPhone key bar** (`TerminalKeyBar`): esc, tab, sticky ctrl in ember when armed, ~ | / -, arrows that repeat while held, hide keyboard. Hosted as the terminal's input accessory. SwiftTerm's own bar had F-keys and a touch toggle; dropped on purpose.
- **Right click on the Mac**: Copy, Paste, Select All, Find.
- **Settings**: theme with swatches, text size, Option as Meta (Mac), the paste check.

Left out on purpose: tabs or several sessions per resource, snippet history, copy on select, a separate Mac window (still phase 3).

## Phases

1. Direct SSH with a device key and the manual setup step. Container shells for applications, databases, and service containers. Host key pinning, the address override, and the unavailable state for tunneled servers.
2. The "Install Hotify's key" step, falling back to the manual step when the key material is missing.
3. The server host shell, and a Mac terminal window.

Cloudflare Tunnel support is deferred and has no phase yet.

## Decisions

- Key: a device key, with the install step using Coolify's key once. See "The key".
- The live API returning `private_key` doesn't block anything. The install step falls back to the manual step.
- No gate on the token's permissions. See "Who may open it".
- The address override is per server.
- The device key's prompt is the only lock.
- Cloudflare Tunnel is deferred, and labeled "not supported yet".

## Live check for Benjamin

Before phase 2 ships, check whether 4.3 returns key material to your token. This prints only whether the field is there and how long it is, never the key:

```sh
set -a; source .env; set +a
curl -s -H "Authorization: Bearer $COOLIFY_DEMO_INSTANCE_API_KEY" \
  "$COOLIFY_DEMO_INSTANCE_BASE_URL/api/v1/security/keys" \
  | jq '[.[] | {uuid, has_private_key: ((.private_key // "") | length > 0)}]'
```

If every entry says `false`, phase 2 still ships, and every user goes through the manual step.

## Tests

- Request shape for the key fetch, if the hybrid ships.
- The `docker ps` command builder for each resource type and for previews. It's string assembly with shell quoting, which breaks easily and is costly to get wrong.
- Address resolution for `isCoolifyHost`.
