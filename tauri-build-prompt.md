# Prompt: Wrap `roblox-home.html` into a native macOS Tauri app

I have a single self-contained `index.html` file (a Roblox desktop launcher UI — custom nav,
friends list, recently-played rail, a Discover page with category chips and a game grid, and a
"Launching..." toast with a spinning logo). It's plain HTML/CSS/vanilla JS with no build step,
no bundler, and no framework. I need you to wrap it in a native **macOS** desktop app using
**Tauri v2** (Rust + Node/npm), fully wired so every network call and the `roblox://` launch
deep link actually works from inside the packaged app — not just "it displays."

Treat the HTML file I give you as the finished frontend. Don't rewrite its markup, CSS, or JS
logic — only touch it if something in it is *actually incompatible* with the Tauri webview
(e.g. an API that needs a Tauri plugin equivalent), and tell me exactly what you changed and why
if you do.

## 1. Environment (I'm on macOS)

Assume a clean macOS machine and set up prerequisites first:

- Xcode Command Line Tools: `xcode-select --install`
- Rust via rustup: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`, then
  `source "$HOME/.cargo/env"`
- Node.js (LTS) + a package manager (npm is fine, pnpm is fine — pick one and be consistent)
- Add both Apple Silicon and Intel targets so I can build a universal binary later:
  `rustup target add aarch64-apple-darwin x86_64-apple-darwin`
- Install the Tauri CLI as a dev dependency (`@tauri-apps/cli`) rather than globally, so the
  project is self-contained.

Verify everything with `rustc --version`, `cargo --version`, `node --version`, and
`npm create tauri-app@latest --help` before scaffolding.

## 2. Scaffold the project

Create a new Tauri v2 app using the **vanilla/no-framework** template (there is no React/Vue/etc.
— the HTML file *is* the frontend):

```
npm create tauri-app@latest roblox-launcher -- --template vanilla
cd roblox-launcher
npm install
```

Replace the generated `src/index.html` entirely with the `index.html` I provide. Delete any
placeholder JS/CSS files the template created that the HTML doesn't reference (`main.js`,
`styles.css`, etc.) unless the template's `index.html` imports something load-bearing — check
first.

`src-tauri/tauri.conf.json` → `build`:
- `frontendDist`: `"../src"` (or wherever `index.html` ends up — just a static folder, no bundler)
- `devUrl`: point it at the same static folder served by the Tauri dev server (the vanilla
  template already wires this up; don't add Vite/webpack, it isn't needed)
- `beforeDevCommand` / `beforeBuildCommand`: leave empty — there is nothing to compile

## 3. Required Tauri plugins

The HTML's JS talks to `window.__TAURI__.http.fetch` (Roblox + Iconify API calls, to dodge
browser CORS) and `window.__TAURI__.opener.openUrl` / `window.__TAURI__.shell.open` (to hand off
`roblox://experiences/start?placeId=...` to the installed Roblox app). Install and register:

```
cargo add tauri-plugin-http --manifest-path src-tauri/Cargo.toml
cargo add tauri-plugin-opener --manifest-path src-tauri/Cargo.toml
npm install @tauri-apps/plugin-http @tauri-apps/plugin-opener
```

In `src-tauri/src/lib.rs` (or `main.rs`, depending on what the template generated), register both
plugins on the builder:

```rust
tauri::Builder::default()
    .plugin(tauri_plugin_http::init())
    .plugin(tauri_plugin_opener::init())
    // ...existing setup...
```

### Expose the global `window.__TAURI__` object

The HTML calls these plugins off `window.__TAURI__` directly (not via ES module imports), so in
`tauri.conf.json` under `app`, set:

```json
"app": {
  "withGlobalTauri": true
}
```

Without this the `window.__TAURI__` checks in the HTML will just be `undefined` and every code
path will silently fall back to plain `fetch`/`location.href`, which will fail or get blocked by
CORS once the app is packaged — confirm this flag is on and sanity check that
`window.__TAURI__.http` and `window.__TAURI__.opener` are actually populated at runtime, not just
that the build succeeds.

## 4. Permissions / capabilities (this is the part most likely to get silently skipped)

Tauri v2 denies everything by default. You need an explicit capabilities file
(`src-tauri/capabilities/default.json` or similar, referenced from `tauri.conf.json`) granting:

**HTTP** — scope it to exactly the hosts the app calls, don't wildcard the whole internet:
- `users.roblox.com`
- `economy.roblox.com`
- `friends.roblox.com`
- `thumbnails.roblox.com`
- `games.roblox.com`
- `apis.roblox.com` (discovery-api, explore-api, search-api all live under this host)
- `api.iconify.design`

Grant `http:default` plus the fetch permission with a `scope` array of URL patterns for those
hosts (e.g. `"https://games.roblox.com/*"` etc. for each). Look up the current exact permission
identifiers/scope syntax for `tauri-plugin-http` v2 in the official docs before finalizing — plugin
permission schemas have changed between minor versions, don't guess from an older example.

**Opener** — the app needs to open a *custom URL scheme* (`roblox://`), not an `http(s)://` URL.
Grant the opener plugin's "open URL" permission with a scope that explicitly allows the `roblox:`
scheme (something like `{"url": "roblox:*"}` under the permission's `allow` array — again, verify
the exact current syntax against the `tauri-plugin-opener` docs, since URL-scheme scoping for
non-http schemes is a newer feature and easy to get subtly wrong). Confirm this by actually
clicking a launch tile in the built app and checking the Roblox app receives the deep link — don't
just trust that the permission file "looks right."

Note: I'm not asking you to register `roblox://` as *our* app's URL scheme — the Roblox desktop
client already registers that scheme during its own installation. Our app only needs permission
to *open* it via `opener.openUrl`, which hands it to whatever's already registered as the handler.
If Roblox isn't installed on the test machine, launching will correctly no-op/fail — that's
expected, not a bug.

## 5. Content Security Policy

The HTML has an inline `<script>` and inline `<style>`, and makes `fetch()` calls to the hosts
above, and renders `<img>` thumbnails whose `src` comes back from the Roblox thumbnails API
(served off Roblox's CDN domains, typically `*.rbxcdn.com` — confirm the actual host from a real
API response rather than assuming). In `tauri.conf.json` → `app.security.csp`, set a policy that:

- allows `'self'` and `'unsafe-inline'` for `script-src` and `style-src` (the whole app is one
  inline-script HTML file, there's no nonce/hash setup here)
- allows `connect-src` to `'self'` plus all the Roblox API hosts above plus
  `https://api.iconify.design`
- allows `img-src` to `'self' data:` plus the Roblox CDN thumbnail host(s)

Don't set CSP to `null`/disable it entirely just to make things easier — scope it to what the app
actually needs.

## 6. macOS window behavior

This UI draws its own nav bar, logo, and chrome at the top of a 1920×1080 design that scales to
fit the window (see the `fit()` function in the JS — it already handles arbitrary window sizes,
don't fight it with a fixed window size).

In `tauri.conf.json` → `app.windows[0]`:
- `"title"`: something reasonable, e.g. `"Roblox"`
- `"width"` / `"height"`: a sane default like 1280×800, `"resizable": true`, with a `"minWidth"`
  / `"minHeight"` so it can't be crushed small enough to break the layout (e.g. 960×600)
- Since the custom nav bar already looks like app chrome, go for a clean native feel: set
  `"titleBarStyle": "Overlay"` (macOS-only key) so the traffic-light buttons float over our content
  instead of a separate native title bar being added on top of it, and set `"hiddenTitle": true`.
  If you do this, you must add `data-tauri-drag-region` to a suitable top-of-window wrapper
  element (or a thin invisible strip) so the window can still be dragged — without this the window
  becomes un-draggable since there's no native title bar left to grab. Pick an element that won't
  swallow clicks meant for the logo/nav/create button/account area; a thin drag strip behind them,
  or `data-tauri-drag-region` on the background with `pointer-events` carefully excluded from the
  interactive children, both work — use your judgment on the cleanest approach and tell me what
  you chose.
- Add a `"trafficLightPosition"` offset if needed so the stoplight buttons don't visually collide
  with the logo in the top-left (check against the actual coordinates: logo sits at
  `left:65px;top:65px` in the 1920-wide design space before scaling).

## 7. App icons

Generate the full icon set from a single source PNG (at least 1024×1024) using the Tauri CLI:

```
npm run tauri icon path/to/source-icon.png
```

This produces the `.icns` and the various PNG sizes under `src-tauri/icons/` and wires them into
`tauri.conf.json` automatically — confirm it actually updated the `bundle.icon` array.

## 8. Dev + build

- Dev: `npm run tauri dev` — confirm the window opens, the Home page renders with demo data (no
  Roblox cookie set yet), and clicking a "Discover" category pill actually fetches real data (you
  should see real game names/thumbnails, which proves the HTTP plugin + capabilities are wired
  correctly, not just that the app launches).
- Build: `npm run tauri build` — target `dmg` and `app` in `bundle.targets`. Confirm the built
  `.app` in `src-tauri/target/release/bundle/macos/` actually opens standalone (not just via `tauri
  dev`), since capability/CSP misconfigurations sometimes only show up in the packaged build.
- Universal binary (optional, only if I ask for it): build both targets added in step 1 and use
  `tauri build --target universal-apple-darwin`.
- Code signing / notarization: skip entirely for local personal use (an ad-hoc/unsigned build is
  fine, macOS will just show a Gatekeeper warning on first launch). Don't set up a Developer ID
  or notarization pipeline unless I explicitly ask for one later.

## 9. Things to actually test before calling it done

Walk through these in the packaged app, not just `tauri dev`, and tell me the result of each:

1. Home page loads with friends list + recently-played rail (real data if a Roblox cookie's been
   set via `window.setRobloxCookie(...)` in devtools, demo data otherwise).
2. Clicking a recently-played tile that has a real `place` id actually hands off to the installed
   Roblox app via the `roblox://` deep link (confirm Roblox actually receives focus/launches).
3. Clicking a demo tile with no `place` shows the toast ("Demo card, nothing to launch") — it
   should use the same slide-in-from-the-right pill with the spinning Roblox logo (this is the
   current default look for every toast, launch or not — don't reintroduce the old dot-style
   variant).
4. Clicking Discover → category chips actually fetch and render real games (not just skeletons
   forever, which would mean the HTTP plugin/capabilities are misconfigured).
5. Hovering a chip pushes its neighbors smoothly, and if the *selected* (white pill) chip gets
   pushed, the white pill background visibly moves with it, not left behind.
6. Switching categories crossfades the grid instead of flashing empty-card skeletons abruptly.
7. Window resizes cleanly without the layout breaking (the `fit()` scaling should handle this).
8. Window is draggable from the top chrome area despite the native title bar being hidden/overlaid.

Report back specifically on any of these 8 that don't work, rather than just "it builds."

## 10. One security note, flag it, don't silently fix it

The HTML stores the Roblox auth cookie (`.ROBLOSECURITY`) in `localStorage` via
`window.setRobloxCookie()`. That's fine for my own local testing, but it's not using any OS
keychain/secure storage. If you think it's worth swapping to `tauri-plugin-store` or the macOS
Keychain via a Tauri plugin for a hardened version later, mention it as a suggestion — don't
silently change the auth storage mechanism without telling me, since it touches how the cookie
gets set/read.
